# agent-comm

[English](./README.md) | [日本語](./README.ja.md)

`agent-comm` is a bash-first multi-agent runner for Codex / Claude setups with per-role runtime selection. Clone it wherever you want, point `working_dir` at the target project or worktree, copy `agent-comm.ini.example` and `agents.ini.example`, edit the config files, then use `start` to launch tmux agents and the local dashboard without scattering runtime files into the target project root.

![Dashboard overview](./docs/readme/dashboard-overview.png)

## Requirements

- `bash`, `tmux`, `python3`, and `git`
- The runtime CLI for every section you enable in `agents.ini`
- `codex` for `runtime = codex`
- `claude` for `runtime = claude`
- An authenticated session for each enabled runtime before `bin/agent-comm start`
- The directory you set in `working_dir` must already be trusted by the runtimes you use

## Quick Start

1. Run `git clone https://github.com/sargienest/agent-comm.git && cd agent-comm`.
2. Copy `agent-comm.ini.example` to `agent-comm.ini`.
3. Copy `agents.ini.example` to `agents.ini`.
4. If you want notifications, copy `.env.example` to `.env`.
5. Edit `agent-comm.ini` and set `runtime.working_dir` to the target project or worktree.
6. If you want notifications, enable the flags you need under `[notification]`. For Discord delivery, also enable `[discord].enable`.
7. Edit `agents.ini`.
8. If Discord notifications are enabled, set the webhook value in `.env` using the env var name referenced by `[discord].webhook_url`.
9. Make sure the `working_dir` path is already trusted by the runtimes you use.
10. Log in to the runtimes you use.
11. Run `bin/agent-comm start`.
12. Open the dashboard URL printed by `start` or `status`.

The shipped `agents.ini.example` stays Codex-only so the first launch works with one authenticated runtime. Switch any section to `claude` when you want a mixed topology.

## Public Commands

- `bin/agent-comm validate-config`
- `bin/agent-comm start`
- `bin/agent-comm stop`
- `bin/agent-comm restart <coordinator|task_author|dispatcher|investigation|analyst|tester|implementers|reviewers|workers|implementerN|reviewerN|all>`
- `bin/agent-comm status`
- `bin/agent-comm dashboard [start|stop|status]`
- `bin/agent-comm send --agent <id> --message <text|file>`

## How It Works

- `coordinator` receives the user request.
- `task_author` turns that request into task files.
- The dispatcher routes each task to the right agent or pool.
- Research, implementation, testing, and review report back through `.runtime/reports/events`.
- If a worker cannot proceed safely, it opens a question, the dispatcher notifies `coordinator`, and the answer is appended before the task is re-queued.
- `task_author` decides the next tasks or finalization, and `coordinator` returns the final answer.

## Runtime Layout

All generated data stays inside `agent-comm/.runtime/`.

- `.runtime/commands`
- `.runtime/tasks`
- `.runtime/reviews`
- `.runtime/questions`
- `.runtime/events`
- `.runtime/reports`
- `.runtime/status`
- `.runtime/manual-prompts`
- `.runtime/research_results`

## Config

`agent-comm.ini` controls shared runtime behavior and optional notifications.

| Section | Key | Default | Description |
| --- | --- | --- | --- |
| `runtime` | `working_dir` | empty | Working directory used for tmux panes and agent processes. Relative paths are resolved from `agent-comm.ini`. `start` fails until you set it. |
| `runtime` | `language` | `en` | Default language for agent-facing prompts, role resolution, and dispatcher notifications. If `ui.language` is blank, the dashboard also uses this value. |
| `runtime` | `codex_home` | `~/.codex` | Codex config and auth directory. Claude uses its normal user auth store. |
| `runtime` | `dangerously_bypass_approvals_and_sandbox` | `false` | Enables runtime-specific no-approval launch flags. For Codex this adds `--dangerously-bypass-approvals-and-sandbox`. For Claude this adds `--dangerously-skip-permissions`. |
| `tmux` | `session_name` | empty | tmux session name. If blank, `agent-comm` generates a per-repo unique name automatically. |
| `ui` | `auto_start` | `true` | Starts the local dashboard automatically when `start` runs. `false` still allows `bin/agent-comm dashboard start`. |
| `ui` | `port` | `43861` | Local dashboard port. |
| `ui` | `open_browser` | `false` | Opens the dashboard URL in the OS default browser after startup. |
| `ui` | `language` | empty | Optional dashboard-only override. If blank, the dashboard uses `runtime.language`. Missing translations fall back to `en`, then to empty strings. |
| `roles` | `extra_paths` | empty | Comma-separated extra role roots. Each path is resolved from `agent-comm.ini` and should contain `<path>/<lang>/...`. |
| `notification` | `command_received` | `false` | Sends a notification when dispatcher accepts a new command and forwards it to `task_author`. |
| `notification` | `research_completed` | `false` | Sends a notification when the investigation / analyst result set is ready for `task_author`. |
| `notification` | `implementation_task_created` | `false` | Sends a notification each time `task_author` writes an implementation task for the implementer pool. |
| `notification` | `implementer_started` | `false` | Sends a notification when dispatcher dispatches an implementation or rework task to an implementer. |
| `notification` | `tester_started` | `false` | Sends a notification when dispatcher dispatches a tester task. |
| `notification` | `review_started` | `false` | Sends a notification when the overall review fan-out starts. |
| `notification` | `review_approved` | `false` | Sends a notification when the overall review finishes with `approve`. |
| `notification` | `review_requested_changes` | `false` | Sends a notification when the overall review returns `requestchange` and a rework task is created. |
| `notification` | `workflow_completed` | `false` | Sends a notification when the full command flow completes successfully. |
| `notification` | `question_opened` | `false` | Sends a notification when a worker opens a user-facing question. |
| `discord` | `enable` | `false` | Enables Discord delivery for the notification events above. |
| `discord` | `webhook_url` | `DISCORD_WEBHOOK_URL` | Env var name to resolve from the shell or `.env`. This is a variable name, not the webhook URL itself. |

