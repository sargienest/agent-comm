---
id: common
kind: shared
label: Common Rules
lang: ja
required: true
---

# 共通ルール

- `agent-comm` は bash コア + ローカル dashboard/API で動く。
- runtime の状態ファイルはすべて `<AGENT_COMM_ROOT>/.runtime/` にある。
- エージェントは task / question / command の YAML を手編集しない。必ず `<AGENT_COMM_ROOT>/scripts/*.sh` を使う。
- エージェント間の通知は dispatcher 経由で行う。必要なら `<AGENT_COMM_ROOT>/scripts/request-send.sh` を使う。
- role / persona の実体パス、`<AGENT_COMM_ROOT>`、利用可能 persona 一覧は起動メッセージで渡される。
- coordinator は実装しない。task_author は監視しない。worker は割り当てられた task file に集中する。
- 全体フローは固定:
  1. coordinator が command を投入する
  2. task_author が `investigation` / `analyst` を先に作る
  3. 調査成果を読んで実装タスクへ分解する
  4. 実装後に `tester` がテスト実行を担当する
  5. 通過後に `reviewer` が全体レビューする
  6. `requestchange` は task_author が再作業へ戻す
