# frozen_string_literal: true

require_relative "featureparity/version"
require_relative "featureparity/metadata"
require_relative "featureparity/config"
require_relative "featureparity/prompts"
require_relative "featureparity/signature"
require_relative "featureparity/handlers"
require_relative "featureparity/cli"

module Brainiac
  module Plugins
    module Featureparity
      # Supported webhook events from FeatureParity
      SUPPORTED_EVENTS = %w[
        requirement.change_rejected
        requirement.change_approved
        requirement.change_proposed
        requirement.removal_proposed
        requirement.activated
        requirement.archived
        requirement.updated
        requirement.work_started
        requirement.agent_mentioned
        evidence.passing
        evidence.failing
        evidence.suspect
        coverage.gap_detected
      ].freeze

      class << self
        # Called by Brainiac plugin system during server startup.
        #
        # @param app [Sinatra::Application] The running Brainiac server
        def register(app)
          Config.load!

          # Register channel prompt
          Brainiac.register_channel_prompt(:featureparity, Prompts::CHANNEL)

          setup_routes(app)

          LOG.info "[FeatureParity] Plugin registered (webhook: /featureparity)"
          LOG.info "[FeatureParity] Accepting webhooks from environments: #{Config.accept_environments.join(', ')}"
        end

        private

        def setup_routes(app)
          setup_webhook_route(app)
          setup_api_routes(app)
        end

        def setup_webhook_route(app)
          app.post "/featureparity" do
            content_type :json
            request.body.rewind
            # self here is the Sinatra request, so reach the plugin by name.
            status_code, body = Brainiac::Plugins::Featureparity.receive(request.body.read, request.env)
            halt status_code, body
          end
        end

        def setup_api_routes(app)
          app.get "/api/featureparity" do
            content_type :json
            {
              enabled: true,
              api_base_url: Brainiac::Plugins::Featureparity::Config.api_base_url,
              environment: Brainiac::Plugins::Featureparity::Config.environment,
              accept_environments: Brainiac::Plugins::Featureparity::Config.accept_environments,
              supported_events: SUPPORTED_EVENTS
            }.to_json
          end
        end

        public

        # Handle one delivery: verify it, drop a repeat, check where it came from, and hand
        # it to its event's handler. Returns [status, json body].
        def receive(raw_body, env)
          LOG.debug "[FeatureParity] Webhook received: #{raw_body.length} bytes" if LOG.debug?
          refusal = verification_refusal(raw_body, env)
          return refusal if refusal

          payload = JSON.parse(raw_body)
          screened = screen(payload)
          return screened if screened

          reload_projects!
          reload_agent_registry!
          dispatch_event(payload["event"], payload)
        rescue JSON::ParserError => e
          LOG.error "[FeatureParity] Invalid JSON: #{e.message}"
          [400, { error: "Invalid JSON" }.to_json]
        rescue StandardError => e
          LOG.error "[FeatureParity] Unhandled error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
          [500, { error: e.message }.to_json]
        end

        # Signed deliveries (Standard Webhooks): with secrets configured, anything that doesn't
        # verify is refused before it is parsed. FeatureParity retries a delivery under the
        # same webhook-id, so a repeat is acknowledged and dropped.
        def verification_refusal(raw_body, env)
          delivery_id = env["HTTP_WEBHOOK_ID"]
          secrets = Config.signing_secrets
          if secrets.empty?
            LOG.warn "[FeatureParity] Accepting an unverified delivery: set signing_secrets in featureparity.json"
          elsif !Signature.valid?(secrets: secrets, id: delivery_id, timestamp: env["HTTP_WEBHOOK_TIMESTAMP"],
                                  signature: env["HTTP_WEBHOOK_SIGNATURE"], body: raw_body)
            LOG.warn "[FeatureParity] Refused a delivery whose signature doesn't verify (id: #{delivery_id || 'none'})"
            return [401, { error: "invalid signature" }.to_json]
          end
          return [200, { status: "duplicate" }.to_json] if delivery_id && Dedupe.seen?("delivery:#{delivery_id}")

          nil
        end

        # An event from an environment this instance doesn't serve, or one it doesn't handle.
        def screen(payload)
          event = payload["event"]
          webhook_env = (payload["metadata"] || {})["environment"]
          LOG.info "[FeatureParity] Received event: #{event} from environment: #{webhook_env || 'unspecified'}"

          unless Config.should_accept_environment?(webhook_env)
            LOG.info "[FeatureParity] Ignoring webhook from environment '#{webhook_env}' " \
                     "(accepting: #{Config.accept_environments.join(', ')})"
            return [200, { status: "ignored", reason: "environment mismatch", webhook_environment: webhook_env,
                           accepted_environments: Config.accept_environments }.to_json]
          end
          return nil if SUPPORTED_EVENTS.include?(event)

          LOG.info "[FeatureParity] Ignoring unsupported event: #{event}"
          [200, { status: "ignored", reason: "unsupported event" }.to_json]
        end

        # The events that start an agent; every other supported event is acknowledged.
        HANDLERS = {
          "requirement.change_rejected" => :handle_change_rejected,
          "requirement.work_started" => :handle_work_started,
          "requirement.agent_mentioned" => :handle_agent_mentioned,
          "coverage.gap_detected" => :handle_gap_detected
        }.freeze

        # Route an accepted event to its handler. Returns [status, json body].
        def dispatch_event(event, payload)
          handler = HANDLERS[event]
          return Handlers.public_send(handler, payload) if handler

          LOG.info "[FeatureParity] #{event}: #{payload.dig('data', 'slug')}"
          [200, { status: "acknowledged", event: event }.to_json]
        end
      end
    end
  end
end
