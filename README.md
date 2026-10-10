# brainiac-featureparity

FeatureParity plugin for Brainiac — routes requirement rejections back to the agent who proposed them for rework.

## What It Does

When you're using Brainiac to orchestrate AI agents that work Fizzy cards or Discord requests, those agents may propose requirements to FeatureParity. When a human reviews those requirements and rejects one:

1. FeatureParity sends a webhook to Brainiac
2. This plugin identifies which agent proposed the requirement (via the Fizzy card or Discord thread it came from)
3. The plugin dispatches that same agent back to the existing worktree to address the rejection

This creates a feedback loop: Agent proposes → Human reviews → If rejected, agent fixes → Human re-reviews.

## Installation

```bash
brainiac install featureparity
brainiac restart
```

## Setup

1. Run the setup command:

```bash
brainiac featureparity setup
```

2. In FeatureParity, go to **Project Settings > Webhooks**

3. Add a webhook:
   - **URL:** `https://your-ngrok.ngrok-free.app/featureparity`
   - **Provider:** `generic`
   - **Events:** Subscribe to "Change rejected" (and optionally others)

4. Test by rejecting a requirement that was proposed from a Fizzy card or Discord thread

## How It Works

When a `requirement.change_rejected` webhook arrives:

1. The plugin reads the `source` field to find where the requirement came from (Fizzy card URL, Discord thread, etc.)
2. It looks up the work item in Brainiac's `work_items.json` by matching the source
3. If found, it dispatches the original agent to the existing worktree with a prompt explaining the rejection
4. The agent reads the rejection reason, makes changes, and updates the PR

## Supported Events

| Event | Action |
|-------|--------|
| `requirement.change_rejected` | Dispatch agent to fix the rejected requirement |
| `requirement.change_approved` | Log acknowledgment (no action) |
| `requirement.change_proposed` | Log acknowledgment (proposals come from agents) |
| `evidence.failing` | Log acknowledgment (future: dispatch to investigate) |
| `coverage.gap_detected` | Log acknowledgment (future: dispatch to write tests) |

## Configuration

Config lives at `~/.brainiac/featureparity.json`:

```json
{
  "api_base_url": "https://app.featureparity.dev",
  "authorized_users": [],
  "authorized_role_ids": []
}
```

## CLI Commands

```bash
brainiac featureparity setup   # Create config and show setup instructions
brainiac featureparity config  # Show current configuration
brainiac featureparity status  # Show plugin status
brainiac featureparity help    # Show help
```

## Requirements

- Brainiac >= 0.1.8
- Ruby >= 3.4
- A FeatureParity account with webhook access

## License

MIT
