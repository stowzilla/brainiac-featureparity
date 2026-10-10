# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "json"
require "fileutils"

# Mock the BRAINIAC_DIR constant that the plugin expects
BRAINIAC_DIR = File.expand_path("../tmp/test-brainiac", __dir__)
FileUtils.mkdir_p(BRAINIAC_DIR)

# Mock the LOG constant
LOG = Class.new do
  def info(msg); end
  def debug(msg); end
  def warn(msg); end
  def error(msg); end
  def debug? = false
end.new

# Mock Brainiac module methods the plugin uses
module Brainiac
  def self.register_channel_prompt(channel, prompt, **opts); end
end

# Mock core helpers that handlers call
def reload_projects!; end
def reload_agent_registry!; end
def local_agent_names = %w[Galen Sherlock]
def load_work_items = {}
def build_brain_context(*_args, **_kwargs) = ""
def render_prompt(*_args, **_kwargs) = "mock prompt"
def log_file_for(*_args) = "/tmp/test.log"
def run_agent(*args, **kwargs); end

# Now require the plugin
require "brainiac_featureparity"

class Minitest::Test
  def setup
    FileUtils.mkdir_p(BRAINIAC_DIR)
  end

  def teardown
    FileUtils.rm_rf(BRAINIAC_DIR)
  end
end
