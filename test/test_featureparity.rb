# frozen_string_literal: true

require_relative "test_helper"

class TestFeatureparity < Minitest::Test
  def test_version_is_set
    refute_nil Brainiac::Plugins::Featureparity::VERSION
    assert_equal "0.0.1", Brainiac::Plugins::Featureparity::VERSION
  end

  def test_metadata_name
    assert_equal "featureparity", Brainiac::Plugins::Featureparity::Metadata.name
  end

  def test_supported_events_include_change_rejected
    assert_includes Brainiac::Plugins::Featureparity::SUPPORTED_EVENTS, "requirement.change_rejected"
  end
end
