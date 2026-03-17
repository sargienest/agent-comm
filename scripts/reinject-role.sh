#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

if [ $# -lt 1 ]; then
    ac_fail "使い方: ./scripts/reinject-role.sh <coordinator|task_author|investigation|analyst|tester|implementers|reviewers|implementerN|reviewerN|all>"
fi

reinject() {
    local agent_id="$1"
    local role_id="$2"
    local extra="${3:-}"
    ac_send_direct_message "$agent_id" "${AC_RESET_COMMAND}
$(ac_render_reinject_message "$(ac_role_path "$role_id")" "$extra")"
}

reinject_worker() {
    local agent_id="$1"
    ac_validate_worker_id "$agent_id"
    reinject "$agent_id" worker "$(ac_render_default_persona_line "$(ac_role_path "$(ac_worker_persona "$agent_id")")")"
}

reinject_section_workers() {
    local section="$1"
    local agent_id
    while IFS= read -r agent_id; do
        [ -n "$agent_id" ] || continue
        reinject_worker "$agent_id"
    done < <(ac_section_agent_ids "$section")
}

case "$1" in
    coordinator)
        reinject coordinator coordinator
        ;;
    task_author|manager)
        reinject task_author task_author "$(ac_render_personas_manifest_line)"
        ;;
    investigation|analyst|tester|implementer*|reviewer*)
        reinject_worker "$1"
        ;;
    implementers)
        reinject_section_workers implementer
        ;;
    reviewers)
        reinject_section_workers reviewer
        ;;
    all)
        reinject coordinator coordinator
        reinject task_author task_author "$(ac_render_personas_manifest_line)"
        reinject_section_workers investigation
        reinject_section_workers analyst
        reinject_section_workers tester
        reinject_section_workers implementer
        reinject_section_workers reviewer
        ;;
    *)
        ac_fail "不明な対象です: $1"
        ;;
esac

echo "role reinjected: $1"
