# frozen_string_literal: true

module Brainiac
  module Plugins
    module Featureparity
      # Config file at ~/.brainiac/featureparity.json
      #
      # {
      #   "api_base_url": "https://app.featureparity.dev",
      #   "authorized_users": [],
      #   "authorized_role_ids": []
      # }
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
            @current ||= {}
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
