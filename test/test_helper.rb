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

# Brainiac core, faked with core's real signatures: a keyword core doesn't take fails
# here as it would in production (the plugin once passed worktree_path:/session_key:/
# log_file: to run_agent and every dispatch died in its thread).
module FakeCore
  class << self
    attr_accessor :work_items, :runs, :worktrees, :sessions, :agents

    def reset!
      self.work_items = {}
      self.runs = []
      self.worktrees = []
      self.sessions = []
      self.agents = %w[Galen Sherlock]
    end
  end
  reset!
end

PROJECTS = {} # rubocop:disable Style/MutableConstant -- core keeps projects in a mutable constant

# The fakes keep core's full signatures on purpose, unused arguments and all.
# rubocop:disable Lint/UnusedMethodArgument

def reload_projects!(force: false); end
def reload_agent_registry!(force: false); end
def local_agent_names = FakeCore.agents
def load_work_item_map = FakeCore.work_items
def save_work_item_map(map) = FakeCore.work_items = map
def find_work_item_by_id(work_item_id) = work_item_id && FakeCore.work_items[work_item_id]
def slugify(title, max_length: 40) = title.to_s.downcase.gsub(/[^a-z0-9]+/, "-")[0, max_length]
def debounced_repo_fetch(repo_path); end

def create_or_reuse_worktree(repo_path:, branch:, base_ref: nil, worktree_path: nil)
  path = worktree_path || File.join(BRAINIAC_DIR, "#{File.basename(repo_path)}--#{branch}")
  FileUtils.mkdir_p(path)
  FakeCore.worktrees << { repo_path: repo_path, branch: branch, path: path }
  path
end

def register_work_item(branch:, worktree: nil, project: nil, agent: nil, source: nil, source_data: {})
  id = "wi-#{FakeCore.work_items.size + 1}"
  FakeCore.work_items[id] = { "id" => id, "branch" => branch, "worktree" => worktree, "project" => project,
                              "agent" => agent, "sources" => { source.to_s => source_data } }
  id
end

def build_brain_context(agent_name: "Galen", card_title: "", card_number: nil, project_key: nil, comment_body: "",
                        source: nil)
  ""
end

def render_prompt(template, vars = {}, brain_context: "", card_context: "", comment_history: "", agent_name: "Galen",
                  channel: nil, board_key: nil)
  vars.reduce(template) { |text, (k, v)| text.gsub("{{#{k}}}", v.to_s) }
end

def run_agent(prompt, project_config:, chdir: nil, log_name: "agent", model: nil, effort: nil, agent_name: nil,
              card_number: nil, comment_id: nil, source: nil, source_context: {}, skip_column_move: false,
              cli_provider: nil, resume: false, message: nil, channel: nil, context: nil, env: {}, profile: nil,
              explicit_model: nil)
  FakeCore.runs << { prompt: prompt, chdir: chdir, agent_name: agent_name, log_name: log_name, message: message }
  [4242, "/tmp/#{log_name}.log"]
end

def register_session(card_key, pid, log_file: nil, message_id: nil, channel_id: nil, supersede_key: nil,
                     draft_files: nil, agent_name: nil)
  FakeCore.sessions << { key: card_key, pid: pid, agent_name: agent_name }
end

# rubocop:enable Lint/UnusedMethodArgument

# Now require the plugin
require "brainiac_featureparity"

Brainiac::Plugins::Featureparity::Handlers.run_inline = true

class Minitest::Test
  def setup
    FileUtils.mkdir_p(BRAINIAC_DIR)
    FakeCore.reset!
    PROJECTS.clear
    Brainiac::Plugins::Featureparity::Dedupe.reset!
    configure({})
  end

  def teardown
    FileUtils.rm_rf(BRAINIAC_DIR)
  end

  # Write ~/.brainiac/featureparity.json for this test.
  def configure(settings)
    File.write(Brainiac::Plugins::Featureparity::Config::CONFIG_FILE, JSON.generate(settings))
    Brainiac::Plugins::Featureparity::Config.load!
  end
end
