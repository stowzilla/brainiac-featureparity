# frozen_string_literal: true

module Brainiac
  module Plugins
    module Featureparity
      # Config file at ~/.brainiac/featureparity.json
      #
      # {
      #   "api_base_url": "https://api.featureparity.dev",
      #   "environment": "prod",
      #   "accept_environments": ["prod", "staging"],
      #   "signing_secrets": ["whsec_..."],
      #   "agents": { "galen": "Galen" },
      #   "default_agent": "Galen",
      #   "projects": { "feature-parity": "feature_parity" },
      #   "dispatch_gaps": false,
      #   "gap_agent": "Galen",
      #   "authorized_users": [],
      #   "authorized_role_ids": []
      # }
      #
      # signing_secrets: the whsec_ secrets FeatureParity showed you, one per project webhook
      #   or agent wake-up address pointed here. When any are set, an unsigned or wrongly
      #   signed delivery is refused (401). Leave empty only while setting up.
      # agents: FeatureParity agent key name (or display name) → Brainiac agent name, for when
      #   they differ. Otherwise the names are matched case-insensitively.
      # default_agent: who takes "Start work" with no agent named.
      # projects: FeatureParity project slug → key in ~/.brainiac/projects.json, for when they
      #   differ. A project entry can also say "featureparity_project": "<slug>".
      # dispatch_gaps: start an agent on coverage.gap_detected (write the missing tests).
      #   Off by default: approving a batch of requirements reports a gap for each.
      #
      # Environment matching:
      # - `environment`: Which environment this brainiac instance represents (default: "prod")
      # - `accept_environments`: Which environments' webhooks to process (default: same as environment)
      #
      # This prevents dev/ephemeral webhooks from triggering prod agents and vice versa.
      # An ephemeral FP environment like "fizzy-1234" sends webhooks with that environment
      # in the metadata — unless accept_environments includes "fizzy-1234", those are ignored.
      module Config
        CONFIG_FILE = File.join(BRAINIAC_DIR, "featureparity.json")
        @config = nil
        @config_mtime = nil

        class << self
          def load!
            @config = read_config_file
            @config_mtime = File.exist?(CONFIG_FILE) ? File.mtime(CONFIG_FILE) : nil
            LOG.info "[FeatureParity] Config loaded from #{CONFIG_FILE}" if @config
          end

          def current
            reload_if_changed
            @config || {}
          end

          def reload_if_changed
            return unless File.exist?(CONFIG_FILE)

            mtime = File.mtime(CONFIG_FILE)
            return if @config_mtime && mtime == @config_mtime

            @config = read_config_file
            @config_mtime = mtime
            LOG.debug "[FeatureParity] Config reloaded" if LOG.debug?
          end

          def api_base_url
            current["api_base_url"] || "https://api.featureparity.dev"
          end

          # Which environment this brainiac instance represents
          def environment
            current["environment"] || "prod"
          end

          # Which environments' webhooks to process. Defaults to just this environment.
          # Use ["prod", "staging", "dev"] to accept webhooks from multiple environments.
          # Use ["*"] to accept webhooks from any environment (useful for dev/testing).
          def accept_environments
            current["accept_environments"] || [environment]
          end

          # Check if this brainiac instance should process a webhook from the given environment.
          # Returns true if:
          # - accept_environments includes "*" (accept all)
          # - accept_environments includes the webhook's environment
          # - The webhook doesn't specify an environment (legacy/backward compatibility)
          def should_accept_environment?(webhook_environment)
            # No environment specified in webhook = backward compatibility, accept it
            return true if webhook_environment.nil? || webhook_environment.to_s.strip.empty?

            # Accept all environments
            return true if accept_environments.include?("*")

            # Check if this specific environment is accepted
            accept_environments.include?(webhook_environment.to_s)
          end

          def signing_secrets
            Array(current["signing_secrets"]).map(&:to_s).reject(&:empty?)
          end

          def agent_map
            (current["agents"] || {}).transform_keys { |k| k.to_s.downcase }
          end

          def default_agent
            current["default_agent"]
          end

          def project_map
            current["projects"] || {}
          end

          def dispatch_gaps?
            current["dispatch_gaps"] == true
          end

          def gap_agent
            current["gap_agent"] || default_agent
          end

          def authorized_users
            current["authorized_users"] || []
          end

          def authorized_role_ids
            current["authorized_role_ids"] || []
          end

          private

          def read_config_file
            return {} unless File.exist?(CONFIG_FILE)

            JSON.parse(File.read(CONFIG_FILE))
          rescue JSON::ParserError => e
            LOG.warn "[FeatureParity] Invalid JSON in config: #{e.message}"
            {}
          end
        end
      end
    end
  end
end
