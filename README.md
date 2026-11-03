# brainiac-featureparity

FeatureParity plugin for [Brainiac](https://github.com/stowzilla/brainiac): your agents take
work straight from [FeatureParity](https://featureparity.dev).

- **Start work.** Someone presses **Start work** on a requirement and picks one of your
  agents. That agent gets a worktree for the requirement and implements it, with tests
  bound to it (`fp:<slug>`).
- **Tags.** Someone tags your agent in a requirement's comments (for example "please
  re-check the suspect tests"). The agent reads the comment, does it, and replies on the
  requirement.
- **Coverage gaps** (opt-in). A requirement goes live on a surface with no tests. An agent
  writes them.
- **Rejections.** A human rejects a change your agent proposed. The same agent reworks it in
  its existing worktree.

Every delivery is signed by FeatureParity, and the plugin refuses anything it can't verify.

## Install

You need Brainiac running with a public URL that reaches it (Brainiac's setup uses an
[ngrok](https://ngrok.com) tunnel), and an account on FeatureParity.

```bash
gem install brainiac          # if you don't have Brainiac yet
brainiac setup                # its own first-run setup
brainiac install featureparity
brainiac featureparity setup  # writes ~/.brainiac/featureparity.json
brainiac restart
```

Every repository your agents should work in must be a project in `~/.brainiac/projects.json`
(Brainiac's usual setup). FeatureParity names projects by their slug (`fp projects`). Name the
Brainiac project the same, or map it (see Configuration).

## Connect FeatureParity

### 1. Point your agents at Brainiac

In FeatureParity, open **Agents & API keys** (under your account). For each agent that runs
on this Brainiac, click **Wake-up** and enter:

```
https://<your-public-url>/featureparity
```

FeatureParity shows a signing secret (`whsec_...`) **once**. Add it to
`~/.brainiac/featureparity.json`:

```json
{ "signing_secrets": ["whsec_..."] }
```

All your agents can share the one address, because each delivery names the agent it's for.
Each key has its own secret, so list every one.

The agent key's name has to match the Brainiac agent: a key named `galen` or shown as `Galen`
reaches the Brainiac agent `Galen`. Map names that differ with `"agents"`.

### 2. Optional: project-wide events

For events no single agent owns, add a webhook in **Project Settings → Integrations**: same
URL, provider **generic**. Subscribe to **Change rejected** and, if you turn on
`dispatch_gaps`, **Coverage gap**. Add its signing secret to `signing_secrets` too.

If your agents already have wake-up addresses, there's no need to subscribe this webhook to
**Work started** or **Agent tagged**. If you do, the plugin notices the repeat and starts the
agent only once.

### 3. Try it

Open an approved requirement, click **Start work**, and pick your agent. The page tells you
whether the agent received it. `brainiac logs` shows the dispatch. Each webhook's **Recent
deliveries** in FeatureParity shows what was sent and what Brainiac answered.

## Configuration

`~/.brainiac/featureparity.json` (reloaded when it changes):

```json
{
  "api_base_url": "https://app.featureparity.dev",
  "environment": "prod",
  "accept_environments": ["prod"],
  "signing_secrets": ["whsec_..."],
  "agents": { "claude-laptop": "Galen" },
  "default_agent": "Galen",
  "projects": { "feature-parity": "feature_parity" },
  "dispatch_gaps": false,
  "gap_agent": "Galen"
}
```

| Key | What it does |
|-----|--------------|
| `signing_secrets` | The `whsec_` secrets FeatureParity showed you. With any set, unsigned or wrongly signed deliveries are refused (401), and so is one stamped more than 5 minutes away from now. Leave it empty only while setting up. |
| `agents` | FeatureParity agent key name (or display name) → Brainiac agent name, for names that differ. Otherwise they match case-insensitively. |
| `default_agent` | Who takes **Start work** when no agent was picked. |
| `projects` | FeatureParity project slug → Brainiac project key, for keys that differ. A project in `projects.json` can also declare `"featureparity_project": "<slug>"`. |
| `dispatch_gaps` | Start an agent on `coverage.gap_detected` to write the missing tests. Off by default, because approving a batch of requirements reports a gap for each one. |
| `gap_agent` | Who writes those tests (defaults to `default_agent`). |
| `environment`, `accept_environments` | Which FeatureParity environments this Brainiac serves. A delivery from a preview environment (`fizzy-1234`) is ignored unless listed here. `["*"]` accepts all. |

## Events

| Event | What happens |
|-------|--------------|
| `requirement.work_started` | The named agent (or `default_agent`) gets the requirement's worktree (`fp-<slug>`, reused if it exists) and implements it. |
| `requirement.agent_mentioned` | The tagged agent, if it runs here, answers the comment, working in the requirement's worktree when there is one. |
| `coverage.gap_detected` | With `dispatch_gaps`, `gap_agent` writes tests for the surfaces listed. Otherwise it's acknowledged. |
| `requirement.change_rejected` | The agent that proposed the change reworks it in its worktree, with the reviewer's reason. |
| others | Acknowledged. |

The plugin answers within FeatureParity's 5-second window and does the work in the
background. FeatureParity retries a delivery that gets no answer; the plugin acts on each
delivery, and each Start work, comment or gap, once.

## CLI

```bash
brainiac featureparity setup   # create the config and show these steps
brainiac featureparity config  # show the config (secrets shortened)
brainiac featureparity status  # what's set up
brainiac featureparity help
```

## Requirements

- Brainiac >= 0.1.8
- Ruby >= 3.4
- A FeatureParity account (agent wake-up addresses and signed deliveries need the current FeatureParity)

## License

MIT
