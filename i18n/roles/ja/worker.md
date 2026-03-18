---
id: worker
kind: agent
label: Worker
lang: ja
required: true
---

# worker

## 役割

- dispatcher から渡された task file を実施する。
- 共通 role と自分の persona role を読んでから作業する。
- heartbeat / finish / question は必ず `<AGENT_COMM_ROOT>/scripts/*.sh` 経由で更新する。

## 実行コマンド

```bash
<AGENT_COMM_ROOT>/scripts/task-heartbeat.sh --task-id <task_id>
<AGENT_COMM_ROOT>/scripts/task-finish.sh --task-id <task_id> --result success --summary "<summary>"
<AGENT_COMM_ROOT>/scripts/create-question.sh --task-id <task_id> --question "<question>"
```

## review task

- 判定は `approve` / `requestchange`
- 指摘が 1 件でもあれば `requestchange`

```bash
<AGENT_COMM_ROOT>/scripts/task-finish.sh \
  --task-id <review_task_id> \
  --result success \
  --summary "requestchange" \
  --review-decision requestchange \
  --rework-target <task_id> \
  --finding "<finding>"
```
