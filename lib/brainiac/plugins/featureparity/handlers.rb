# frozen_string_literal: true

module Brainiac
  module Plugins
    module Featureparity
      # Handlers for FeatureParity webhook events.
      #
      # Each `handle_*` returns [status, json body] straight away and does the slow part
      # (fetch, worktree, agent launch) on a thread: FeatureParity waits 5 seconds for an
      # answer and retries a delivery that doesn't get one.
      module Handlers
        # --- Events ------------------------------------------------------------

        # requirement.work_started — someone pressed Start work in FeatureParity, usually for
        # a named agent. The agent gets a worktree for the requirement (reused if one exists)
        # and is asked to implement it.
        def self.handle_work_started(payload)
          context = extract_work_context(payload)
          fp_env = extract_fp_environment(payload)
          agent_name = agent_for_work(payload["data"] || payload)
          return ignored("no local agent for this work (name one, or set default_agent)") unless agent_name

          project_key, project_config = resolve_project(context[:project_key])
          return ignored("unknown project #{context[:project_key].inspect}") unless project_config
          return duplicate if context[:work_id] && Dedupe.seen?("work:#{context[:work_id]}:#{agent_name}")

          LOG.info "[FeatureParity] Work started on #{context[:slug]} for #{agent_name} (env: #{fp_env[:environment]})"
          in_background("work on #{context[:slug]}") do
            work_item = ensure_work_item(context, project_key, project_config, agent_name, fp_env)
            next unless work_item

            dispatch(Prompts::WORK_DISPATCH, work_vars(context, work_item, fp_env),
                     work_item: work_item, project_key: project_key, project_config: project_config,
                     agent_name: agent_name, slug: context[:slug], kind: "work", title: context[:title])
          end
          accepted(agent_name, context[:slug])
        end

        # coverage.gap_detected — a requirement is active on a surface nobody has tested.
        # Only acted on with "dispatch_gaps": true; the gap agent writes the missing tests.
        def self.handle_gap_detected(payload)
          return [200, { status: "acknowledged", reason: "dispatch_gaps is off" }.to_json] unless Config.dispatch_gaps?

          data = payload["data"] || payload
          context = extract_work_context(payload).merge(surfaces: Array(data["surfaces"]))
          agent_name = local_agent(Config.gap_agent)
          return ignored("no local gap_agent configured") unless agent_name

          project_key, project_config = resolve_project(context[:project_key])
          return ignored("unknown project #{context[:project_key].inspect}") unless project_config
          return duplicate if Dedupe.seen?("gap:#{context[:slug]}:#{context[:surfaces].sort.join(',')}")

          fp_env = extract_fp_environment(payload)
          in_background("tests for #{context[:slug]}") do
            work_item = ensure_work_item(context, project_key, project_config, agent_name, fp_env)
            next unless work_item

            vars = work_vars(context, work_item, fp_env).merge("MISSING_SURFACES" => context[:surfaces].join(", "))
            dispatch(Prompts::GAP_DISPATCH, vars,
                     work_item: work_item, project_key: project_key, project_config: project_config,
                     agent_name: agent_name, slug: context[:slug], kind: "gap", title: context[:title])
          end
          accepted(agent_name, context[:slug])
        end

        # requirement.agent_mentioned — a comment tagged one of the team's agents. If that
        # agent runs here, it reads the comment (in the requirement's worktree when there is
        # one) and answers it on the requirement.
        def self.handle_agent_mentioned(payload)
          data = payload["data"] || payload
          agent_name = resolve_agent(data)
          return ignored("the tagged agent doesn't run here") unless agent_name

          comment = data["comment"] || {}
          return duplicate if comment["id"] && Dedupe.seen?("mention:#{comment['id']}:#{agent_name}")

          context = extract_work_context(payload)
          project_key, project_config = resolve_project(context[:project_key])
          return ignored("unknown project #{context[:project_key].inspect}") unless project_config

          fp_env = extract_fp_environment(payload)
          in_background("mention on #{context[:slug]}") do
            dispatch_mention(data, context, project_key, project_config, agent_name, fp_env)
          end
          accepted(agent_name, context[:slug])
        end

        # The tagged agent answers in the requirement's worktree when one exists, else the repo.
        def self.dispatch_mention(data, context, project_key, project_config, agent_name, fp_env)
          comment = data["comment"] || {}
          work_item = existing_work_item(context[:slug])
          work_dir = work_item ? work_item["worktree"] : project_config["repo_path"]
          vars = work_vars(context, { "worktree" => work_dir }, fp_env).merge(
            "COMMENT_AUTHOR" => data["actor"].to_s,
            "COMMENT_BODY" => comment["body"].to_s,
            "AGENT_NAME" => agent_name
          )
          dispatch(Prompts::MENTION_DISPATCH, vars,
                   work_item: work_item || { "worktree" => work_dir }, project_key: project_key,
                   project_config: project_config, agent_name: agent_name, slug: context[:slug],
                   kind: "mention", title: context[:title], message: comment["body"].to_s)
        end

        # requirement.change_rejected — a human turned down a change an agent proposed. The
        # agent that proposed it, found through the work item the proposal came from, reworks it.
        def self.handle_change_rejected(payload)
          context = extract_rejection_context(payload)
          fp_env = extract_fp_environment(payload)
          LOG.info "[FeatureParity] Change rejected: #{context[:slug]} by #{context[:actor]} (env: #{fp_env[:environment]})"

          work_item = find_work_item_from_source(context[:source_type], context[:source_url])
          work_item ||= find_work_item_by_fp_requirement(context[:slug])
          return ignored_response("no work item found", context[:slug]) unless work_item

          validation = validate_work_item(work_item)
          return validation if validation

          project_config = PROJECTS[work_item["project"]]
          return ignored("project not found") unless project_config

          update_work_item_fp_env(work_item["id"], fp_env) if fp_env[:api_base_url]
          fp_env = get_fp_env_from_work_item(work_item) if fp_env[:api_base_url].nil?
          agent_name = work_item["agent"]

          in_background("rework of #{context[:slug]}") do
            dispatch(Prompts::REJECTION_DISPATCH, rejection_vars(context, work_item, fp_env),
                     work_item: work_item, project_key: work_item["project"], project_config: project_config,
                     agent_name: agent_name, slug: context[:slug], kind: "rejection", title: context[:title])
          end
          accepted(agent_name, context[:slug])
        end

        # --- Who and where -----------------------------------------------------

        # The local Brainiac agent a payload names: its `agent` (from Start work or a tag)
        # or `assigned_agent`, through the config's `agents` map, then by name. nil when
        # the agent doesn't run on this machine.
        def self.resolve_agent(data)
          agent = data["agent"].is_a?(Hash) ? data["agent"] : {}
          candidates = [agent["key_name"], agent["name"], data["assigned_agent"]].compact.map(&:to_s).reject(&:empty?)
          candidates.each do |candidate|
            mapped = Config.agent_map[candidate.downcase]
            found = local_agent(mapped || candidate)
            return found if found
          end
          nil
        end

        # Who takes Start work: the agent it names, else the configured default_agent.
        def self.agent_for_work(data)
          resolve_agent(data) || local_agent(Config.default_agent)
        end

        # `name` as this machine's agent is spelled, or nil if it isn't local.
        def self.local_agent(name)
          return nil if name.to_s.empty?

          local_agent_names.find { |local| local.to_s.casecmp?(name.to_s) }
        end

        # [brainiac project key, config] for a FeatureParity project slug.
        def self.resolve_project(fp_key)
          return [nil, nil] if fp_key.to_s.empty?

          key = [Config.project_map[fp_key], fp_key].compact.find { |candidate| PROJECTS[candidate] }
          return [key, PROJECTS[key]] if key

          PROJECTS.find { |_, config| config.is_a?(Hash) && config["featureparity_project"] == fp_key } || [nil, nil]
        end

        # --- Work items and worktrees ------------------------------------------

        # The requirement's work item: the existing one (its worktree still on disk), or a
        # new worktree on an "fp-<slug>" branch registered with FP as the source.
        def self.ensure_work_item(context, project_key, project_config, agent_name, fp_env)
          existing = existing_work_item(context[:slug])
          if existing
            update_work_item_fp_env(existing["id"], fp_env)
            return existing
          end

          repo_path = project_config["repo_path"]
          unless repo_path && File.directory?(repo_path)
            LOG.warn "[FeatureParity] Project #{project_key} has no repo_path on disk"
            return nil
          end

          branch = "fp-#{slugify(context[:slug].to_s)}"
          debounced_repo_fetch(repo_path)
          worktree = create_or_reuse_worktree(repo_path: repo_path, branch: branch)
          id = register_fp_work_item({ branch: branch, worktree: worktree }, context.merge(project_key: project_key),
                                     agent_name, fp_env)
          find_work_item_by_id(id)&.merge("id" => id)
        rescue StandardError => e
          LOG.error "[FeatureParity] Could not prepare a worktree for #{context[:slug]}: #{e.message}"
          nil
        end

        # The requirement's work item, if its worktree is still on disk.
        def self.existing_work_item(slug)
          item = find_work_item_by_fp_requirement(slug)
          item if item && File.directory?(item["worktree"].to_s)
        end

        def self.register_fp_work_item(worktree_info, context, agent_name, fp_env)
          source_data = { "slug" => context[:slug], "title" => context[:title] }
          if fp_env[:api_base_url]
            source_data["api_base_url"] = fp_env[:api_base_url]
            source_data["environment"] = fp_env[:environment]
            source_data["ephemeral"] = fp_env[:ephemeral]
          end

          register_work_item(
            branch: worktree_info[:branch],
            worktree: worktree_info[:worktree],
            project: context[:project_key],
            agent: agent_name,
            source: "featureparity",
            source_data: source_data
          )
        end

        # Keep the FP environment on the work item current (a requirement can move from a
        # preview environment to prod).
        def self.update_work_item_fp_env(work_item_id, fp_env)
          return unless fp_env[:api_base_url] && work_item_id

          map = load_work_item_map
          fp_source = map.dig(work_item_id, "sources", "featureparity")
          return unless fp_source

          fp_source["api_base_url"] = fp_env[:api_base_url]
          fp_source["environment"] = fp_env[:environment]
          fp_source["ephemeral"] = fp_env[:ephemeral]
          save_work_item_map(map)
        end

        # --- Launching the agent -----------------------------------------------

        def self.dispatch(template, vars, work_item:, project_key:, project_config:, agent_name:, slug:, kind:,
                          title: nil, message: nil)
          prompt = render_prompt(
            template, vars,
            brain_context: build_brain_context(agent_name: agent_name, card_title: title.to_s,
                                               project_key: project_key, comment_body: message.to_s),
            agent_name: agent_name, channel: :featureparity
          )
          opts = { project_config: project_config, chdir: work_item["worktree"], log_name: "fp-#{kind}-#{slug}",
                   agent_name: agent_name, source: :featureparity,
                   source_context: { slug: slug, work_item_id: work_item["id"], event: kind } }
          opts[:message] = message if message
          pid, log_file = run_agent(prompt, **opts)
          LOG.info "[FeatureParity] Dispatched #{agent_name} (#{kind}) on #{slug}#{" (pid #{pid})" if pid}"
          register_session("fp-#{kind}-#{slug}", pid, log_file: log_file, agent_name: agent_name) if pid && respond_to?(:register_session, true)
          pid
        end

        # Tests set this to run the background work inline.
        class << self
          attr_accessor :run_inline
        end

        def self.in_background(what)
          if run_inline
            yield
            return
          end

          Thread.new do
            yield
          rescue StandardError => e
            LOG.error "[FeatureParity] #{what} failed: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
          end
        end

        def self.accepted(agent_name, slug)
          [202, { status: "accepted", agent: agent_name, slug: slug }.to_json]
        end

        def self.ignored(reason)
          LOG.info "[FeatureParity] Ignored: #{reason}"
          [200, { status: "ignored", reason: reason }.to_json]
        end

        def self.duplicate
          [200, { status: "duplicate" }.to_json]
        end

        # --- Prompt variables --------------------------------------------------

        def self.work_vars(context, work_item, fp_env)
          {
            "REQUIREMENT_SLUG" => context[:slug],
            "REQUIREMENT_TITLE" => context[:title],
            "REQUIREMENT_DESCRIPTION" => context[:description] || "",
            "REQUIREMENT_WHY" => context[:why] || "",
            "ACCEPTANCE_CRITERIA" => context[:acceptance_criteria] || "",
            "PROJECT_KEY" => context[:project_key],
            "WORKTREE_PATH" => work_item["worktree"],
            "FP_API_URL" => fp_env[:api_base_url] || Config.api_base_url,
            "FP_ENVIRONMENT" => fp_env[:environment] || "prod",
            "FP_EPHEMERAL" => fp_env[:ephemeral] ? "true" : "false"
          }
        end

        def self.rejection_vars(context, work_item, fp_env)
          {
            "REQUIREMENT_SLUG" => context[:slug],
            "REQUIREMENT_TITLE" => context[:title],
            "ACTOR" => context[:actor],
            "REJECTION_NOTE" => context[:note],
            "SOURCE_TYPE" => context[:source_type] || "unknown",
            "SOURCE_URL" => context[:source_url] || "",
            "SOURCE_CONTEXT" => context[:source_context] || "",
            "CHANGE_KIND" => context[:kind],
            "CHANGE_DETAILS" => build_change_details({ "kind" => context[:kind] }),
            "WORKTREE_PATH" => work_item["worktree"],
            "FP_API_URL" => fp_env[:api_base_url] || Config.api_base_url,
            "FP_ENVIRONMENT" => fp_env[:environment] || "prod",
            "FP_EPHEMERAL" => fp_env[:ephemeral] ? "true" : "false"
          }
        end

        # --- Payloads ----------------------------------------------------------

        def self.extract_work_context(payload)
          data = payload["data"] || payload

          {
            work_id: data["work_id"],
            slug: data["slug"],
            title: data["title"],
            description: data["description"],
            why: data["why"],
            acceptance_criteria: data["acceptance_criteria"] || data.dig("requirement", "acceptance"),
            project_key: data["project_key"] || data["project"],
            assigned_agent: data["assigned_agent"] || data.dig("agent", "name"),
            priority: data["priority"],
            tags: data["tags"] || []
          }
        end

        # Which FP instance sent this, so the agent talks to the same one.
        def self.extract_fp_environment(payload)
          metadata = payload["metadata"] || {}

          {
            environment: metadata["environment"] || "prod",
            api_base_url: metadata["api_base_url"],
            ephemeral: metadata["ephemeral"] || false
          }
        end

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

        # A rejection can only be reworked where its agent's worktree still exists.
        def self.validate_work_item(work_item)
          worktree = work_item["worktree"]
          agent_name = work_item["agent"]

          unless worktree && File.directory?(worktree)
            LOG.warn "[FeatureParity] Worktree not found for work item #{work_item['id']}: #{worktree}"
            return [200, { status: "ignored", reason: "worktree not found" }.to_json]
          end

          unless local_agent(agent_name)
            LOG.info "[FeatureParity] Agent '#{agent_name}' is not local, skipping"
            return [200, { status: "ignored", reason: "non-local agent" }.to_json]
          end

          nil
        end

        def self.get_fp_env_from_work_item(work_item)
          fp_source = work_item.dig("sources", "featureparity") || {}
          {
            environment: fp_source["environment"] || "prod",
            api_base_url: fp_source["api_base_url"],
            ephemeral: fp_source["ephemeral"] || false
          }
        end

        def self.ignored_response(reason, slug)
          LOG.warn "[FeatureParity] Could not find work item for rejection: #{slug}"
          [200, { status: "ignored", reason: reason }.to_json]
        end

        # --- Finding work items ------------------------------------------------

        # A work item by where the rejected requirement came from.
        def self.find_work_item_from_source(source_type, source_url)
          finder = source_finder_for(source_type)
          return nil unless finder

          finder.call(load_work_item_map, source_url)
        end

        def self.source_finder_for(source_type)
          {
            "fizzy" => ->(items, url) { find_by_fizzy_source(items, url) },
            "discord" => ->(items, url) { find_by_discord_source(items, url) },
            "featureparity" => ->(items, url) { find_by_fp_source(items, url) }
          }[source_type]
        end

        def self.find_by_fizzy_source(work_items, url)
          card_number = extract_fizzy_card_number(url)
          return nil unless card_number

          find_work_item_by_fizzy_card(work_items, card_number)
        end

        def self.find_by_discord_source(work_items, url)
          thread_id = extract_discord_thread_id(url)
          return nil unless thread_id

          find_work_item_by_discord_thread(work_items, thread_id)
        end

        def self.find_by_fp_source(work_items, url)
          slug = extract_fp_slug(url)
          return nil unless slug

          find_work_item_by_fp_requirement_in_items(work_items, slug)
        end

        # The requirement slug from an FP URL, or the string itself when it is a bare slug.
        def self.extract_fp_slug(url)
          return nil unless url

          if url.include?("/requirements/")
            match = url.match(%r{/requirements/([^/\s]+)})
            return match&.[](1)
          end

          url.to_s.strip.empty? ? nil : url.to_s.strip
        end

        def self.find_work_item_by_fp_requirement(slug)
          return nil unless slug

          find_work_item_by_fp_requirement_in_items(load_work_item_map, slug)
        end

        # The work item whose FeatureParity source is this requirement, with its id.
        def self.find_work_item_by_fp_requirement_in_items(work_items, slug)
          found = work_items.find do |_, item|
            fp_source = item.is_a?(Hash) && item.dig("sources", "featureparity")
            fp_source && fp_source["slug"]&.to_s == slug.to_s
          end
          found && { "id" => found[0] }.merge(found[1])
        end

        def self.extract_fizzy_card_number(url)
          return nil unless url

          match = url.match(%r{/cards/(\d+)})
          match&.[](1)
        end

        def self.extract_discord_thread_id(url)
          return nil unless url

          if url.include?("discord.com")
            match = url.match(%r{/channels/\d+/(\d+)})
            return match&.[](1)
          end

          url.to_s.match?(/^\d+$/) ? url : nil
        end

        def self.find_work_item_by_fizzy_card(work_items, card_number)
          work_items.values.find do |item|
            fizzy_source = item.dig("sources", "fizzy")
            next unless fizzy_source

            fizzy_source["card_number"]&.to_s == card_number.to_s
          end
        end

        def self.find_work_item_by_discord_thread(work_items, thread_id)
          work_items.values.find do |item|
            discord_source = item.dig("sources", "discord")
            next unless discord_source

            discord_source["thread_id"]&.to_s == thread_id.to_s
          end
        end

        def self.build_change_details(data)
          data["kind"] == "removal" ? "Proposed deletion of this requirement" : "Proposed modification to requirement content"
        end
      end
    end
  end
end
