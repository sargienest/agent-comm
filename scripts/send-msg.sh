#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

usage() {
    cat <<'USAGE'
使い方:
  ./scripts/send-msg.sh <target> <message>

target:
  coordinator | task_author | dispatcher | investigation | analyst | tester | implementerN | reviewerN
USAGE
}

if [ "$#" -lt 2 ]; then
    usage >&2
    exit 1
fi

TARGET_NAME="$1"
MESSAGE="$2"

ac_ensure_runtime_dirs
TARGET="$(ac_agent_tmux_target "$TARGET_NAME" 2>/dev/null || true)"
[ -n "$TARGET" ] || ac_fail_with_code "invalid_agent" "送信先 agent が不正です: ${TARGET_NAME}"
tmux list-panes -t "$TARGET" >/dev/null 2>&1 || ac_fail_with_code "tmux_target_missing" "tmux ターゲットが存在しません: ${TARGET}"
ac_send_direct_message "$TARGET_NAME" "$MESSAGE"

echo "✅ 送信しました: ${TARGET_NAME}"
