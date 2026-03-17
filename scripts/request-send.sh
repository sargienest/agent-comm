#!/bin/bash
# 非dispatcher用: 送信要求イベントを outbox に積む

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

usage() {
    cat <<'USAGE'
使い方:
  ./scripts/request-send.sh --target <agent|discord> --message <text> [--title <text>] [--channel <agent|discord>]

例:
  ./scripts/request-send.sh --target implementer1 --message "タスクを確認してください"
  ./scripts/request-send.sh --channel discord --target coordinator --title "質問" --message "ユーザー確認が必要です"
USAGE
}

detect_requester() {
    local window_pane pane_index

    if [ -n "${TMUX:-}" ]; then
        window_pane=$(tmux display-message -p '#W.#P' 2>/dev/null || true)
        case "$window_pane" in
            coordinator.*) echo "coordinator" ; return ;;
            task-author.*) echo "task_author" ; return ;;
            dispatcher.*) echo "dispatcher" ; return ;;
            investigation.*) echo "investigation" ; return ;;
            analyst.*) echo "analyst" ; return ;;
            tester.*) echo "tester" ; return ;;
            implementer.*)
                pane_index="${window_pane#implementer.}"
                if [[ "$pane_index" =~ ^[0-9]+$ ]]; then
                    echo "implementer$((pane_index + 1))"
                    return
                fi
                ;;
            reviewer.*)
                pane_index="${window_pane#reviewer.}"
                if [[ "$pane_index" =~ ^[0-9]+$ ]]; then
                    echo "reviewer$((pane_index + 1))"
                    return
                fi
                ;;
        esac
    fi

    echo "external"
}

TARGET=""
MESSAGE=""
TITLE=""
CHANNEL="agent"

while [ $# -gt 0 ]; do
    case "$1" in
        --target)
            TARGET="${2:-}"
            shift 2
            ;;
        --message)
            MESSAGE="${2:-}"
            shift 2
            ;;
        --title)
            TITLE="${2:-}"
            shift 2
            ;;
        --channel)
            CHANNEL="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "❌ エラー: 不明な引数です: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo "❌ エラー: --target は必須です。" >&2
    exit 1
fi

if [ -z "$MESSAGE" ]; then
    echo "❌ エラー: --message は必須です。" >&2
    exit 1
fi

case "$CHANNEL" in
    agent|discord) ;;
    *)
        echo "❌ エラー: --channel は agent|discord を指定してください。" >&2
        exit 1
        ;;
esac

ac_ensure_dirs

requester=$(detect_requester)
created_at=$(ac_now_iso)
event_id="sendreq_$(date '+%Y%m%d_%H%M%S')_$RANDOM"
out_file="${EVENT_OUTBOX_DIR}/${event_id}.yaml"
tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT

{
    echo "id: \"$(ac_escape_yaml_double_quoted "$event_id")\""
    echo "event_type: \"send_request\""
    echo "channel: \"$(ac_escape_yaml_double_quoted "$CHANNEL")\""
    echo "target: \"$(ac_escape_yaml_double_quoted "$TARGET")\""
    echo "title: \"$(ac_escape_yaml_double_quoted "$TITLE")\""
    echo "message: |"
    printf '%s\n' "$MESSAGE" | sed 's/^/  /'
    echo "requested_by: \"$(ac_escape_yaml_double_quoted "$requester")\""
    echo "status: \"pending\""
    echo "created_at: \"$(ac_escape_yaml_double_quoted "$created_at")\""
} > "$tmp_file"

chmod 0644 "$tmp_file"

ac_atomic_write_from_tmp "$tmp_file" "$out_file"
trap - EXIT

echo "✅ 送信要求を作成しました: ${out_file}"
