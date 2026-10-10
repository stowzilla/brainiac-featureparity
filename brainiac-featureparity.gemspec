# frozen_string_literal: true

require_relative "lib/brainiac/plugins/featureparity/version"

Gem::Specification.new do |s|
  s.name        = "brainiac-featureparity"
  s.version     = Brainiac::Plugins::Featureparity::VERSION
  s.summary     = "FeatureParity plugin for Brainiac"
  s.description = "FeatureParity integration for Brainiac — routes requirement " \
                  "rejections back to the agent who proposed them for rework."
  s.authors     = ["Andy Davis"]
  s.homepage    = "https://github.com/stowzilla/brainiac-featureparity"
  s.license     = "MIT"
  s.required_ruby_version = ">= 3.4"

  s.files = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  s.require_paths = ["lib"]

  s.add_dependency "brainiac", ">= 0.1.8"

  s.add_development_dependency "minitest", "~> 5.25"
  s.add_development_dependency "rake", "~> 13.0"
  s.add_development_dependency "rubocop", "~> 1.75"
  s.add_development_dependency "rubocop-performance", "~> 1.25"

  s.metadata["rubygems_mfa_required"] = "true"
end
