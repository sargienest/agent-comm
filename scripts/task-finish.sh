#!/bin/bash
# Worker completion handler: update task state, release locks, and write reports.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

usage() {
    ac_t "usage.task_finish"
}

TASK_ID=""
RESULT=""
SUMMARY=""
DETAILS=""
REVIEW_DECISION=""
TASK_TYPE=""
REWORK_TARGETS=()
FINDINGS=()
RESULT_ARTIFACT_PATH=""
REVIEW_PARENT_ID=""

while [ $# -gt 0 ]; do
    case "$1" in
        --task-id)
            TASK_ID="${2:-}"
            shift 2
            ;;
        --result)
            RESULT="${2:-}"
            shift 2
            ;;
        --summary)
            SUMMARY="${2:-}"
            shift 2
            ;;
        --details)
            DETAILS="${2:-}"
            shift 2
            ;;
        --review-decision)
            REVIEW_DECISION="${2:-}"
            shift 2
            ;;
        --rework-target)
            REWORK_TARGETS+=("${2:-}")
            shift 2
            ;;
        --finding)
            FINDINGS+=("${2:-}")
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

if [ -z "$TASK_ID" ] || [ -z "$RESULT" ] || [ -z "$SUMMARY" ]; then
    usage >&2
    exit 1
fi

ac_assert_task_id "$TASK_ID"

case "$RESULT" in
    success|failure|blocked) ;;
    *)
        ac_t "task_finish.error.invalid_result" >&2
        exit 1
        ;;
esac

if [ -n "$REVIEW_DECISION" ]; then
    case "$REVIEW_DECISION" in
        approve|requestchange) ;;
        *)
            ac_t "task_finish.error.invalid_review_decision" >&2
            exit 1
            ;;
    esac
fi

for i in "${!REWORK_TARGETS[@]}"; do
    REWORK_TARGETS[$i]=$(ac_trim "${REWORK_TARGETS[$i]}")
done

local_filtered_targets=()
for target_id in "${REWORK_TARGETS[@]}"; do
    [ -z "$target_id" ] && continue
    local_filtered_targets+=("$target_id")
done
REWORK_TARGETS=("${local_filtered_targets[@]}")

if [ "$REVIEW_DECISION" = "requestchange" ] && [ "${#REWORK_TARGETS[@]}" -eq 0 ]; then
    ac_t "task_finish.error.rework_target_required" >&2
    exit 1
fi

for target_id in "${REWORK_TARGETS[@]}"; do
    ac_assert_task_id "$target_id"
    if ! ac_find_task_file_by_id "$target_id" >/dev/null 2>&1; then
        ac_t_format "task_finish.error.rework_target_not_found" "target_id=${target_id}" >&2
        exit 1
    fi
done

ac_ensure_dirs

if ! task_file=$(ac_find_task_file_by_id "$TASK_ID" 2>/dev/null); then
    ac_t_format "task_finish.error.task_not_found" "task_id=${TASK_ID}" >&2
    exit 1
fi

state=$(ac_task_state_from_path "$task_file")
if [ "$state" != "inflight" ]; then
    ac_t_format "task_finish.error.inflight_only" "state=${state}" >&2
    exit 1
fi

kind=$(ac_task_kind_from_path "$task_file")
persona=$(ac_read_yaml_scalar "$task_file" "persona")
TASK_TYPE=$(ac_read_yaml_scalar "$task_file" "type")
worker_id=$(ac_read_yaml_scalar "$task_file" "assigned_to")
command_id=$(ac_read_yaml_scalar "$task_file" "command_id")
if [ -z "$worker_id" ]; then
    ac_t_format "task_finish.error.assigned_to_missing" "task_id=${TASK_ID}" >&2
    exit 1
fi
ac_validate_worker_id "$worker_id"

now_iso=$(ac_now_iso)

new_status="done"
if [ "$kind" = "task" ] && [ "$RESULT" != "success" ]; then
    new_status="blocked"
fi

if [ "$kind" = "task" ] && [ "$new_status" = "blocked" ]; then
    blocked_reason=$(ac_read_yaml_scalar "$task_file" "blocked_reason")
    if [ -z "$blocked_reason" ]; then
        case "$RESULT" in
            failure) blocked_reason="failure" ;;
            blocked) blocked_reason="blocked" ;;
            *) blocked_reason="$RESULT" ;;
        esac
        ac_set_yaml_scalar "$task_file" "blocked_reason" "$blocked_reason"
    fi
fi
if [ -z "$TASK_TYPE" ]; then
    TASK_TYPE="task"
fi
if [ "$TASK_TYPE" = "investigation" ] || [ "$TASK_TYPE" = "analyst" ]; then
    RESULT_ARTIFACT_PATH=$(ac_read_yaml_scalar "$task_file" "result_artifact_path")
    if [ -z "$RESULT_ARTIFACT_PATH" ]; then
        RESULT_ARTIFACT_PATH="$(ac_default_research_result_path "$TASK_ID")"
    fi
    ac_set_yaml_scalar "$task_file" "result_artifact_path" "$RESULT_ARTIFACT_PATH"
