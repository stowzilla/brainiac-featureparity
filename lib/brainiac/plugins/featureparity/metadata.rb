# frozen_string_literal: true

module Brainiac
  module Plugins
    module Featureparity
      # Plugin metadata for brainiac plugin system.
      module Metadata
        def self.name
          "featureparity"
        end

        def self.version
          VERSION
        end

        def self.description
          "FeatureParity integration — routes requirement rejections back to agents for rework"
        end
      end
    end
  end
end
