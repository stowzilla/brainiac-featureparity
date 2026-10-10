# frozen_string_literal: true

module Brainiac
  module Plugins
    module Featureparity
      # CLI commands for the FeatureParity plugin.
      # Accessed via `brainiac featureparity <command>`.
      module CLI
        CONFIG_FILE = File.join(BRAINIAC_DIR, "featureparity.json")

        class << self
          def cli(args)
            command = args.shift
            case command
            when "setup"
              setup_command
            when "config"
              config_command
            when "status"
              status_command
            when "help", nil
              help_command
            else
              puts "Unknown command: #{command}"
              puts "Run 'brainiac featureparity help' for usage."
              exit 1
            end
          end

          def completions
            %w[setup config status help]
          end

          def configured?
            File.exist?(CONFIG_FILE)
          end

          def help_text
            "Manage FeatureParity webhook integration"
          end

          private

          def setup_command
            puts "Setting up FeatureParity plugin..."

            if File.exist?(CONFIG_FILE)
              puts "Config file already exists at #{CONFIG_FILE}"
              print "Overwrite? [y/N] "
              answer = $stdin.gets&.strip&.downcase
              return unless answer == "y"
            end

            config = {
              "api_base_url" => "https://app.featureparity.dev",
              "authorized_users" => [],
              "authorized_role_ids" => []
            }

            File.write(CONFIG_FILE, JSON.pretty_generate(config))
            puts "Created config at #{CONFIG_FILE}"
            puts
            puts "Next steps:"
            puts "1. In FeatureParity, go to Project Settings > Webhooks"
            puts "2. Add a webhook with URL: https://your-ngrok.ngrok-free.app/featureparity"
            puts "3. Select provider: 'generic'"
            puts "4. Subscribe to events you want to handle (e.g., 'Change rejected')"
            puts
            puts "Run 'brainiac restart' to load the plugin."
          end

          def config_command
            unless File.exist?(CONFIG_FILE)
              puts "No config file found. Run 'brainiac featureparity setup' first."
              exit 1
            end

            config = JSON.parse(File.read(CONFIG_FILE))
            puts "FeatureParity Config (#{CONFIG_FILE}):"
            puts JSON.pretty_generate(config)
          end

          def status_command
            puts "FeatureParity Plugin Status"
            puts "=" * 30

            if File.exist?(CONFIG_FILE)
              config = JSON.parse(File.read(CONFIG_FILE))
              puts "Config: ✓ #{CONFIG_FILE}"
              puts "API URL: #{config['api_base_url']}"
            else
              puts "Config: ✗ Not configured (run 'brainiac featureparity setup')"
            end

            puts
            puts "Webhook endpoint: POST /featureparity"
            puts "API endpoint: GET /api/featureparity"
          end

          def help_command
            puts <<~HELP
              brainiac featureparity — #{help_text}

              Usage:
                brainiac featureparity setup   Create config file and show setup instructions
                brainiac featureparity config  Show current configuration
                brainiac featureparity status  Show plugin status
                brainiac featureparity help    Show this help message

              Webhook Events:
                The plugin receives webhooks from FeatureParity and dispatches agents
                when requirements are rejected, evidence fails, or coverage gaps are detected.

                Currently handled:
                - requirement.change_rejected → Dispatch agent to fix rejected requirement

              Configuration:
                Config is stored at ~/.brainiac/featureparity.json
            HELP
          end
        end
      end
    end
  end
end
