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

          ### Requirement Rejection Workflow

          A human has rejected a proposed change to a requirement. Your job:
          1. Read the rejection reason to understand what's wrong
          2. Review the requirement's current state in FP
          3. Make the necessary code/test changes to address the feedback
          4. Update the requirement in FP if needed using `fp` CLI commands
          5. Push changes and update the PR

          ### FP CLI Commands

          ```bash
          fp show <slug>                    # Show requirement details
          fp list --project <project-id>   # List all requirements
          fp propose <slug> --title "..." --why "..." --acceptance "..."  # Update requirement
          ```

          ### Important Notes

          - Address the specific rejection reason — don't make unrelated changes
          - The requirement is back in "draft" status awaiting re-review
          - Your changes should fix whatever the human flagged, then they'll re-review
          - Keep your response focused: what you found, what you changed, what's next
        PROMPT

        # The full prompt template for requirement rejection dispatches.
        REJECTION_DISPATCH = <<~PROMPT
          ## FeatureParity: Requirement Rejection

          A requirement you proposed has been rejected and needs rework.

          ### Rejection Details
          - **Requirement:** `{{REQUIREMENT_SLUG}}` — {{REQUIREMENT_TITLE}}
          - **Rejected by:** {{ACTOR}}
          - **Rejection note:** {{REJECTION_NOTE}}

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
        PROMPT
      end
    end
  end
end
