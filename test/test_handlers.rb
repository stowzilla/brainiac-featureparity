# frozen_string_literal: true

require_relative "test_helper"

class TestHandlers < Minitest::Test
  def test_extract_fizzy_card_number_from_url
    url = "https://app.fizzy.do/6098707/cards/1377"
    assert_equal "1377", Brainiac::Plugins::Featureparity::Handlers.extract_fizzy_card_number(url)
  end

  def test_extract_fizzy_card_number_with_comment
    url = "https://app.fizzy.do/6098707/cards/1377#comment_123"
    assert_equal "1377", Brainiac::Plugins::Featureparity::Handlers.extract_fizzy_card_number(url)
  end

  def test_extract_fizzy_card_number_nil_url
    assert_nil Brainiac::Plugins::Featureparity::Handlers.extract_fizzy_card_number(nil)
  end

  def test_extract_fizzy_card_number_invalid_url
    assert_nil Brainiac::Plugins::Featureparity::Handlers.extract_fizzy_card_number("https://example.com")
  end

  def test_extract_discord_thread_id_from_url
    url = "https://discord.com/channels/123456/789012/345678"
    assert_equal "789012", Brainiac::Plugins::Featureparity::Handlers.extract_discord_thread_id(url)
  end

  def test_extract_discord_thread_id_direct
    assert_equal "789012345678", Brainiac::Plugins::Featureparity::Handlers.extract_discord_thread_id("789012345678")
  end

  def test_extract_discord_thread_id_nil
    assert_nil Brainiac::Plugins::Featureparity::Handlers.extract_discord_thread_id(nil)
  end

  def test_extract_fp_slug_from_url
    url = "https://fp.example.com/requirements/user-login-validation"
    assert_equal "user-login-validation", Brainiac::Plugins::Featureparity::Handlers.extract_fp_slug(url)
  end

  def test_extract_fp_slug_direct
    assert_equal "my-requirement-slug", Brainiac::Plugins::Featureparity::Handlers.extract_fp_slug("my-requirement-slug")
  end

  def test_extract_fp_slug_nil
    assert_nil Brainiac::Plugins::Featureparity::Handlers.extract_fp_slug(nil)
  end

  def test_extract_fp_slug_empty_string
    assert_nil Brainiac::Plugins::Featureparity::Handlers.extract_fp_slug("")
  end

  def test_find_work_item_by_fizzy_card
    work_items = {
      "wi-abc123" => {
        "id" => "wi-abc123",
        "branch" => "fizzy-1377-feature",
        "worktree" => "/path/to/worktree",
        "agent" => "Galen",
        "project" => "myproject",
        "sources" => {
          "fizzy" => { "card_number" => 1377 }
        }
      }
    }

    result = Brainiac::Plugins::Featureparity::Handlers.find_work_item_by_fizzy_card(work_items, "1377")
    assert_equal "wi-abc123", result["id"]
  end

  def test_find_work_item_by_fizzy_card_not_found
    work_items = {
      "wi-abc123" => {
        "id" => "wi-abc123",
        "sources" => {
          "fizzy" => { "card_number" => 999 }
        }
      }
    }

    result = Brainiac::Plugins::Featureparity::Handlers.find_work_item_by_fizzy_card(work_items, "1377")
    assert_nil result
  end

  def test_find_work_item_by_discord_thread
    work_items = {
      "wi-xyz789" => {
        "id" => "wi-xyz789",
        "branch" => "discord-topic",
        "worktree" => "/path/to/worktree",
        "agent" => "Sherlock",
        "project" => "myproject",
        "sources" => {
          "discord" => { "thread_id" => "123456789" }
        }
      }
    }

    result = Brainiac::Plugins::Featureparity::Handlers.find_work_item_by_discord_thread(work_items, "123456789")
    assert_equal "wi-xyz789", result["id"]
  end

  def test_find_work_item_by_fp_requirement_in_items
    work_items = {
      "wi-fp123" => {
        "id" => "wi-fp123",
        "branch" => "fp-user-login-20261009",
        "worktree" => "/path/to/worktree",
        "agent" => "Galen",
        "project" => "myproject",
        "sources" => {
          "featureparity" => { "slug" => "user-login-validation", "title" => "User Login Validation" }
        }
      }
    }

    result = Brainiac::Plugins::Featureparity::Handlers.find_work_item_by_fp_requirement_in_items(work_items, "user-login-validation")
    assert_equal "wi-fp123", result["id"]
  end

  def test_find_work_item_by_fp_requirement_not_found
    work_items = {
      "wi-fp123" => {
        "id" => "wi-fp123",
        "sources" => {
          "featureparity" => { "slug" => "other-requirement" }
        }
      }
    }

    result = Brainiac::Plugins::Featureparity::Handlers.find_work_item_by_fp_requirement_in_items(work_items, "user-login-validation")
    assert_nil result
  end

  def test_build_change_details_modification
    data = { "kind" => "modification" }
    result = Brainiac::Plugins::Featureparity::Handlers.build_change_details(data)
    assert_includes result, "modification"
  end

  def test_build_change_details_removal
    data = { "kind" => "removal" }
    result = Brainiac::Plugins::Featureparity::Handlers.build_change_details(data)
    assert_includes result, "deletion"
  end

  def test_extract_work_context
    payload = {
      "data" => {
        "slug" => "user-login-validation",
        "title" => "User Login Validation",
        "description" => "Validate user login credentials",
        "why" => "Improve security",
        "acceptance_criteria" => "Must validate email format",
        "project_key" => "myproject",
        "assigned_agent" => "Galen",
        "priority" => "high",
        "tags" => %w[security auth]
      }
    }

    context = Brainiac::Plugins::Featureparity::Handlers.extract_work_context(payload)

    assert_equal "user-login-validation", context[:slug]
    assert_equal "User Login Validation", context[:title]
    assert_equal "Validate user login credentials", context[:description]
    assert_equal "Galen", context[:assigned_agent]
    assert_equal "myproject", context[:project_key]
    assert_equal %w[security auth], context[:tags]
  end
end
