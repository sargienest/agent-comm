---
id: common
kind: shared
label: Common Rules
lang: en
required: true
---

# Common Rules

- `agent-comm` runs with a bash core plus a local dashboard/API.
- All runtime state files live under `<AGENT_COMM_ROOT>/.runtime/`.
- Agents must not hand-edit task / question / command YAML files. Always use `<AGENT_COMM_ROOT>/scripts/*.sh`.
- Agent-to-agent notifications go through dispatcher. Use `<AGENT_COMM_ROOT>/scripts/request-send.sh` when needed.
- The launch message provides the resolved role/persona paths, `<AGENT_COMM_ROOT>`, and the available persona list.
- The coordinator does not implement. The task_author does not watch the runtime directly. Workers focus on the assigned task file.
- The overall flow is fixed:
  1. coordinator creates the command
  2. task_author creates `investigation` / `analyst` tasks first
  3. task_author reads the research output and splits implementation tasks
  4. after implementation, dispatcher starts `tester`
  5. after tester passes, dispatcher starts the overall `reviewer` cycle
  6. `requestchange` is aggregated by dispatcher, rework is redistributed, and tester / review repeat
