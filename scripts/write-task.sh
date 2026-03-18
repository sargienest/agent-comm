#!/bin/bash
# Writes task YAML files for task_author.
# - investigation / analyst / rework may omit write_files.
# - investigation / analyst store outputs in result_artifact_path.
# - Validates depends_on existence, cycles, and self-dependencies.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

usage() {
    ac_t "usage.write_task"
}

escape_yaml() {
    ac_escape_yaml_double_quoted "$1"
}

is_research_task_type() {
    local task_type="$1"
    [ "$task_type" = "investigation" ] || [ "$task_type" = "analyst" ]
}

has_active_research_for_command() {
    local target_command_id="$1"
    local task_file task_type command_id

    [ -z "$target_command_id" ] && return 1

    for task_file in "${TASK_PENDING_DIR}"/*.yaml "${TASK_INFLIGHT_DIR}"/*.yaml "${TASK_BLOCKED_DIR}"/*.yaml; do
        [ -f "$task_file" ] || continue
        task_type=$(ac_read_yaml_scalar "$task_file" "type")
        command_id=$(ac_read_yaml_scalar "$task_file" "command_id")
        if is_research_task_type "$task_type" && [ "$command_id" = "$target_command_id" ]; then
            return 0
        fi
    done

    return 1
}

has_done_research_for_command() {
    local target_command_id="$1"
    local task_file task_type command_id

    [ -z "$target_command_id" ] && return 1

    for task_file in "${TASK_DONE_DIR}"/*.yaml; do
        [ -f "$task_file" ] || continue
        task_type=$(ac_read_yaml_scalar "$task_file" "type")
        command_id=$(ac_read_yaml_scalar "$task_file" "command_id")
        if is_research_task_type "$task_type" && [ "$command_id" = "$target_command_id" ]; then
            return 0
        fi
    done

    return 1
}

task_id_has_timestamp_suffix() {
    local task_id="$1"
    [[ "$task_id" =~ _[0-9]{8}_[0-9]{6}$ ]]
}

TASK_ID=""
TASK_TYPE="implementation"
PERSONA=""
TITLE=""
DESCRIPTION=""
EXCLUSIVE_GROUP=""
ASSIGNED_TO=""
OUTPUT_PATH=""
RESULT_ARTIFACT_PATH=""
COMMAND_ID=""
CURRENT_COMMAND_ID=""

DEPENDS_ON=()
WRITE_FILES=()
READ_FILES=()

while [ $# -gt 0 ]; do
    case "$1" in
        --id)
            TASK_ID="${2:-}"
            shift 2
            ;;
        --type)
            TASK_TYPE="${2:-}"
            shift 2
            ;;
        --persona)
            PERSONA="${2:-}"
            shift 2
            ;;
        --title)
            TITLE="${2:-}"
            shift 2
            ;;
        --description)
            DESCRIPTION="${2:-}"
            shift 2
            ;;
        --depends-on)
            DEPENDS_ON+=("${2:-}")
            shift 2
            ;;
        --write-file)
            WRITE_FILES+=("${2:-}")
            shift 2
            ;;
        --read-file)
            READ_FILES+=("${2:-}")
            shift 2
            ;;
        --exclusive-group)
            EXCLUSIVE_GROUP="${2:-}"
            shift 2
            ;;
        --assigned-to)
            ASSIGNED_TO="${2:-}"
            shift 2
            ;;
        --command-id)
            COMMAND_ID="${2:-}"
            shift 2
            ;;
        --result-artifact-path)
            RESULT_ARTIFACT_PATH="${2:-}"
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

ac_ensure_dirs

CURRENT_COMMAND_ID="$COMMAND_ID"
if [ -z "$CURRENT_COMMAND_ID" ]; then
    CURRENT_COMMAND_ID="$(ac_read_yaml_scalar "${COMMANDS_DIR}/command.yaml" "id")"
fi

case "$TASK_TYPE" in
    implementation|investigation|analyst|rework|review) ;;
    *)
        ac_t_format "write_task.error.invalid_type" "task_type=${TASK_TYPE}" >&2
        exit 1
        ;;
esac

timestamp_suffix=$(date '+%Y%m%d_%H%M%S')
if [ -z "$TASK_ID" ]; then
    if [ "$TASK_TYPE" = "review" ]; then
        TASK_ID="task_${timestamp_suffix}_$RANDOM"
    else
        TASK_ID="task_${RANDOM}_${timestamp_suffix}"
    fi
elif [ "$TASK_TYPE" != "review" ]; then
    if ! task_id_has_timestamp_suffix "$TASK_ID"; then
        TASK_ID="${TASK_ID}_${RANDOM}_${timestamp_suffix}"
    fi
fi
ac_assert_task_id "$TASK_ID"

if [ -z "$PERSONA" ]; then
    ac_t "write_task.error.persona_required" >&2
    exit 1
fi
ac_assert_persona_exists "$PERSONA"

if [ -z "$TITLE" ]; then
    ac_t "write_task.error.title_required" >&2
    exit 1
fi

if [ -z "$DESCRIPTION" ]; then
    ac_t "write_task.error.description_required" >&2
    exit 1
fi

if [ "${#WRITE_FILES[@]}" -eq 0 ]; then
    if [ "$TASK_TYPE" != "investigation" ] && [ "$TASK_TYPE" != "analyst" ] && [ "$TASK_TYPE" != "rework" ]; then
        ac_t "write_task.error.write_files_required" >&2
        exit 1
    fi
fi

for wf in "${WRITE_FILES[@]}"; do
    if [ -z "$wf" ]; then
        ac_t "write_task.error.write_file_empty" >&2
        exit 1
    fi
done

if [ -z "$RESULT_ARTIFACT_PATH" ]; then
    if [ "$TASK_TYPE" = "investigation" ] || [ "$TASK_TYPE" = "analyst" ]; then
        RESULT_ARTIFACT_PATH="$(ac_default_research_result_path "$TASK_ID")"
    fi
fi

if [ -n "$ASSIGNED_TO" ]; then
    ac_validate_worker_id "$ASSIGNED_TO"
fi

if [ "$TASK_TYPE" = "implementation" ] && [ "$PERSONA" = "implementer" ] && [ -n "$CURRENT_COMMAND_ID" ]; then
    if has_active_research_for_command "$CURRENT_COMMAND_ID"; then
        ac_t "write_task.error.research_active" >&2
        exit 1
    fi
fi

if ac_find_task_file_by_id "$TASK_ID" >/dev/null 2>&1; then
    ac_t_format "write_task.error.task_exists" "task_id=${TASK_ID}" >&2
    exit 1
fi

# depends_on validation: forbid self-dependency and require existing targets.
existing_ids_tmp=$(mktemp)
trap 'rm -f "$existing_ids_tmp"' EXIT
ac_collect_task_ids > "$existing_ids_tmp"

for dep in "${DEPENDS_ON[@]}"; do
    [ -z "$dep" ] && continue
    if [ "$dep" = "$TASK_ID" ]; then
        ac_t_format "write_task.error.self_dependency" "task_id=${TASK_ID}" "dependency=${dep}" >&2
        exit 1
    fi

    if ! grep -Fxq "$dep" "$existing_ids_tmp"; then
        ac_t_format "write_task.error.dep_not_found" "dependency=${dep}" >&2
        exit 1
    fi
done

# depends_on validation: reject cycles via tsort.
edges_tmp=$(mktemp)
trap 'rm -f "$existing_ids_tmp" "$edges_tmp"' EXIT

while IFS= read -r task_file; do
    current_id=$(ac_read_yaml_scalar "$task_file" "id")
    [ -z "$current_id" ] && continue

    while IFS= read -r dep_id; do
        [ -z "$dep_id" ] && continue
        printf '%s %s\n' "$dep_id" "$current_id" >> "$edges_tmp"
    done < <(ac_read_yaml_list "$task_file" "depends_on")
done < <(ac_all_task_files)

for dep in "${DEPENDS_ON[@]}"; do
    [ -z "$dep" ] && continue
    printf '%s %s\n' "$dep" "$TASK_ID" >> "$edges_tmp"
done

if [ -s "$edges_tmp" ]; then
    if ! tsort "$edges_tmp" >/dev/null 2>&1; then
        ac_t "write_task.error.dep_cycle" >&2
        exit 1
    fi
fi

created_at=$(ac_now_iso)
updated_at="$created_at"

if [ -z "$OUTPUT_PATH" ]; then
    if [ "$TASK_TYPE" = "review" ]; then
        OUTPUT_PATH="${REVIEW_PENDING_DIR}/${TASK_ID}.yaml"
    else
        OUTPUT_PATH="${TASK_PENDING_DIR}/${TASK_ID}.yaml"
    fi
fi

tmp_file=$(mktemp)
trap 'rm -f "$existing_ids_tmp" "$edges_tmp" "$tmp_file"' EXIT

{
    echo "id: \"$(escape_yaml "$TASK_ID")\""
    echo "type: \"$(escape_yaml "$TASK_TYPE")\""
    echo "persona: \"$(escape_yaml "$PERSONA")\""
    echo "command_id: \"$(escape_yaml "$CURRENT_COMMAND_ID")\""
    echo "title: \"$(escape_yaml "$TITLE")\""
    echo "description: |"
    printf '%s\n' "$DESCRIPTION" | sed 's/^/  /'
    ac_write_yaml_list_block "depends_on" "${DEPENDS_ON[@]}"
    ac_write_yaml_list_block "write_files" "${WRITE_FILES[@]}"
    ac_write_yaml_list_block "read_files" "${READ_FILES[@]}"
    echo "result_artifact_path: \"$(escape_yaml "$RESULT_ARTIFACT_PATH")\""
    echo "rework_note_path: \"\""
    ac_write_yaml_list_block "rework_note_paths"
    echo "exclusive_group: \"$(escape_yaml "$EXCLUSIVE_GROUP")\""
    echo "status: \"pending\""
    echo "assigned_to: \"$(escape_yaml "$ASSIGNED_TO")\""
    echo "result: \"\""
    echo "blocked_reason: \"\""
    echo "created_at: \"$(escape_yaml "$created_at")\""
    echo "updated_at: \"$(escape_yaml "$updated_at")\""
} > "$tmp_file"

ac_atomic_write_from_tmp "$tmp_file" "$OUTPUT_PATH"
trap - EXIT
rm -f "$existing_ids_tmp" "$edges_tmp"

ac_t_format "write_task.success.written" "output_path=${OUTPUT_PATH}"
