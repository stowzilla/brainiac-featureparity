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
          "FeatureParity integration — starts the agent you pick on a requirement, and answers its tags, gaps and rejections"
        end
      end
    end
  end
end
