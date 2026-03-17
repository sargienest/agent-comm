---
id: worker
kind: agent
label: Worker
lang: en
required: true
---

# worker

## Role

- Execute the task file handed to you by dispatcher.
- Read the common role and your assigned persona role before starting work.
- Update heartbeat / finish / question only through `<AGENT_COMM_ROOT>/scripts/*.sh`.

## Commands

```bash
<AGENT_COMM_ROOT>/scripts/task-heartbeat.sh --task-id <task_id>
<AGENT_COMM_ROOT>/scripts/task-finish.sh --task-id <task_id> --result success --summary "<summary>"
<AGENT_COMM_ROOT>/scripts/create-question.sh --task-id <task_id> --question "<question>"
```

## review task

- The only allowed decisions are `approve` / `requestchange`
- If there is even one finding, use `requestchange`

```bash
<AGENT_COMM_ROOT>/scripts/task-finish.sh \
  --task-id <review_task_id> \
  --result success \
  --summary "requestchange" \
  --review-decision requestchange \
  --rework-target <task_id> \
  --finding "<finding>"
```
