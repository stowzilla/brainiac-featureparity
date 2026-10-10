# frozen_string_literal: true

module Brainiac
  module Plugins
    module Featureparity
      # Handlers for FeatureParity webhook events.
      module Handlers
        # Handle requirement.change_rejected webhook.
        # This is the main entry point for dispatching an agent to rework a rejected requirement.
        #
        # @param payload [Hash] The webhook payload from FeatureParity
        # @return [Array<Integer, String>] HTTP status code and JSON response body
        def self.handle_change_rejected(payload)
          context = extract_rejection_context(payload)
          LOG.info "[FeatureParity] Change rejected: #{context[:slug]} by #{context[:actor]}"

          # Try to find the work item based on source
          work_item = find_work_item_from_source(context[:source_type], context[:source_url])
          return ignored_response("no work item found", context[:slug]) unless work_item

          validation = validate_work_item(work_item)
          return validation if validation

          dispatch_agent_for_rejection(work_item, context)
        end

        # Extract context from rejection payload.
        def self.extract_rejection_context(payload)
          data = payload["data"] || payload
          source = data["source"] || {}

          {
            slug: data["slug"],
            title: data["title"],
            actor: data["actor"],
            note: source["note"] || data["note"] || "No reason provided",
            kind: data["kind"] || "modification",
            source_type: source["type"],
            source_url: source["url"],
            source_context: source["context"]
          }
        end

        # Validate work item has required fields and is dispatchable.
        def self.validate_work_item(work_item)
          worktree = work_item["worktree"]
          agent_name = work_item["agent"]

          unless worktree && File.directory?(worktree)
            LOG.warn "[FeatureParity] Worktree not found for work item #{work_item['id']}: #{worktree}"
            return [200, { status: "ignored", reason: "worktree not found" }.to_json]
          end

          unless agent_name && local_agent_names.include?(agent_name)
            LOG.info "[FeatureParity] Agent '#{agent_name}' is not local, skipping"
            return [200, { status: "ignored", reason: "non-local agent" }.to_json]
          end

          nil # validation passed
        end

        # Dispatch the agent to handle the rejection.
        def self.dispatch_agent_for_rejection(work_item, context)
          worktree = work_item["worktree"]
          agent_name = work_item["agent"]
          project_key = work_item["project"]

          project_config = PROJECTS[project_key]
          unless project_config
            LOG.warn "[FeatureParity] Project not found: #{project_key}"
            return [200, { status: "ignored", reason: "project not found" }.to_json]
          end

          prompt = build_rejection_prompt(context, worktree, agent_name)
          session_key = "fp-rejection-#{context[:slug]}-#{Time.now.to_i}"
          log_file = log_file_for("fp-rejection", context[:slug])

          LOG.info "[FeatureParity] Dispatching #{agent_name} to handle rejection of #{context[:slug]}"

          Thread.new do
            run_agent(
              prompt,
              project_config: project_config,
              agent_name: agent_name,
              worktree_path: worktree,
              session_key: session_key,
              log_file: log_file,
              source: :featureparity
            )
          rescue StandardError => e
            LOG.error "[FeatureParity] Agent dispatch failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          end

          [200, { status: "dispatched", agent: agent_name, work_item: work_item["id"], slug: context[:slug] }.to_json]
        end

        # Build the prompt for the rejection dispatch.
        def self.build_rejection_prompt(context, worktree, agent_name)
          prompt_vars = {
            "REQUIREMENT_SLUG" => context[:slug],
            "REQUIREMENT_TITLE" => context[:title],
            "ACTOR" => context[:actor],
            "REJECTION_NOTE" => context[:note],
            "SOURCE_TYPE" => context[:source_type] || "unknown",
            "SOURCE_URL" => context[:source_url] || "",
            "SOURCE_CONTEXT" => context[:source_context] || "",
            "CHANGE_KIND" => context[:kind],
            "CHANGE_DETAILS" => build_change_details({ "kind" => context[:kind] }),
            "WORKTREE_PATH" => worktree
          }

          brain_context = build_brain_context("FeatureParity rejection: #{context[:slug]}", agent_name: agent_name)
          render_prompt(
            Prompts::REJECTION_DISPATCH,
            prompt_vars,
            brain_context: brain_context,
            agent_name: agent_name,
            channel: :featureparity
          )
        end

        # Generate an ignored response with logging.
        def self.ignored_response(reason, slug)
          LOG.warn "[FeatureParity] Could not find work item for rejection: #{slug}"
          [200, { status: "ignored", reason: reason }.to_json]
        end

        # Find a work item based on the source of the rejected requirement.
        #
        # @param source_type [String] The type of source (fizzy, discord, github_issue, etc.)
        # @param source_url [String] The URL of the source
        # @return [Hash, nil] The work item if found
        def self.find_work_item_from_source(source_type, source_url)
          work_items = load_work_items

          case source_type
          when "fizzy"
            card_number = extract_fizzy_card_number(source_url)
            return nil unless card_number

            find_work_item_by_fizzy_card(work_items, card_number)
          when "discord"
            thread_id = extract_discord_thread_id(source_url)
            return nil unless thread_id

            find_work_item_by_discord_thread(work_items, thread_id)
          else
            LOG.debug "[FeatureParity] Unsupported source type: #{source_type}" if LOG.debug?
            nil
          end
        end

        # Extract card number from a Fizzy URL.
        #
        # @param url [String] URL like "https://app.fizzy.do/6098707/cards/1377"
        # @return [String, nil] The card number
        def self.extract_fizzy_card_number(url)
          return nil unless url

          match = url.match(%r{/cards/(\d+)})
          match&.[](1)
        end

        # Extract thread ID from a Discord URL.
        #
        # @param url [String] URL like "https://discord.com/channels/123/456/789" or just the thread ID
        # @return [String, nil] The thread ID
        def self.extract_discord_thread_id(url)
          return nil unless url

          if url.include?("discord.com")
            match = url.match(%r{/channels/\d+/(\d+)})
            return match&.[](1)
          end

          url.to_s.match?(/^\d+$/) ? url : nil
        end

        # Find a work item by Fizzy card number.
        #
        # @param work_items [Hash] All work items
        # @param card_number [String] The card number to find
        # @return [Hash, nil] The work item if found
        def self.find_work_item_by_fizzy_card(work_items, card_number)
          work_items.values.find do |item|
            fizzy_source = item.dig("sources", "fizzy")
            next unless fizzy_source

            fizzy_source["card_number"]&.to_s == card_number.to_s
          end
        end

        # Find a work item by Discord thread ID.
        #
        # @param work_items [Hash] All work items
        # @param thread_id [String] The thread ID to find
        # @return [Hash, nil] The work item if found
        def self.find_work_item_by_discord_thread(work_items, thread_id)
          work_items.values.find do |item|
            discord_source = item.dig("sources", "discord")
            next unless discord_source

            discord_source["thread_id"]&.to_s == thread_id.to_s
          end
        end

        # Build a human-readable summary of what changed in the proposal.
        #
        # @param data [Hash] The webhook payload data
        # @return [String] Description of the changes
        def self.build_change_details(data)
          data["kind"] == "removal" ? "Proposed deletion of this requirement" : "Proposed modification to requirement content"
        end
      end
    end
  end
end
