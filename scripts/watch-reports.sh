#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

SWEEP_INTERVAL_SECONDS="${SWEEP_INTERVAL_SECONDS:-2}"
TMUX_SNAPSHOT_INTERVAL_SECONDS="${TMUX_SNAPSHOT_INTERVAL_SECONDS:-5}"
PRE_REVIEW_TEST_GATE_TASK_PREFIX="${PRE_REVIEW_TEST_GATE_TASK_PREFIX:-pre_review_test_gate_}"

QUESTION_NOTIFY_STATE_FILE="${STATUS_DIR}/question_notify_state.txt"
QUESTION_RESUME_STATE_FILE="${STATUS_DIR}/question_resume_state.txt"
COMMAND_NOTIFY_STATE_FILE="${STATUS_DIR}/command_dispatch_state.txt"
REPORT_NOTIFY_STATE_FILE="${STATUS_DIR}/report_notify_state.txt"
RESEARCH_NOTIFY_STATE_FILE="${STATUS_DIR}/research_complete_notify_state.txt"
REVIEW_CYCLE_STATE_FILE="${RUNTIME_DIR}/review_cycle_state.env"
TMUX_SNAPSHOT_LOOP_PID=""

set_contains_line() {
    local file="$1"
    local value="$2"
    grep -Fxq "$value" "$file" 2>/dev/null
}

set_add_line() {
    local file="$1"
    local value="$2"
    if ! set_contains_line "$file" "$value"; then
        echo "$value" >> "$file"
    fi
}

dispatch_cursor_file() {
    printf '%s/dispatch_cursor_%s.txt\n' "$RUNTIME_DIR" "$1"
}

read_review_cycle_state() {
    if [ -f "$REVIEW_CYCLE_STATE_FILE" ]; then
        # shellcheck disable=SC1090
        source "$REVIEW_CYCLE_STATE_FILE"
    fi

    REVIEW_CYCLE_ID="${REVIEW_CYCLE_ID:-0}"
    REVIEW_CYCLE_ACTIVE="${REVIEW_CYCLE_ACTIVE:-0}"
    REVIEW_TARGET_SIGNATURE="${REVIEW_TARGET_SIGNATURE:-}"
    REVIEW_LAST_APPROVED_SIGNATURE="${REVIEW_LAST_APPROVED_SIGNATURE:-}"
    REVIEW_CYCLE_STARTED_AT_EPOCH="${REVIEW_CYCLE_STARTED_AT_EPOCH:-0}"
}

save_review_cycle_state() {
    local tmp_file
    tmp_file=$(mktemp)
    {
        echo "REVIEW_CYCLE_ID=${REVIEW_CYCLE_ID}"
        echo "REVIEW_CYCLE_ACTIVE=${REVIEW_CYCLE_ACTIVE}"
        echo "REVIEW_TARGET_SIGNATURE=\"${REVIEW_TARGET_SIGNATURE}\""
        echo "REVIEW_LAST_APPROVED_SIGNATURE=\"${REVIEW_LAST_APPROVED_SIGNATURE}\""
        echo "REVIEW_CYCLE_STARTED_AT_EPOCH=${REVIEW_CYCLE_STARTED_AT_EPOCH}"
    } > "$tmp_file"
    ac_atomic_write_from_tmp "$tmp_file" "$REVIEW_CYCLE_STATE_FILE"
}

init_runtime() {
    local token

    ac_ensure_runtime_dirs
    ac_write_runtime_env
    touch \
        "$QUESTION_NOTIFY_STATE_FILE" \
        "$QUESTION_RESUME_STATE_FILE" \
        "$COMMAND_NOTIFY_STATE_FILE" \
        "$REPORT_NOTIFY_STATE_FILE" \
        "$RESEARCH_NOTIFY_STATE_FILE"

    token=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
    [ -n "$token" ] || token="token_${RANDOM}_$(date +%s)"

    echo "$$" > "$DISPATCHER_PID_FILE"
    echo "$token" > "$DISPATCHER_TOKEN_FILE"
    export DISPATCHER_PID="$$"
    export DISPATCHER_TOKEN="$token"

    read_review_cycle_state
    save_review_cycle_state

    if [ ! -s "$RESEARCH_NOTIFY_STATE_FILE" ]; then
        init_research_notify_state
    fi

    trap cleanup_runtime EXIT INT TERM
}

cleanup_runtime() {
    if [ -n "${TMUX_SNAPSHOT_LOOP_PID:-}" ]; then
        kill "$TMUX_SNAPSHOT_LOOP_PID" >/dev/null 2>&1 || true
        wait "$TMUX_SNAPSHOT_LOOP_PID" 2>/dev/null || true
    fi

    rm -f "$DISPATCHER_PID_FILE" "$DISPATCHER_TOKEN_FILE"
}

capture_tmux_snapshots_once() {
    local agent_id
    while IFS= read -r agent_id; do
        [ -n "$agent_id" ] || continue
        ac_capture_tmux_snapshot "$agent_id" "$(ac_agent_tmux_target "$agent_id")"
    done < <(ac_all_agent_ids)
}

run_tmux_snapshot_loop() {
    while true; do
        capture_tmux_snapshots_once || true
        sleep "$TMUX_SNAPSHOT_INTERVAL_SECONDS"
    done
}

