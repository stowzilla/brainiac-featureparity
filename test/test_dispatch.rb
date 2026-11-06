# frozen_string_literal: true

require_relative "test_helper"
require "base64"
require "stringio"

# Signed deliveries, agent routing, and the dispatches FeatureParity events start
# (Fizzy #1799).
module DispatchHelpers
  FP = Brainiac::Plugins::Featureparity
  SECRET = "whsec_#{Base64.strict_encode64('0123456789abcdef01234567')}".freeze

  # Stands in for the Sinatra app: keeps the route blocks so a test can call them.
  class FakeApp
    attr_reader :routes

    def initialize = @routes = {}
    def post(path, &block) = @routes[[:post, path]] = block
    def get(path, &block) = @routes[[:get, path]] = block
  end

  # What a route block sees as `self` in Sinatra: request, halt, content_type.
  class FakeRequestScope
    Request = Struct.new(:body, :env)

    attr_reader :request

    def initialize(body, env) = @request = Request.new(StringIO.new(body), env)
    def content_type(_type); end
    def halt(status, body) = throw(:halt, [status, body])
  end

  def deliver(event, data, headers: {}, metadata: { "environment" => "prod" })
    app = FakeApp.new
    FP.register(app)
    body = JSON.generate({ "event" => event, "data" => data, "metadata" => metadata })
    env = headers.transform_keys { |k| "HTTP_#{k.upcase.tr('-', '_')}" }
    env = env.call(body) if headers.respond_to?(:call)
    scope = FakeRequestScope.new(body, env.is_a?(Hash) ? env : {})
    status, response = catch(:halt) { scope.instance_exec(&app.routes[[:post, "/featureparity"]]) }
    [status, JSON.parse(response)]
  end

  def signed(body_event, data, id: "msg_1", at: Time.now.to_i, secret: SECRET)
    body = JSON.generate({ "event" => body_event, "data" => data, "metadata" => { "environment" => "prod" } })
    { "webhook-id" => id, "webhook-timestamp" => at.to_s,
      "webhook-signature" => "v1,#{FP::Signature.sign(secret, id, at, body)}" }
  end

  def project!(key = "feature-parity", **extra)
    repo = File.join(BRAINIAC_DIR, "repos", key)
    FileUtils.mkdir_p(repo)
    PROJECTS[key] = { "repo_path" => repo }.merge(extra)
  end

  def work_data(overrides = {})
    { "work_id" => "w-1", "slug" => "weekly_digest", "title" => "Weekly digest email",
      "why" => "Managers want a summary", "acceptance_criteria" => "A digest is sent every Monday",
      "project_key" => "feature-parity", "agent" => { "id" => "key-1", "name" => "Galen", "key_name" => "galen" },
      "assigned_agent" => "Galen" }.merge(overrides)
  end
end

class TestSignature < Minitest::Test
  include DispatchHelpers

  def test_a_standard_webhooks_signature_verifies
    sig = FP::Signature.sign(SECRET, "msg_1", 1_700_000_000, '{"a":1}')
    assert FP::Signature.valid?(secrets: [SECRET], id: "msg_1", timestamp: "1700000000",
                                signature: "v1,#{sig}", body: '{"a":1}', now: 1_700_000_010)
  end

  def test_a_changed_body_or_wrong_secret_does_not
    sig = FP::Signature.sign(SECRET, "msg_1", 1_700_000_000, '{"a":1}')
    refute FP::Signature.valid?(secrets: [SECRET], id: "msg_1", timestamp: "1700000000",
                                signature: "v1,#{sig}", body: '{"a":2}', now: 1_700_000_010)
    other = "whsec_#{Base64.strict_encode64('x' * 24)}"
    refute FP::Signature.valid?(secrets: [other], id: "msg_1", timestamp: "1700000000",
                                signature: "v1,#{sig}", body: '{"a":1}', now: 1_700_000_010)
  end

  def test_an_old_timestamp_is_refused
    sig = FP::Signature.sign(SECRET, "msg_1", 1_700_000_000, "{}")
    refute FP::Signature.valid?(secrets: [SECRET], id: "msg_1", timestamp: "1700000000",
                                signature: "v1,#{sig}", body: "{}", now: 1_700_000_000 + 301)
  end

  def test_any_configured_secret_and_any_offered_signature_count
    sig = FP::Signature.sign(SECRET, "msg_1", 1_700_000_000, "{}")
    other = "whsec_#{Base64.strict_encode64('y' * 24)}"
    assert FP::Signature.valid?(secrets: [other, SECRET], id: "msg_1", timestamp: "1700000000",
                                signature: "v1,bogus v1,#{sig}", body: "{}", now: 1_700_000_000)
  end
end

class TestWebhookRoute < Minitest::Test
  include DispatchHelpers

  def test_an_unsigned_delivery_is_refused_once_secrets_are_configured
    configure("signing_secrets" => [SECRET])
    project!

    status, body = deliver("requirement.work_started", work_data)

    assert_equal 401, status
    assert_equal "invalid signature", body["error"]
    assert_empty FakeCore.runs
  end

  def test_a_signed_delivery_is_accepted_and_dispatched
    configure("signing_secrets" => [SECRET])
    project!
    data = work_data

    status, body = deliver("requirement.work_started", data, headers: signed("requirement.work_started", data))

    assert_equal 202, status
    assert_equal "Galen", body["agent"]
    assert_equal 1, FakeCore.runs.length
  end

  def test_a_retried_delivery_is_acted_on_once
    project!
    data = work_data("work_id" => nil)
    headers = { "webhook-id" => "msg_same" }

    deliver("requirement.work_started", data, headers: headers)
    status, body = deliver("requirement.work_started", data, headers: headers)

    assert_equal 200, status
    assert_equal "duplicate", body["status"]
    assert_equal 1, FakeCore.runs.length
  end