`agents.ini` controls the agent topology.

`.env` stores local notification secrets.

| Key | Default | Description |
| --- | --- | --- |
| `DISCORD_WEBHOOK_URL` | empty | Discord webhook URL used when `agent-comm.ini` has `discord.enable = true` and `discord.webhook_url = DISCORD_WEBHOOK_URL`. |

Rules:

- `runtime` supports `codex` or `claude`.
- `model` is optional. If blank, `agent-comm` does not pass `--model`, so the runtime CLI default is used.
- `count` is used only by `[implementer]` and `[reviewer]`.
- `investigation`, `analyst`, and `tester` are fixed single agents.
- `reviewer.count` fans a review task out to every reviewer. Each reviewer receives its own child review task.

| Section | Keys | Description |
| --- | --- | --- |
| `[coordinator]` | `runtime`, `model` | User-facing intake agent. `model` blank means the runtime CLI default model. |
| `[task_author]` | `runtime`, `model` | Splits work into research, implementation, test, and review tasks. `model` blank means the runtime CLI default model. |
| `[dispatcher]` | `runtime`, `model` | Runs the queue/snapshot loop. The dispatcher itself stays a bash process, but this section is kept so the dashboard and topology stay explicit. `model` blank means the runtime CLI default model. |
| `[investigation]` | `runtime`, `model` | Dedicated research agent for `investigation` tasks. `model` blank means the runtime CLI default model. |
| `[analyst]` | `runtime`, `model` | Dedicated research agent for `analyst` tasks. `model` blank means the runtime CLI default model. |
| `[tester]` | `runtime`, `model` | Dedicated test execution agent. `model` blank means the runtime CLI default model. |
| `[implementer]` | `runtime`, `model`, `count` | Pooled implementation / rework agents. Tasks are dispatched to idle implementers. `model` blank means the runtime CLI default model. |
| `[reviewer]` | `runtime`, `model`, `count` | Pooled review agents. A review task is expanded into one child task per reviewer. `model` blank means the runtime CLI default model. |

## Dispatch Rules

- `investigation` tasks go to `investigation`.
- `analyst` tasks go to `analyst`.
- `implementation` and `rework` tasks go to the `implementer` pool.
- tester tasks go to `tester`.
- review tasks go to every reviewer in the `reviewer` pool.
- Review completion is aggregated back into one parent review result for `task_author`.

## Role Format

Role files live under `i18n/roles/<lang>/`.
Persona files live under `i18n/roles/<lang>/personas/`.

Each role file must start with YAML frontmatter:

```md
---
id: tester
kind: persona
label: Tester
lang: en
required: true
---
```

`kind` must be one of `agent`, `persona`, or `shared`.
`lang` is required.
The loader resolves roles in this order: `target language -> en -> available file`.

Required standard roles are:

- `coordinator`
- `task_author`
- `worker`
- `common`
- `implementer`
- `tester`
- `reviewer`
- `investigation`
- `analyst`

## Dashboard API

- `GET /api/snapshot`
- `GET /api/tmux/snapshot`
- `POST /api/tmux/send`

The dashboard server is local-only and uses Python standard library modules only.

## Contributing

If you do not have write access, fork the repository, create a branch in your fork, and open a pull request back to `sargienest/agent-comm`.

## License

Distributed under the MIT License. See [LICENSE](./LICENSE).
