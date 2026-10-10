# frozen_string_literal: true

module Brainiac
  module Plugins
    module Featureparity
      # Config file at ~/.brainiac/featureparity.json
      #
      # {
      #   "api_base_url": "https://app.featureparity.dev",
      #   "environment": "prod",
      #   "accept_environments": ["prod", "staging"],
      #   "authorized_users": [],
      #   "authorized_role_ids": []
      # }
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
            current["api_base_url"] || "https://app.featureparity.dev"
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