end

class TestAgentRouting < Minitest::Test
  include DispatchHelpers

  def test_names_match_local_agents_case_insensitively
    assert_equal "Galen", FP::Handlers.resolve_agent({ "agent" => { "key_name" => "galen" } })
    assert_nil FP::Handlers.resolve_agent({ "agent" => { "name" => "Grok", "key_name" => "grok" } })
  end

  def test_the_agents_map_translates_fp_names
    configure("agents" => { "claude-laptop" => "Sherlock" })
    assert_equal "Sherlock", FP::Handlers.resolve_agent({ "agent" => { "key_name" => "claude-laptop" } })
  end

  def test_projects_resolve_by_slug_map_or_declared_slug
    project!("feature-parity")
    project!("stowzilla", "featureparity_project" => "stowzilla-app")
    project!("belt")
    configure("projects" => { "belt-framework" => "belt" })

    assert_equal "feature-parity", FP::Handlers.resolve_project("feature-parity").first
    assert_equal "stowzilla", FP::Handlers.resolve_project("stowzilla-app").first
    assert_equal "belt", FP::Handlers.resolve_project("belt-framework").first
    assert_nil FP::Handlers.resolve_project("unknown").first
  end
end

class TestWorkStarted < Minitest::Test
  include DispatchHelpers

  def test_start_work_gives_the_named_agent_a_worktree_and_launches_it
    project!

    status, = FP::Handlers.handle_work_started({ "data" => work_data, "metadata" => { "environment" => "prod" } })

    assert_equal 202, status
    assert_equal "fp-weekly-digest", FakeCore.worktrees.first[:branch]
    run = FakeCore.runs.first
    assert_equal "Galen", run[:agent_name]
    assert_equal FakeCore.worktrees.first[:path], run[:chdir]
    assert_includes run[:prompt], "A digest is sent every Monday"
    assert_equal "featureparity", FakeCore.work_items.values.first["sources"].keys.first
    assert_equal "fp-work-weekly_digest", FakeCore.sessions.first[:key]
  end

  def test_a_second_start_reuses_the_requirements_worktree
    project!
    FP::Handlers.handle_work_started({ "data" => work_data })
    FP::Handlers.handle_work_started({ "data" => work_data("work_id" => "w-2") })

    assert_equal 1, FakeCore.worktrees.length
    assert_equal 2, FakeCore.runs.length
  end

  def test_the_same_work_id_dispatches_once
    project!
    FP::Handlers.handle_work_started({ "data" => work_data })
    status, body = FP::Handlers.handle_work_started({ "data" => work_data })

    assert_equal "duplicate", JSON.parse(body)["status"]
    assert_equal 200, status
    assert_equal 1, FakeCore.runs.length
  end

  def test_an_agent_that_does_not_run_here_is_ignored
    project!
    data = work_data("agent" => { "name" => "Grok", "key_name" => "grok" }, "assigned_agent" => "Grok")

    _, body = FP::Handlers.handle_work_started({ "data" => data })

    assert_equal "ignored", JSON.parse(body)["status"]
    assert_empty FakeCore.runs
  end

  def test_no_agent_named_falls_back_to_default_agent
    project!
    configure("default_agent" => "sherlock")
    data = work_data("agent" => nil, "assigned_agent" => nil)

    FP::Handlers.handle_work_started({ "data" => data })

    assert_equal "Sherlock", FakeCore.runs.first[:agent_name]
  end
end

class TestGapAndMention < Minitest::Test
  include DispatchHelpers

  def test_gaps_are_only_acknowledged_until_dispatch_gaps_is_on
    project!
    data = work_data("surfaces" => %w[ios])

    _, body = FP::Handlers.handle_gap_detected({ "data" => data })
    assert_equal "acknowledged", JSON.parse(body)["status"]
    assert_empty FakeCore.runs

    configure("dispatch_gaps" => true, "gap_agent" => "Galen")
    status, = FP::Handlers.handle_gap_detected({ "data" => data })
    assert_equal 202, status
    assert_includes FakeCore.runs.first[:prompt], "Missing on:** ios"
  end

  def test_a_tagged_local_agent_answers_the_comment
    project!
    data = work_data("actor" => "Andy Davis",
                     "comment" => { "id" => "c-1", "body" => "@Galen please re-check the tests" })

    status, = FP::Handlers.handle_agent_mentioned({ "data" => data })
    FP::Handlers.handle_agent_mentioned({ "data" => data })

    assert_equal 202, status
    assert_equal 1, FakeCore.runs.length, "the same comment twice (webhook + wake URL) dispatches once"
    run = FakeCore.runs.first
    assert_equal "Galen", run[:agent_name]
    assert_equal "@Galen please re-check the tests", run[:message]
    assert_includes run[:prompt], "Andy Davis tagged you (Galen)"
  end

  def test_a_rejection_reworks_in_the_proposing_agents_worktree
    project!
    worktree = File.join(BRAINIAC_DIR, "wt-digest")
    FileUtils.mkdir_p(worktree)
    FakeCore.work_items["wi-9"] = { "id" => "wi-9", "worktree" => worktree, "agent" => "Galen",
                                    "project" => "feature-parity",
                                    "sources" => { "featureparity" => { "slug" => "weekly_digest" } } }

    status, = FP::Handlers.handle_change_rejected({ "data" => { "slug" => "weekly_digest", "title" => "Weekly digest",
                                                                "actor" => "andy@example.com", "note" => "Too broad" } })

    assert_equal 202, status
    assert_equal worktree, FakeCore.runs.first[:chdir]
    assert_includes FakeCore.runs.first[:prompt], "Too broad"
  end
end
