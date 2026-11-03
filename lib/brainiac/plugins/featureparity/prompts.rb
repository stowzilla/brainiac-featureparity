# frozen_string_literal: true

module Brainiac
  module Plugins
    module Featureparity
      # Prompt templates for FeatureParity agent dispatches.
      module Prompts
        # Channel-specific prompt for FeatureParity interactions.
        # Injected into the agent prompt when dispatching for FP events.
        CHANNEL = <<~PROMPT
          ## FeatureParity Channel Rules

          You're responding to a FeatureParity webhook event. FeatureParity tracks requirements
          and their test coverage across surfaces.

          ### FP Environment

          This work is coming from a specific FP environment:
          - **API URL:** {{FP_API_URL}}
          - **Environment:** {{FP_ENVIRONMENT}}
          - **Ephemeral:** {{FP_EPHEMERAL}}

          **CRITICAL:** You MUST use `--api-url {{FP_API_URL}}` with ALL `fp` CLI commands.
          This ensures you're reading from and writing to the correct FP instance (prod vs dev vs ephemeral).

          ```bash
          # CORRECT - always include --api-url
          fp show <slug> --project <project> --api-url {{FP_API_URL}}
          fp list --project <project> --api-url {{FP_API_URL}}
          fp propose-change <slug> --project <project> --api-url {{FP_API_URL}} ...

          # WRONG - will hit production FP even if you're working on dev
          fp show <slug> --project <project>
          ```

          ### Requirement Work Workflow

          When implementing a requirement from FP:
          1. Read the requirement details to understand the spec
          2. Implement the feature/fix in your worktree
          3. Write tests that satisfy the acceptance criteria
          4. Bind your tests to the requirement using `fp:<slug>` comments
          5. Commit and push your changes
          6. Open a PR

          ### Requirement Rejection Workflow

          A human has rejected a proposed change to a requirement. Your job:
          1. Read the rejection reason to understand what's wrong
          2. Review the requirement's current state in FP
          3. Make the necessary code/test changes to address the feedback
          4. Update the requirement in FP if needed using `fp` CLI commands (with --api-url!)
          5. Push changes and update the PR

          ### FP CLI Commands

          Remember: ALWAYS include `--api-url {{FP_API_URL}}`

          ```bash
          fp show <slug> --project <project> --api-url {{FP_API_URL}}
          fp list --project <project> --api-url {{FP_API_URL}}
          fp propose-change <slug> --project <project> --api-url {{FP_API_URL}} \\
            --title "..." --why "..." --acceptance "..."
          ```

          ### Test Binding

          To link a test to a requirement, add a comment with `fp:<slug>`:
          ```ruby
          # fp:user-login-validation
          test "validates email format" do
            # ...
          end
          ```

          ### Important Notes

          - When implementing: write tests that directly exercise the acceptance criteria
          - When reworking: address the specific rejection reason — don't make unrelated changes
          - Keep your response focused: what you implemented/changed, what's next
          - **Never forget `--api-url`** — using the wrong FP instance corrupts data
        PROMPT

        # The full prompt template for initial work dispatches (FP-as-source).
        WORK_DISPATCH = <<~PROMPT
          ## FeatureParity: Implement Requirement

          You've been assigned to implement a requirement directly from FeatureParity.

          ### Requirement Details
          - **Slug:** `{{REQUIREMENT_SLUG}}`
          - **Title:** {{REQUIREMENT_TITLE}}
          - **Project:** {{PROJECT_KEY}}

          ### FP Instance
          - **API URL:** {{FP_API_URL}}
          - **Environment:** {{FP_ENVIRONMENT}}

          **CRITICAL:** All `fp` CLI commands MUST include `--api-url {{FP_API_URL}}`

          ### Description
          {{REQUIREMENT_DESCRIPTION}}

          ### Why This Matters
          {{REQUIREMENT_WHY}}

          ### Acceptance Criteria
          {{ACCEPTANCE_CRITERIA}}

          ### Your Task

          1. Read and understand the requirement fully
          2. Implement the feature in your worktree
          3. Write tests that exercise the acceptance criteria
          4. Bind your tests to this requirement using `fp:{{REQUIREMENT_SLUG}}` comments
          5. Commit your changes with a clear message referencing the requirement
          6. Push and open a PR

          Work in the worktree at: {{WORKTREE_PATH}}

          When you commit, include the requirement slug in the message:
          ```
          Implement {{REQUIREMENT_SLUG}}: {{REQUIREMENT_TITLE}}
          ```

          To view or update the requirement in FP:
          ```bash
          fp show {{REQUIREMENT_SLUG}} --project {{PROJECT_KEY}} --api-url {{FP_API_URL}}
          ```
        PROMPT

        # The full prompt template for requirement rejection dispatches.
        REJECTION_DISPATCH = <<~PROMPT
          ## FeatureParity: Requirement Rejection

          A requirement you proposed has been rejected and needs rework.

          ### Rejection Details
          - **Requirement:** `{{REQUIREMENT_SLUG}}` — {{REQUIREMENT_TITLE}}
          - **Rejected by:** {{ACTOR}}
          - **Rejection note:** {{REJECTION_NOTE}}

          ### FP Instance
          - **API URL:** {{FP_API_URL}}
          - **Environment:** {{FP_ENVIRONMENT}}

          **CRITICAL:** All `fp` CLI commands MUST include `--api-url {{FP_API_URL}}`

          ### Source Context
          This requirement was proposed from: {{SOURCE_TYPE}} ({{SOURCE_URL}})
          {{SOURCE_CONTEXT}}

          ### What Changed
          {{CHANGE_KIND}}: {{CHANGE_DETAILS}}

          ### Your Task

          1. Review the rejection note to understand what needs to change
          2. Make the necessary fixes in your worktree
          3. Update the requirement in FP if the wording/scope needs adjustment
          4. Commit and push your changes
          5. Summarize what you fixed and why

          Work in the existing worktree at: {{WORKTREE_PATH}}

          To view or update the requirement in FP:
          ```bash
          fp show {{REQUIREMENT_SLUG}} --api-url {{FP_API_URL}}
          fp propose-change {{REQUIREMENT_SLUG}} --api-url {{FP_API_URL}} ...
          ```
        PROMPT

        # Writing the tests a newly active requirement is missing (coverage.gap_detected).
        GAP_DISPATCH = <<~PROMPT
          ## FeatureParity: Write the Missing Tests

          A requirement is now active on surfaces that have no tests yet.

          ### Requirement
          - **Slug:** `{{REQUIREMENT_SLUG}}`
          - **Title:** {{REQUIREMENT_TITLE}}
          - **Project:** {{PROJECT_KEY}}
          - **Missing on:** {{MISSING_SURFACES}}

          ### Acceptance Criteria
          {{ACCEPTANCE_CRITERIA}}

          ### FP Instance
          - **API URL:** {{FP_API_URL}}
          - **Environment:** {{FP_ENVIRONMENT}}

          **CRITICAL:** All `fp` CLI commands MUST include `--api-url {{FP_API_URL}}`

          ### Your Task

          1. Read the requirement: `fp show {{REQUIREMENT_SLUG}} --project {{PROJECT_KEY}} --api-url {{FP_API_URL}}`
          2. For each missing surface, write a test that exercises the acceptance criteria and mark it
             `fp:{{REQUIREMENT_SLUG}}` (pin the surface, e.g. `fp:{{REQUIREMENT_SLUG}}@web`, when one test file serves several).
          3. If the product doesn't do what the acceptance says, don't bend the test to fit: say so, and
             leave a question on the requirement (`fp question {{REQUIREMENT_SLUG}} "..."`) for a human.
          4. Run the tests, commit, push and open a PR.

          Work in the worktree at: {{WORKTREE_PATH}}
        PROMPT

        # Answering a comment that tagged this agent (requirement.agent_mentioned).
        MENTION_DISPATCH = <<~PROMPT
          ## FeatureParity: You Were Tagged

          {{COMMENT_AUTHOR}} tagged you ({{AGENT_NAME}}) in a comment on a requirement.

          ### Requirement
          - **Slug:** `{{REQUIREMENT_SLUG}}`
          - **Title:** {{REQUIREMENT_TITLE}}
          - **Project:** {{PROJECT_KEY}}

          ### The Comment
          {{COMMENT_BODY}}

          ### FP Instance
          - **API URL:** {{FP_API_URL}}
          - **Environment:** {{FP_ENVIRONMENT}}

          **CRITICAL:** All `fp` CLI commands MUST include `--api-url {{FP_API_URL}}`

          ### Your Task

          1. Read the requirement and its discussion:
             `fp show {{REQUIREMENT_SLUG}} --project {{PROJECT_KEY}} --api-url {{FP_API_URL}}`
             `fp comments {{REQUIREMENT_SLUG}} --project {{PROJECT_KEY}} --api-url {{FP_API_URL}}`
          2. Do what was asked. If it is to re-check suspect tests, read the tests marked
             `fp:{{REQUIREMENT_SLUG}}` against the current acceptance, fix them if they no longer prove it,
             and re-report the evidence.
          3. Reply on the requirement so they know what you did:
             `fp comments {{REQUIREMENT_SLUG}} --project {{PROJECT_KEY}} --api-url {{FP_API_URL}} --body "..."`

          Work in: {{WORKTREE_PATH}}
        PROMPT
      end
    end
  end
end