fi
REVIEW_PARENT_ID=$(ac_read_yaml_scalar "$task_file" "review_parent_id")

ac_set_yaml_scalar "$task_file" "status" "$new_status"
ac_set_yaml_scalar "$task_file" "result" "$RESULT"
ac_set_yaml_scalar "$task_file" "updated_at" "$now_iso"
ac_set_yaml_scalar "$task_file" "completed_at" "$now_iso"

if [ "$kind" = "task" ]; then
    if [ "$new_status" = "done" ]; then
        destination="${TASK_DONE_DIR}/$(basename "$task_file")"
    else
        destination="${TASK_BLOCKED_DIR}/$(basename "$task_file")"
    fi
else
    destination="${REVIEW_DONE_DIR}/$(basename "$task_file")"
fi

mv "$task_file" "$destination"

ac_release_task_locks "$destination"

report_status="done"
if [ "$RESULT" != "success" ]; then
    report_status="failure"
fi

report_header_file="${REPORTS_DIR}/${worker_id}_report.yaml"
report_event_file="${REPORT_EVENTS_DIR}/report_${TASK_ID}_$(date '+%Y%m%d_%H%M%S')_$RANDOM.yaml"

write_report() {
    local out_file="$1"
    {
        echo "worker_id: \"$(ac_escape_yaml_double_quoted "$worker_id")\""
        echo "task_id: \"$(ac_escape_yaml_double_quoted "$TASK_ID")\""
        echo "persona: \"$(ac_escape_yaml_double_quoted "$persona")\""
        echo "type: \"$(ac_escape_yaml_double_quoted "$TASK_TYPE")\""
        echo "command_id: \"$(ac_escape_yaml_double_quoted "$command_id")\""
        echo "review_parent_id: \"$(ac_escape_yaml_double_quoted "$REVIEW_PARENT_ID")\""
        echo "status: \"$(ac_escape_yaml_double_quoted "$report_status")\""
        echo "result: \"$(ac_escape_yaml_double_quoted "$RESULT")\""
        echo "result_artifact_path: \"$(ac_escape_yaml_double_quoted "$RESULT_ARTIFACT_PATH")\""
        echo "summary: |"
        printf '%s\n' "$SUMMARY" | sed 's/^/  /'
        echo "details: |"
        if [ -n "$DETAILS" ]; then
            printf '%s\n' "$DETAILS" | sed 's/^/  /'
        else
            echo "  "
        fi
        echo "review_decision: \"$(ac_escape_yaml_double_quoted "$REVIEW_DECISION")\""
        ac_write_yaml_list_block "rework_targets" "${REWORK_TARGETS[@]}"
        ac_write_yaml_list_block "findings" "${FINDINGS[@]}"
        echo "completed_at: \"$(ac_escape_yaml_double_quoted "$now_iso")\""
    } | ac_atomic_write_stdin "$out_file"
}

write_research_artifact() {
    local artifact_path="$1"
    local task_type="$2"
    local artifact_dir

    [ -n "$artifact_path" ] || return 0
    artifact_dir=$(dirname "$artifact_path")
    mkdir -p "$artifact_dir"

    # Preserve an existing research artifact instead of overwriting it.
    if [ -f "$artifact_path" ] && [ -s "$artifact_path" ]; then
        ac_t_format "task_finish.info.artifact_preserved" "artifact_path=${artifact_path}" >&2
        return 0
    fi

    {
        ac_t_format "task_finish.artifact.header" "task_type=${task_type}"
        echo "task_id: \"$(ac_escape_yaml_double_quoted "$TASK_ID")\""
        echo "worker_id: \"$(ac_escape_yaml_double_quoted "$worker_id")\""
        echo "persona: \"$(ac_escape_yaml_double_quoted "$persona")\""
        echo "result: \"$(ac_escape_yaml_double_quoted "$RESULT")\""
        echo "completed_at: \"$(ac_escape_yaml_double_quoted "$now_iso")\""
        echo "summary: |"
        printf '%s\n' "$SUMMARY" | sed 's/^/  /'
        echo "details: |"
        if [ -n "$DETAILS" ]; then
            printf '%s\n' "$DETAILS" | sed 's/^/  /'
        else
            echo "  "
        fi
    } | ac_atomic_write_stdin "$artifact_path"
}

write_report "$report_header_file"
write_report "$report_event_file"
if [ "$TASK_TYPE" = "investigation" ] || [ "$TASK_TYPE" = "analyst" ]; then
    if ! write_research_artifact "$RESULT_ARTIFACT_PATH" "$TASK_TYPE"; then
        ac_t_format "task_finish.warn.artifact_save_failed" "artifact_path=${RESULT_ARTIFACT_PATH}" >&2
    fi
fi

ac_t_format "task_finish.success.completed" "task_id=${TASK_ID}" "new_status=${new_status}" "destination=${destination}"