is_worker_busy() {
    local worker_id="$1"
    local task_file
    for task_file in "${TASK_INFLIGHT_DIR}"/*.yaml "${REVIEW_INFLIGHT_DIR}"/*.yaml; do
        [ -f "$task_file" ] || continue
        if [ "$(ac_read_yaml_scalar "$task_file" "assigned_to")" = "$worker_id" ]; then
            return 0
        fi
    done
    return 1
}

is_research_task_type() {
    local task_type="$1"
    [ "$task_type" = "investigation" ] || [ "$task_type" = "analyst" ]
}

has_active_research_tasks_for_command() {
    local target_command_id="$1"
    local task_file task_type command_id

    [ -z "$target_command_id" ] && return 1

    for task_file in "$TASK_PENDING_DIR"/*.yaml "$TASK_INFLIGHT_DIR"/*.yaml "$TASK_BLOCKED_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        task_type=$(ac_read_yaml_scalar "$task_file" "type")
        command_id=$(ac_read_yaml_scalar "$task_file" "command_id")
        if is_research_task_type "$task_type" && [ "$command_id" = "$target_command_id" ]; then
            return 0
        fi
    done

    return 1
}

has_done_research_tasks_for_command() {
    local target_command_id="$1"
    local task_file task_type command_id

    [ -z "$target_command_id" ] && return 1

    for task_file in "$TASK_DONE_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        task_type=$(ac_read_yaml_scalar "$task_file" "type")
        command_id=$(ac_read_yaml_scalar "$task_file" "command_id")
        if is_research_task_type "$task_type" && [ "$command_id" = "$target_command_id" ]; then
            return 0
        fi
    done

    return 1
}

has_active_primary_tasks_for_command() {
    local target_command_id="$1"
    local task_file task_type command_id

    [ -z "$target_command_id" ] && return 1

    for task_file in "$TASK_PENDING_DIR"/*.yaml "$TASK_INFLIGHT_DIR"/*.yaml "$TASK_BLOCKED_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        task_type=$(ac_read_yaml_scalar "$task_file" "type")
        command_id=$(ac_read_yaml_scalar "$task_file" "command_id")
        if [ "$command_id" = "$target_command_id" ] && ! is_research_task_type "$task_type"; then
            return 0
        fi
    done

    return 1
}

has_active_reviews_for_command() {
    local target_command_id="$1"
    local review_file command_id

    [ -z "$target_command_id" ] && return 1

    for review_file in "$REVIEW_PENDING_DIR"/*.yaml "$REVIEW_INFLIGHT_DIR"/*.yaml; do
        [ -f "$review_file" ] || continue
        command_id=$(ac_read_yaml_scalar "$review_file" "command_id")
        if [ "$command_id" = "$target_command_id" ]; then
            return 0
        fi
    done

    return 1
}

init_research_notify_state() {
    local task_file task_type task_id

    for task_file in "${TASK_DONE_DIR}"/*.yaml; do
        [ -f "$task_file" ] || continue
        task_type=$(ac_read_yaml_scalar "$task_file" "type")
        [ "$task_type" != "investigation" ] && [ "$task_type" != "analyst" ] && continue
        task_id=$(ac_read_yaml_scalar "$task_file" "id")
        [ -z "$task_id" ] && task_id=$(basename "$task_file" .yaml)
        [ -z "$task_id" ] && continue
        set_add_line "$RESEARCH_NOTIFY_STATE_FILE" "$task_id"
    done

    set_add_line "$RESEARCH_NOTIFY_STATE_FILE" "__research_complete_notify_initialized__"
}

has_active_research_tasks() {
    local task_file task_type

    for task_file in "$TASK_PENDING_DIR"/*.yaml "$TASK_INFLIGHT_DIR"/*.yaml "$TASK_BLOCKED_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        task_type=$(ac_read_yaml_scalar "$task_file" "type")
        if is_research_task_type "$task_type"; then
            return 0
        fi
    done

    return 1
}

has_unnotified_research_results() {
    local task_file task_id task_type

    for task_file in "$TASK_DONE_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        task_type=$(ac_read_yaml_scalar "$task_file" "type")
        if ! is_research_task_type "$task_type"; then
            continue
        fi

        task_id=$(ac_read_yaml_scalar "$task_file" "id")
        [ -z "$task_id" ] && task_id=$(basename "$task_file" .yaml)
        [ -z "$task_id" ] && continue

        if ! set_contains_line "$RESEARCH_NOTIFY_STATE_FILE" "$task_id"; then
            return 0
        fi
    done

    return 1
}

has_unnotified_research_results_for_command() {
    local target_command_id="$1"
    local task_file task_id task_type command_id

    [ -z "$target_command_id" ] && return 1

    for task_file in "$TASK_DONE_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        task_type=$(ac_read_yaml_scalar "$task_file" "type")
        if ! is_research_task_type "$task_type"; then
            continue
        fi
        command_id=$(ac_read_yaml_scalar "$task_file" "command_id")
        [ "$command_id" = "$target_command_id" ] || continue

        task_id=$(ac_read_yaml_scalar "$task_file" "id")
        [ -z "$task_id" ] && task_id=$(basename "$task_file" .yaml)
        [ -z "$task_id" ] && continue

        if ! set_contains_line "$RESEARCH_NOTIFY_STATE_FILE" "$task_id"; then
            return 0
        fi
    done

    return 1
}

is_pre_review_test_gate_task_id() {
    local task_id="$1"
    [[ "$task_id" == "${PRE_REVIEW_TEST_GATE_TASK_PREFIX}"* ]]
}

is_primary_task_file() {
    local task_file="$1"
    local task_id task_type persona

    [ -f "$task_file" ] || return 1

    task_type=$(ac_read_yaml_scalar "$task_file" "type")
    persona=$(ac_read_yaml_scalar "$task_file" "persona")
    task_id=$(ac_read_yaml_scalar "$task_file" "id")

    if is_research_task_type "$task_type"; then
        return 1
    fi

    case "$task_type" in
        implementation|rework) ;;
        *)
            return 1
            ;;
    esac

    if [ "$persona" = "tester" ]; then
        return 1
    fi

    if is_pre_review_test_gate_task_id "$task_id"; then
        return 1
    fi

    return 0
}

has_active_implementation_tasks_for_command() {
    local target_command_id="$1"
    local task_file command_id

    [ -z "$target_command_id" ] && return 1

    for task_file in "$TASK_PENDING_DIR"/*.yaml "$TASK_INFLIGHT_DIR"/*.yaml "$TASK_BLOCKED_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        if ! is_primary_task_file "$task_file"; then
            continue
        fi
        command_id=$(ac_read_yaml_scalar "$task_file" "command_id")
        if [ "$command_id" = "$target_command_id" ]; then
            return 0
        fi
    done

    return 1
}

has_done_primary_tasks_for_command() {
    local target_command_id="$1"
    local task_file command_id

    [ -z "$target_command_id" ] && return 1

    for task_file in "$TASK_DONE_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        if ! is_primary_task_file "$task_file"; then
            continue
        fi
        command_id=$(ac_read_yaml_scalar "$task_file" "command_id")
        if [ "$command_id" = "$target_command_id" ]; then
            return 0
        fi
    done

    return 1
}

collect_done_primary_task_ids_for_command() {
    local target_command_id="$1"
    local task_file task_id command_id

    [ -z "$target_command_id" ] && return 0

    for task_file in $(find "$TASK_DONE_DIR" -maxdepth 1 -type f -name '*.yaml' | sort); do
        [ -f "$task_file" ] || continue
        if ! is_primary_task_file "$task_file"; then
            continue
        fi
        command_id=$(ac_read_yaml_scalar "$task_file" "command_id")
        [ "$command_id" = "$target_command_id" ] || continue
        task_id=$(ac_read_yaml_scalar "$task_file" "id")
        [ -n "$task_id" ] && printf '%s\n' "$task_id"
    done
}

collect_done_primary_write_files_for_command() {
    local target_command_id="$1"
    local task_file command_id write_file

    [ -z "$target_command_id" ] && return 0

    for task_file in $(find "$TASK_DONE_DIR" -maxdepth 1 -type f -name '*.yaml' | sort); do
        [ -f "$task_file" ] || continue
        if ! is_primary_task_file "$task_file"; then
            continue
        fi
        command_id=$(ac_read_yaml_scalar "$task_file" "command_id")
        [ "$command_id" = "$target_command_id" ] || continue
        while IFS= read -r write_file; do
            write_file=$(ac_trim "$write_file")
            [ -n "$write_file" ] || continue
            printf '%s\n' "$write_file"
        done < <(ac_read_yaml_list "$task_file" "write_files")
    done | awk '!seen[$0]++'
}

build_done_signature_for_command() {
    local target_command_id="$1"
    local task_file task_id completed_at command_id payload=""

    [ -z "$target_command_id" ] && return 0

    for task_file in $(find "$TASK_DONE_DIR" -maxdepth 1 -type f -name '*.yaml' | sort); do
        [ -f "$task_file" ] || continue
        if ! is_primary_task_file "$task_file"; then
            continue
        fi
        command_id=$(ac_read_yaml_scalar "$task_file" "command_id")
        [ "$command_id" = "$target_command_id" ] || continue
        task_id=$(ac_read_yaml_scalar "$task_file" "id")
        [ -n "$task_id" ] || continue
        completed_at=$(ac_read_yaml_scalar "$task_file" "completed_at")
        payload+="${task_id}:${completed_at};"
    done

    if [ -z "$payload" ]; then
        printf '\n'
        return 0
    fi

    printf '%s' "$payload" | sha1sum | awk '{print $1}'
}

pre_review_test_gate_task_id() {
    local done_signature="$1"
    printf '%s%s_19700101_000000\n' "$PRE_REVIEW_TEST_GATE_TASK_PREFIX" "$done_signature"
}

find_pre_review_test_gate_task_file() {
    local done_signature="$1"
    local task_id

    task_id=$(pre_review_test_gate_task_id "$done_signature")
    ac_find_task_file_by_id "$task_id"
}

notify_task_author_research_complete() {
    local task_file task_id task_type artifact_path summary_lines=""
    local -a pending_notify_ids=()

    if has_active_research_tasks; then
        return 0
    fi

    for task_file in "$TASK_DONE_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        task_type=$(ac_read_yaml_scalar "$task_file" "type")
        [ "$task_type" != "investigation" ] && [ "$task_type" != "analyst" ] && continue

        task_id=$(ac_read_yaml_scalar "$task_file" "id")
        [ -z "$task_id" ] && task_id=$(basename "$task_file" .yaml)
        [ -z "$task_id" ] && continue

        if set_contains_line "$RESEARCH_NOTIFY_STATE_FILE" "$task_id"; then
            continue
        fi

        artifact_path=$(ac_read_yaml_scalar "$task_file" "result_artifact_path")
        [ -z "$artifact_path" ] && artifact_path="$(ac_default_research_result_path "$task_id")"
        summary_lines+="- ${task_id} (${task_type}) -> ${artifact_path}"$'\n'
        pending_notify_ids+=("$task_id")
    done

    [ "${#pending_notify_ids[@]}" -gt 0 ] || return 0

    ac_send_direct_message task_author "${AC_RESET_COMMAND}
$(ac_render_report_research_summary_message "${summary_lines%$'\n'}")"

    for task_id in "${pending_notify_ids[@]}"; do
        set_add_line "$RESEARCH_NOTIFY_STATE_FILE" "$task_id"
    done
}

ensure_pre_review_test_gate_passed() {
    local target_command_id="$1"
    local done_signature="$2"
    local task_id task_file task_state task_result short_sig description dep_id write_file
    local -a depends_args=()
    local -a write_files=()
    local -a write_args=()

    [ -n "$target_command_id" ] || return 1
    [ -n "$done_signature" ] || return 1

    task_id=$(pre_review_test_gate_task_id "$done_signature")
    if task_file=$(find_pre_review_test_gate_task_file "$done_signature" 2>/dev/null); then
        task_state=$(ac_task_state_from_path "$task_file")
        task_result=$(ac_read_yaml_scalar "$task_file" "result")
        if [ "$task_state" = "done" ] && [ "$task_result" = "success" ]; then
            return 0
        fi
        return 1
    fi

    mapfile -t write_files < <(collect_done_primary_write_files_for_command "$target_command_id")
    [ "${#write_files[@]}" -gt 0 ] || return 1
    for write_file in "${write_files[@]}"; do
        write_args+=(--write-file "$write_file")
    done

    while IFS= read -r dep_id; do
        [ -n "$dep_id" ] || continue
        depends_args+=(--depends-on "$dep_id")
    done < <(collect_done_primary_task_ids_for_command "$target_command_id")

    short_sig="${done_signature:0:8}"
    description="全体レビュー前のテストゲートです。現在の実装差分に対してテストを実行し、失敗が今回変更に起因する場合は修正して再実行してください。"$'\n\n'
    description+="完了条件:"$'\n'
    description+="- 必要なテストを実行し、結果を summary / details に残すこと"$'\n'
    description+="- 今回変更に起因する失敗があれば修正まで完了させること"$'\n'
    description+="- 不明点があれば推測せず create-question.sh を使うこと"

    "${SCRIPT_DIR}/write-task.sh" \
        --id "$task_id" \
        --type implementation \
        --command-id "$target_command_id" \
        --persona tester \
        --title "プレレビュー テストゲート (${short_sig})" \
        --description "$description" \
        "${depends_args[@]}" \
        "${write_args[@]}" >/dev/null

    ac_log "🧪 pre-review test gate created: ${task_id}"
    return 1
}

requeue_blocked_pre_review_test_gate_tasks() {
    local task_file task_id blocked_reason now_iso destination

    for task_file in "$TASK_BLOCKED_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        task_id=$(ac_read_yaml_scalar "$task_file" "id")
        if ! is_pre_review_test_gate_task_id "$task_id"; then
            continue
        fi

        blocked_reason=$(ac_read_yaml_scalar "$task_file" "blocked_reason")
        if [[ "$blocked_reason" == question:* ]]; then
            continue
        fi

        now_iso=$(ac_now_iso)
        ac_set_yaml_scalar "$task_file" "status" "pending"
        ac_set_yaml_scalar "$task_file" "result" ""
        ac_set_yaml_scalar "$task_file" "blocked_reason" ""
        ac_set_yaml_scalar "$task_file" "assigned_to" ""
        ac_set_yaml_scalar "$task_file" "updated_at" "$now_iso"

        destination="${TASK_PENDING_DIR}/$(basename "$task_file")"
        mv "$task_file" "$destination"
        ac_log "♻️ pre-review test gate requeued: ${task_id}"
    done
}

mark_command_done_after_review_approve() {
    local command_id="$1"
    local cycle_id="$2"
    local command_file current_command_id current_status now_iso

    [ -n "$command_id" ] || return 0

    command_file="${COMMANDS_DIR}/command.yaml"
    [ -f "$command_file" ] || return 0

    current_command_id=$(ac_read_yaml_scalar "$command_file" "id")
    [ -n "$current_command_id" ] || return 0
    [ "$current_command_id" = "$command_id" ] || return 0

    current_status=$(ac_read_yaml_scalar "$command_file" "status")
    [ "$current_status" = "inflight" ] || return 0

    now_iso=$(ac_now_iso)
    ac_set_yaml_scalar "$command_file" "status" "done"
    ac_set_yaml_scalar "$command_file" "updated_at" "$now_iso"
    ac_log "✅ command marked done after review approval: ${command_id} (cycle=${cycle_id})"
}

create_aggregated_rework_task() {
    local cycle_id="$1"
    local command_id="$2"
    local note_path="$3"
    shift 3 || true
    local -a depends_args=("$@")
    local task_id task_file description

    [ -n "$command_id" ] || command_id="$(ac_read_yaml_scalar "${COMMANDS_DIR}/command.yaml" "id")"
    [ -n "$command_id" ] || return 1

    task_id="review_cycle${cycle_id}_rework_$(date '+%Y%m%d_%H%M%S')"
    description="全体レビュー cycle ${cycle_id} で requestchange が出ました。"$'\n'
    if [ -n "$note_path" ]; then
        description+="rework_note_path を確認して全指摘を反映してください。"$'\n'
    fi
    description+="完了後は dispatcher が再度 tester と overall review を回します。"

    "${SCRIPT_DIR}/write-task.sh" \
        --id "$task_id" \
        --type rework \
        --command-id "$command_id" \
        --persona implementer \
        --title "レビュー指摘対応 (cycle ${cycle_id})" \
        --description "$description" \
        "${depends_args[@]}" >/dev/null

    task_file=$(ac_find_task_file_by_id "$task_id")
    if [ -n "$note_path" ]; then
        ac_set_yaml_scalar "$task_file" "rework_note_path" "$note_path"
    fi

    ac_log "🧩 aggregated rework task created: ${task_id}"
}

generate_review_tasks_if_needed() {
    local command_id command_status done_signature cycle_id short_sig parent_id description dep_id now_epoch parent_file write_file
    local -a depends_args=()
    local -a write_files=()
    local -a write_args=()

    command_id=$(ac_read_yaml_scalar "${COMMANDS_DIR}/command.yaml" "id")
    [ -n "$command_id" ] || return 0

    command_status=$(ac_read_yaml_scalar "${COMMANDS_DIR}/command.yaml" "status")
    [ "$command_status" = "inflight" ] || return 0

    read_review_cycle_state
    if [ "$REVIEW_CYCLE_ACTIVE" -eq 1 ]; then
        return 0
    fi

    if has_active_research_tasks_for_command "$command_id"; then
        return 0
    fi

    if has_unnotified_research_results_for_command "$command_id"; then
        return 0
    fi

    if has_active_implementation_tasks_for_command "$command_id"; then
        return 0
    fi

    if ! has_done_primary_tasks_for_command "$command_id"; then
        return 0
    fi

    done_signature=$(build_done_signature_for_command "$command_id")
    [ -n "$done_signature" ] || return 0

    if [ "$done_signature" = "$REVIEW_LAST_APPROVED_SIGNATURE" ]; then
        return 0
    fi

    if has_active_reviews_for_command "$command_id"; then
        return 0
    fi

    if ! ensure_pre_review_test_gate_passed "$command_id" "$done_signature"; then
        return 0
    fi

    mapfile -t write_files < <(collect_done_primary_write_files_for_command "$command_id")
    [ "${#write_files[@]}" -gt 0 ] || return 0
    for write_file in "${write_files[@]}"; do
        write_args+=(--write-file "$write_file")
    done

    while IFS= read -r dep_id; do
        [ -n "$dep_id" ] || continue
        depends_args+=(--depends-on "$dep_id")
    done < <(collect_done_primary_task_ids_for_command "$command_id")

    cycle_id=$((REVIEW_CYCLE_ID + 1))
    short_sig="${done_signature:0:8}"
    parent_id="review_cycle${cycle_id}"
    description="全体差分をレビューし、approve か requestchange を判定してください。"$'\n'
    description+="requestchange の場合は summary / details / rework_targets / findings を正しく記載してください。"$'\n'
    description+="requestchange は dispatcher が集約して再作業を再配布します。"

    parent_file="${REVIEW_PENDING_DIR}/${parent_id}.yaml"
    "${SCRIPT_DIR}/write-task.sh" \
        --id "$parent_id" \
        --type review \
        --command-id "$command_id" \
        --persona reviewer \
        --title "全体レビュー cycle ${cycle_id} (${short_sig})" \
        --description "$description" \
        "${depends_args[@]}" \
        "${write_args[@]}" >/dev/null

    now_epoch=$(ac_now_epoch)
    REVIEW_CYCLE_ID="$cycle_id"
    REVIEW_CYCLE_ACTIVE=1
    REVIEW_TARGET_SIGNATURE="$done_signature"
    REVIEW_CYCLE_STARTED_AT_EPOCH="$now_epoch"
    save_review_cycle_state

    if [ -f "$parent_file" ]; then
        ac_set_yaml_scalar "$parent_file" "review_cycle_id" "$cycle_id"
    fi

    ac_log "✅ review cycle created: cycle=${cycle_id}"
}

worker_state_for_agent() {
    local worker_id="$1"
    local task_file assigned_to

    for task_file in "${TASK_INFLIGHT_DIR}"/*.yaml "${REVIEW_INFLIGHT_DIR}"/*.yaml; do
        [ -f "$task_file" ] || continue
        assigned_to=$(ac_read_yaml_scalar "$task_file" "assigned_to")
        if [ "$assigned_to" = "$worker_id" ]; then
            printf 'inflight\n'
            return 0
        fi
    done

    for task_file in "${TASK_PENDING_DIR}"/*.yaml "${REVIEW_PENDING_DIR}"/*.yaml; do
        [ -f "$task_file" ] || continue
        assigned_to=$(ac_read_yaml_scalar "$task_file" "assigned_to")
        if [ "$assigned_to" = "$worker_id" ]; then
            printf 'pending\n'
            return 0
        fi
    done

    for task_file in "${TASK_BLOCKED_DIR}"/*.yaml; do
        [ -f "$task_file" ] || continue
        assigned_to=$(ac_read_yaml_scalar "$task_file" "assigned_to")
        if [ "$assigned_to" = "$worker_id" ]; then
            printf 'blocked\n'
            return 0
        fi
    done

    printf 'idle\n'
}

pick_free_worker_from_candidates() {
    local pool_key="$1"
    shift || true
    local candidates=("$@")
    local count="${#candidates[@]}"
    local cursor_file cursor_value idx offset candidate

    [ "$count" -gt 0 ] || return 1

    cursor_file="$(dispatch_cursor_file "$pool_key")"
    cursor_value="-1"
    if [ -f "$cursor_file" ]; then
        cursor_value="$(cat "$cursor_file" 2>/dev/null || true)"
    fi
    [[ "$cursor_value" =~ ^-?[0-9]+$ ]] || cursor_value="-1"

    offset=1
    while [ "$offset" -le "$count" ]; do
        idx=$(((cursor_value + offset + count) % count))
        candidate="${candidates[$idx]}"
        if ! is_worker_busy "$candidate"; then
            printf '%s\n' "$idx" > "$cursor_file"
            printf '%s\n' "$candidate"
            return 0
        fi
        offset=$((offset + 1))
    done

    return 1
}

pick_free_worker_for_task() {
    local task_file="$1"
    local persona
    local candidates=()

    persona="$(ac_read_yaml_scalar "$task_file" "persona")"
    [ -n "$persona" ] || return 1

    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        candidates+=("$candidate")
    done < <(ac_agents_for_persona "$persona")

    [ "${#candidates[@]}" -gt 0 ] || return 1
    pick_free_worker_from_candidates "$persona" "${candidates[@]}"
}

dependencies_satisfied() {
    local task_file="$1"
    local dep_id
    while IFS= read -r dep_id; do
        [ -n "$dep_id" ] || continue
        ac_task_is_done "$dep_id" || return 1
    done < <(ac_read_yaml_list "$task_file" "depends_on")
    return 0
}

notify_worker_for_task() {
    local task_file="$1"
    local task_id persona worker_id message

    task_id=$(ac_read_yaml_scalar "$task_file" "id")
    persona=$(ac_read_yaml_scalar "$task_file" "persona")
    worker_id=$(ac_read_yaml_scalar "$task_file" "assigned_to")
    [ -n "$worker_id" ] || return 1

    message="${AC_RESET_COMMAND}"$'\n'"$(ac_render_worker_notify_message "$persona" "$task_id" "$task_file")"
    ac_send_direct_message "$worker_id" "$message"
}

find_latest_report_event_for_task() {
    local task_id="$1"
    local report_file report_task_id

    while IFS= read -r report_file; do
        [ -f "$report_file" ] || continue
        report_task_id="$(ac_read_yaml_scalar "$report_file" "task_id")"
        if [ "$report_task_id" = "$task_id" ]; then
            printf '%s\n' "$report_file"
            return 0
        fi
    done < <(find "$REPORT_EVENTS_DIR" -maxdepth 1 -type f -name '*.yaml' | sort -r)

    return 1
}

create_review_group_note() {
    local parent_id="$1"
    local content="$2"
    local note_path
    note_path="${REWORK_DIR}/${parent_id}_review.md"
    {
        printf '# Review Group %s\n' "$parent_id"
        echo
        printf '%s\n' "$content"
    } > "$note_path"
    printf '%s\n' "$note_path"
}

expand_pending_review_groups() {
    local parent_file parent_id now_iso destination child_id child_path reviewer_id cycle_id count
    local target_file existing_file
    local child_read_files=()
    local parent_read_files=()
    local parent_write_files=()

    while IFS= read -r parent_file; do
        [ -f "$parent_file" ] || continue
        [ "$(ac_read_yaml_scalar "$parent_file" "persona")" = "reviewer" ] || continue
        [ -z "$(ac_read_yaml_scalar "$parent_file" "review_parent_id")" ] || continue
        [ "$(ac_read_yaml_scalar "$parent_file" "status")" = "pending" ] || continue
        dependencies_satisfied "$parent_file" || continue

        mapfile -t reviewer_ids < <(ac_section_agent_ids reviewer)
        [ "${#reviewer_ids[@]}" -gt 0 ] || continue

        parent_id="$(ac_read_yaml_scalar "$parent_file" "id")"
        cycle_id="$(ac_read_yaml_scalar "$parent_file" "review_cycle_id")"
        if ! [[ "$cycle_id" =~ ^[0-9]+$ ]] || [ "$cycle_id" -le 0 ]; then
            read_review_cycle_state
            cycle_id=$((REVIEW_CYCLE_ID + 1))
            REVIEW_CYCLE_ID="$cycle_id"
            REVIEW_CYCLE_ACTIVE=1
            REVIEW_TARGET_SIGNATURE="$parent_id"
            REVIEW_CYCLE_STARTED_AT_EPOCH="$(ac_now_epoch)"
            save_review_cycle_state
        fi

        now_iso="$(ac_now_iso)"
        count="${#reviewer_ids[@]}"
        mapfile -t parent_write_files < <(ac_read_yaml_list "$parent_file" "write_files")
        mapfile -t parent_read_files < <(ac_read_yaml_list "$parent_file" "read_files")
        for reviewer_id in "${reviewer_ids[@]}"; do
            child_id="${parent_id}__${reviewer_id}"
            child_path="${REVIEW_PENDING_DIR}/${child_id}.yaml"
            cp "$parent_file" "$child_path"
            child_read_files=()
            for existing_file in "${parent_read_files[@]}"; do
                existing_file="$(ac_trim "$existing_file")"
                [ -n "$existing_file" ] || continue
                child_read_files+=("$existing_file")
            done
            for target_file in "${parent_write_files[@]}"; do
                target_file="$(ac_trim "$target_file")"
                [ -n "$target_file" ] || continue
                if printf '%s\n' "${child_read_files[@]}" | grep -Fxq "$target_file"; then
                    continue
                fi
                child_read_files+=("$target_file")
            done
            ac_replace_yaml_list_block "$child_path" "write_files"
            ac_replace_yaml_list_block "$child_path" "read_files" "${child_read_files[@]}"
            ac_set_yaml_scalar "$child_path" "exclusive_group" ""
            ac_set_yaml_scalar "$child_path" "id" "$child_id"
            ac_set_yaml_scalar "$child_path" "assigned_to" "$reviewer_id"
            ac_set_yaml_scalar "$child_path" "status" "pending"
            ac_set_yaml_scalar "$child_path" "updated_at" "$now_iso"
            ac_set_yaml_scalar "$child_path" "review_parent_id" "$parent_id"
            ac_set_yaml_scalar "$child_path" "review_cycle_id" "$cycle_id"
        done

        ac_set_yaml_scalar "$parent_file" "assigned_to" "reviewers"
        ac_set_yaml_scalar "$parent_file" "status" "inflight"
        ac_set_yaml_scalar "$parent_file" "updated_at" "$now_iso"
        ac_set_yaml_scalar "$parent_file" "review_cycle_id" "$cycle_id"
        ac_set_yaml_scalar "$parent_file" "reviewer_target_count" "$count"
        destination="${REVIEW_INFLIGHT_DIR}/$(basename "$parent_file")"
        mv "$parent_file" "$destination"

        ac_log "✅ review fan-out: ${parent_id} -> ${count} reviewers"
    done < <(find "$REVIEW_PENDING_DIR" -maxdepth 1 -type f -name '*.yaml' | sort)
}

finalize_review_groups() {
    local parent_file parent_id cycle_id now_iso command_id note_path
    local reviewer_id child_id child_file child_state report_file review_decision result summary details findings_text target reviewer reviewer_count
    local all_ready any_requestchange aggregate_body
    local findings_items=()
    local rework_targets=()
    local -a review_depends=()
    local -a target_depends=()
    local -A seen_targets=()

    while IFS= read -r parent_file; do
        [ -f "$parent_file" ] || continue
        [ "$(ac_read_yaml_scalar "$parent_file" "persona")" = "reviewer" ] || continue
        [ "$(ac_read_yaml_scalar "$parent_file" "assigned_to")" = "reviewers" ] || continue
        parent_id="$(ac_read_yaml_scalar "$parent_file" "id")"
        [ -n "$parent_id" ] || continue

        mapfile -t reviewer_ids < <(ac_section_agent_ids reviewer)
        [ "${#reviewer_ids[@]}" -gt 0 ] || continue

        all_ready=1
        any_requestchange=0
        aggregate_body=""
        command_id="$(ac_read_yaml_scalar "$parent_file" "command_id")"
        review_depends=()
        target_depends=()
        seen_targets=()

        for reviewer_id in "${reviewer_ids[@]}"; do
            child_id="${parent_id}__${reviewer_id}"
            child_file="$(ac_find_task_file_by_id "$child_id" 2>/dev/null || true)"
            if [ -z "$child_file" ]; then
                all_ready=0
                break
            fi
            child_state="$(ac_task_state_from_path "$child_file")"
            if [ "$child_state" != "done" ]; then
                all_ready=0
                break
            fi

            report_file="$(find_latest_report_event_for_task "$child_id" 2>/dev/null || true)"
            if [ -z "$report_file" ]; then
                all_ready=0
                break
            fi

            review_decision="$(ac_read_yaml_scalar "$report_file" "review_decision")"
            result="$(ac_read_yaml_scalar "$report_file" "result")"
            [ -n "$command_id" ] || command_id="$(ac_read_yaml_scalar "$report_file" "command_id")"
            review_depends+=(--depends-on "$child_id")

            if [ "$review_decision" = "requestchange" ]; then
                any_requestchange=1
            fi

            reviewer="$reviewer_id"
            summary="$(ac_read_yaml_block "$report_file" "summary")"
            details="$(ac_read_yaml_block "$report_file" "details")"
            findings_items=()
            mapfile -t findings_items < <(ac_read_yaml_list "$report_file" "findings")
            rework_targets=()
            mapfile -t rework_targets < <(ac_read_yaml_list "$report_file" "rework_targets")

            findings_text=""
            for target in "${findings_items[@]}"; do
                target="$(ac_trim "$target")"
                [ -n "$target" ] || continue
                findings_text+="- ${target}"$'\n'
            done
            findings_text="${findings_text%$'\n'}"

            aggregate_body+="## ${reviewer}"$'\n'
            aggregate_body+="task_id: ${child_id}"$'\n'
            aggregate_body+="result: ${result}"$'\n'
            aggregate_body+="review_decision: ${review_decision}"$'\n'
            if [ "${#rework_targets[@]}" -gt 0 ]; then
                aggregate_body+="rework_targets: $(IFS=', '; printf '%s' "${rework_targets[*]}")"$'\n'
                for target in "${rework_targets[@]}"; do
                    target="$(ac_trim "$target")"
                    [ -n "$target" ] || continue
                    if [ -z "${seen_targets[$target]+x}" ] && ac_find_task_file_by_id "$target" >/dev/null 2>&1; then
                        target_depends+=(--depends-on "$target")
                        seen_targets["$target"]=1
                    fi
                done
            fi
            aggregate_body+="summary:"$'\n'"${summary:-"(empty)"}"$'\n'
            aggregate_body+="details:"$'\n'"${details:-"(empty)"}"$'\n'
            if [ -n "$findings_text" ]; then
                aggregate_body+="findings:"$'\n'"${findings_text}"$'\n'
            fi
            aggregate_body+=$'\n'
        done

        [ "$all_ready" -eq 1 ] || continue

        now_iso="$(ac_now_iso)"
        cycle_id="$(ac_read_yaml_scalar "$parent_file" "review_cycle_id")"
        reviewer_count="${#reviewer_ids[@]}"
        note_path=""

        if [ "$any_requestchange" -eq 1 ]; then
            note_path="$(create_review_group_note "$parent_id" "$aggregate_body")"
            if ! create_aggregated_rework_task "$cycle_id" "$command_id" "$note_path" "${review_depends[@]}" "${target_depends[@]}"; then
                ac_log "❌ aggregated rework task creation failed: cycle=${cycle_id}"
                continue
            fi
            ac_set_yaml_scalar "$parent_file" "rework_note_path" "$note_path"
            ac_set_yaml_scalar "$parent_file" "result" "failure"
            ac_set_yaml_scalar "$parent_file" "review_decision" "requestchange"
        else
            ac_set_yaml_scalar "$parent_file" "result" "success"
            ac_set_yaml_scalar "$parent_file" "review_decision" "approve"
        fi

        ac_set_yaml_scalar "$parent_file" "status" "done"
        ac_set_yaml_scalar "$parent_file" "updated_at" "$now_iso"
        ac_set_yaml_scalar "$parent_file" "completed_at" "$now_iso"
        mv "$parent_file" "${REVIEW_DONE_DIR}/$(basename "$parent_file")"

        read_review_cycle_state
        REVIEW_CYCLE_ACTIVE=0
        if [ "$any_requestchange" -eq 0 ]; then
            REVIEW_LAST_APPROVED_SIGNATURE="$REVIEW_TARGET_SIGNATURE"
            mark_command_done_after_review_approve "$command_id" "$cycle_id"
        fi
        REVIEW_TARGET_SIGNATURE=""
        REVIEW_CYCLE_STARTED_AT_EPOCH=0
        save_review_cycle_state

        ac_log "✅ review group finalized: ${parent_id}"
    done < <(find "$REVIEW_INFLIGHT_DIR" -maxdepth 1 -type f -name '*.yaml' | sort)
}

dispatch_directory() {
    local pending_dir="$1"
    local inflight_dir="$2"
    local task_file assigned_to worker_id now_iso destination task_id was_preassigned
    local pending_files=()

    while IFS= read -r task_file; do
        pending_files+=("$task_file")
    done < <(find "$pending_dir" -maxdepth 1 -type f -name '*.yaml' | sort)

    for task_file in "${pending_files[@]}"; do
        [ -f "$task_file" ] || continue
        dependencies_satisfied "$task_file" || continue

        assigned_to=$(ac_read_yaml_scalar "$task_file" "assigned_to")
        was_preassigned=0
        if [ -n "$assigned_to" ]; then
            ac_validate_worker_id "$assigned_to"
            is_worker_busy "$assigned_to" && continue
            worker_id="$assigned_to"
            was_preassigned=1
        else
            worker_id="$(pick_free_worker_for_task "$task_file")" || continue
        fi

        if ! ac_acquire_task_locks "$task_file"; then
            continue
        fi

        now_iso=$(ac_now_iso)
        ac_set_yaml_scalar "$task_file" "assigned_to" "$worker_id"
        ac_set_yaml_scalar "$task_file" "status" "inflight"
        ac_set_yaml_scalar "$task_file" "updated_at" "$now_iso"
        destination="${inflight_dir}/$(basename "$task_file")"
        mv "$task_file" "$destination"

        if notify_worker_for_task "$destination"; then
            task_id=$(ac_read_yaml_scalar "$destination" "id")
            ac_log "✅ task dispatched: ${task_id} -> ${worker_id}"
        else
            ac_release_task_locks "$destination"
            if [ "$was_preassigned" -eq 0 ]; then
                ac_set_yaml_scalar "$destination" "assigned_to" ""
            fi
            ac_set_yaml_scalar "$destination" "status" "pending"
            ac_set_yaml_scalar "$destination" "updated_at" "$now_iso"
            mv "$destination" "$task_file"
        fi
    done
}

process_send_outbox() {
    local event_file channel target title message sent_path

    for event_file in "${EVENT_OUTBOX_DIR}"/*.yaml; do
        [ -f "$event_file" ] || continue
        channel=$(ac_read_yaml_scalar "$event_file" "channel")
        target=$(ac_read_yaml_scalar "$event_file" "target")
        title=$(ac_read_yaml_scalar "$event_file" "title")
        message=$(ac_read_yaml_block "$event_file" "message")
        [ -n "$message" ] || message="(empty)"

        case "$channel" in
            agent|'')
                if ! "${SCRIPT_DIR}/send-msg.sh" "$target" "$message" >/dev/null 2>&1; then
                    continue
                fi
                ;;
            *)
                continue
                ;;
        esac

        sent_path="${EVENT_SENT_DIR}/$(basename "$event_file")"
        mv "$event_file" "$sent_path"
        ac_log "✅ outbox processed: ${title:-message} -> ${target}"
    done
}

process_command_queue() {
    local command_file command_id command_status command_text key command_hash command_updated_at dispatch_updated_at

    command_file="${COMMANDS_DIR}/command.yaml"
    [ -f "$command_file" ] || return 0
    command_status=$(ac_read_yaml_scalar "$command_file" "status")
    [ "$command_status" = "pending" ] || return 0

    command_id=$(ac_read_yaml_scalar "$command_file" "id")
    [ -n "$command_id" ] || command_id="command_unknown"

    command_updated_at=$(ac_read_yaml_scalar "$command_file" "updated_at")
    command_text=$(ac_read_yaml_block "$command_file" "command")
    [ -n "$command_text" ] || command_text="command.yaml を確認してください。"
    command_hash=$(printf '%s' "$command_text" | sha1sum | awk '{print $1}')
    key="${command_id}|${command_updated_at}|${command_hash}"
    set_contains_line "$COMMAND_NOTIFY_STATE_FILE" "$key" && return 0

    ac_send_direct_message task_author "${AC_RESET_COMMAND}
$(ac_render_command_notify_message "$command_file" "$command_text")"

    dispatch_updated_at=$(ac_now_iso)
    ac_set_yaml_scalar "$command_file" "status" "inflight"
    ac_set_yaml_scalar "$command_file" "updated_at" "$dispatch_updated_at"

    set_add_line "$COMMAND_NOTIFY_STATE_FILE" "$key"
    set_add_line "$COMMAND_NOTIFY_STATE_FILE" "${command_id}|${dispatch_updated_at}|${command_hash}"
}

append_answer_to_task_context() {
    local task_file="$1"
    local question_file="$2"
    local question_id question answer current_context entry

    question_id=$(ac_read_yaml_scalar "$question_file" "id")
    question=$(ac_read_yaml_block "$question_file" "question")
    answer=$(ac_read_yaml_block "$question_file" "answer")
    current_context=$(ac_read_yaml_block "$task_file" "question_context")

    entry="[${question_id}]"$'\n'"question:"$'\n'"${question}"$'\n'"answer:"$'\n'"${answer}"
    if [ -n "$current_context" ]; then
        current_context="${current_context}"$'\n\n'"${entry}"
    else
        current_context="${entry}"
    fi

    ac_replace_yaml_multiline_block "$task_file" "question_context" "$current_context"
}

resume_tasks_from_answered_questions() {
    local question_file question_id task_file blocked_reason now_iso destination

    for question_file in "${QUESTION_ANSWERED_DIR}"/*.yaml; do
        [ -f "$question_file" ] || continue
        question_id=$(ac_read_yaml_scalar "$question_file" "id")
        [ -n "$question_id" ] || question_id="$(basename "$question_file" .yaml)"
        set_contains_line "$QUESTION_RESUME_STATE_FILE" "$question_id" && continue

        for task_file in "${TASK_BLOCKED_DIR}"/*.yaml; do
            [ -f "$task_file" ] || continue
            blocked_reason=$(ac_read_yaml_scalar "$task_file" "blocked_reason")
            [ "$blocked_reason" = "question:${question_id}" ] || continue

            append_answer_to_task_context "$task_file" "$question_file"
            now_iso=$(ac_now_iso)
            ac_set_yaml_scalar "$task_file" "status" "pending"
            ac_set_yaml_scalar "$task_file" "blocked_reason" ""
            ac_set_yaml_scalar "$task_file" "updated_at" "$now_iso"
            destination="${TASK_PENDING_DIR}/$(basename "$task_file")"
            mv "$task_file" "$destination"
            ac_log "✅ task resumed from answer: $(ac_read_yaml_scalar "$destination" "id")"
        done

        set_add_line "$QUESTION_RESUME_STATE_FILE" "$question_id"
    done
}

process_open_questions_notify() {
    local question_file question_id task_id asked_by question

    for question_file in "${QUESTION_OPEN_DIR}"/*.yaml; do
        [ -f "$question_file" ] || continue
        question_id=$(ac_read_yaml_scalar "$question_file" "id")
        [ -n "$question_id" ] || question_id="$(basename "$question_file" .yaml)"
        set_contains_line "$QUESTION_NOTIFY_STATE_FILE" "$question_id" && continue

        task_id=$(ac_read_yaml_scalar "$question_file" "task_id")
        asked_by=$(ac_read_yaml_scalar "$question_file" "asked_by")
        question=$(ac_read_yaml_block "$question_file" "question")

        ac_send_direct_message coordinator "$(ac_render_open_question_notify_message "$question_id" "$task_id" "$asked_by" "$question_file" "$question")"
        set_add_line "$QUESTION_NOTIFY_STATE_FILE" "$question_id"
    done
}

process_report_notifications() {
    local report_file key persona task_type task_id result command_id artifact review_decision review_parent_id

    for report_file in "${REPORT_EVENTS_DIR}"/*.yaml; do
        [ -f "$report_file" ] || continue
        key="$(basename "$report_file")"
        set_contains_line "$REPORT_NOTIFY_STATE_FILE" "$key" && continue

        persona=$(ac_read_yaml_scalar "$report_file" "persona")
        task_type=$(ac_read_yaml_scalar "$report_file" "type")
        task_id=$(ac_read_yaml_scalar "$report_file" "task_id")
        result=$(ac_read_yaml_scalar "$report_file" "result")
        command_id=$(ac_read_yaml_scalar "$report_file" "command_id")
        artifact=$(ac_read_yaml_scalar "$report_file" "result_artifact_path")
        review_decision=$(ac_read_yaml_scalar "$report_file" "review_decision")
        review_parent_id=$(ac_read_yaml_scalar "$report_file" "review_parent_id")

        set_add_line "$REPORT_NOTIFY_STATE_FILE" "$key"
    done
}

refresh_current_status() {
    local worker_id worker_state started_at command_status current_command_id
    local coordinator_status task_author_status open_question_count
    started_at="$(ac_read_yaml_scalar "${STATUS_DIR}/current.yaml" "started_at")"
    [ -n "$started_at" ] || started_at="$(date -Iseconds)"

    open_question_count=$(find "$QUESTION_OPEN_DIR" -maxdepth 1 -type f -name '*.yaml' 2>/dev/null | wc -l)
    command_status=$(ac_read_yaml_scalar "${COMMANDS_DIR}/command.yaml" "status")
    current_command_id=$(ac_read_yaml_scalar "${COMMANDS_DIR}/command.yaml" "id")

    coordinator_status="idle"
    if [ "$open_question_count" -gt 0 ]; then
        coordinator_status="attention"
    fi

    task_author_status="idle"
    if [ "$command_status" = "pending" ] || [ "$command_status" = "inflight" ]; then
        if [ -n "$current_command_id" ] && has_unnotified_research_results_for_command "$current_command_id"; then
            task_author_status="task_breakdown"
        elif [ -n "$current_command_id" ] \
            && has_done_research_tasks_for_command "$current_command_id" \
            && ! has_active_research_tasks_for_command "$current_command_id" \
            && ! has_active_primary_tasks_for_command "$current_command_id" \
            && ! has_active_reviews_for_command "$current_command_id"; then
            task_author_status="task_breakdown"
        elif [ -n "$current_command_id" ] \
            && ! has_done_research_tasks_for_command "$current_command_id" \
            && ! has_active_research_tasks_for_command "$current_command_id" \
            && ! has_active_primary_tasks_for_command "$current_command_id"; then
            task_author_status="research_dispatching"
        else
            task_author_status="attention"
        fi
    elif has_unnotified_research_results; then
        task_author_status="task_breakdown"
    fi

    {
        echo "session: \"${AC_TMUX_SESSION_NAME}\""
        echo "started_at: \"${started_at}\""
        echo "coordinator: \"${coordinator_status}\""
        echo "task_author: \"${task_author_status}\""
        echo "dispatcher: \"running\""
        echo "workers:"
        while IFS= read -r worker_id; do
            [ -n "$worker_id" ] || continue
            worker_state="$(worker_state_for_agent "$worker_id")"
            echo "  ${worker_id}: \"${worker_state}\""
        done < <(ac_worker_ids)
    } > "${STATUS_DIR}/current.yaml"
}

main_loop() {
    while true; do
        process_send_outbox
        process_command_queue
        process_open_questions_notify
        resume_tasks_from_answered_questions
        process_report_notifications
        notify_task_author_research_complete
        requeue_blocked_pre_review_test_gate_tasks
        generate_review_tasks_if_needed
        expand_pending_review_groups
        finalize_review_groups
        dispatch_directory "$TASK_PENDING_DIR" "$TASK_INFLIGHT_DIR"
        dispatch_directory "$REVIEW_PENDING_DIR" "$REVIEW_INFLIGHT_DIR"
        refresh_current_status
        sleep "$SWEEP_INTERVAL_SECONDS"
    done
}

init_runtime
run_tmux_snapshot_loop &
TMUX_SNAPSHOT_LOOP_PID="$!"
main_loop
