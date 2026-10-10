# frozen_string_literal: true

require_relative "featureparity/version"
require_relative "featureparity/metadata"
require_relative "featureparity/config"
require_relative "featureparity/prompts"
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
            payload_body = request.body.read

            LOG.debug "[FeatureParity] Webhook received: #{payload_body.length} bytes" if LOG.debug?

            begin
              payload = JSON.parse(payload_body)
            rescue JSON::ParserError => e
              LOG.error "[FeatureParity] Invalid JSON: #{e.message}"
              halt 400, { error: "Invalid JSON" }.to_json
            end

            event = payload["event"]
            LOG.info "[FeatureParity] Received event: #{event}"

            unless SUPPORTED_EVENTS.include?(event)
              LOG.info "[FeatureParity] Ignoring unsupported event: #{event}"
              halt 200, { status: "ignored", reason: "unsupported event" }.to_json
            end

            reload_projects!
            reload_agent_registry!

            status_code, body = dispatch_event(event, payload)
            halt status_code, body
          rescue StandardError => e
            LOG.error "[FeatureParity] Unhandled error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
            halt 500, { error: e.message }.to_json
          end
        end

        def setup_api_routes(app)
          app.get "/api/featureparity" do
            content_type :json
            {
              enabled: true,
              api_base_url: Brainiac::Plugins::Featureparity::Config.api_base_url,
              supported_events: SUPPORTED_EVENTS
            }.to_json
          end
        end

        def dispatch_event(event, payload)
          case event
          when "requirement.change_rejected"
            Handlers.handle_change_rejected(payload)
          when "requirement.change_approved"
            # Could notify the agent that their change was approved
            LOG.info "[FeatureParity] Change approved: #{payload.dig('data', 'slug')}"
            [200, { status: "acknowledged", event: event }.to_json]
          when "requirement.change_proposed", "requirement.removal_proposed"
            # Proposals are created by agents, so we don't need to dispatch here
            LOG.info "[FeatureParity] Proposal created: #{payload.dig('data', 'slug')}"
            [200, { status: "acknowledged", event: event }.to_json]
          when "evidence.failing"
            # Could dispatch agent to investigate failing evidence
            LOG.info "[FeatureParity] Evidence failing: #{payload.dig('data', 'slug')}"
            [200, { status: "acknowledged", event: event }.to_json]
          when "coverage.gap_detected"
            # Could dispatch agent to write missing tests
            LOG.info "[FeatureParity] Coverage gap: #{payload.dig('data', 'slug')}"
            [200, { status: "acknowledged", event: event }.to_json]
          else
            # Other events are informational for now
            LOG.info "[FeatureParity] Event received: #{event}"
            [200, { status: "acknowledged", event: event }.to_json]
          end
        end
      end
    end
  end
end
