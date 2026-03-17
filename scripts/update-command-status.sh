#!/bin/bash
# command の status を更新する

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

usage() {
    ac_t "usage.update_command_status"
}

STATUS=""
OUTPUT_PATH="${COMMANDS_DIR}/command.yaml"

while [ $# -gt 0 ]; do
    case "$1" in
        --status)
            STATUS="${2:-}"
            shift 2
            ;;
        --output)
            OUTPUT_PATH="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            ac_t_format "cli.error.unknown_argument" "arg=$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

case "$STATUS" in
    pending|inflight|done|blocked) ;;
    *)
        ac_t "update_command_status.error.invalid_status" >&2
        exit 1
        ;;
esac

if [ ! -f "$OUTPUT_PATH" ]; then
    ac_t_format "update_command_status.error.command_file_missing" "output_path=${OUTPUT_PATH}" >&2
    exit 1
fi

ac_set_yaml_scalar "$OUTPUT_PATH" "status" "$STATUS"
ac_set_yaml_scalar "$OUTPUT_PATH" "updated_at" "$(ac_now_iso)"

ac_t_format "update_command_status.success.updated" "status=${STATUS}"
