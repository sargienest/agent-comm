#!/usr/bin/env bash

set -euo pipefail

if [ -n "${AC_COMMON_SH_LOADED:-}" ]; then
    return 0
fi
AC_COMMON_SH_LOADED=1

AC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AC_REPO_ROOT_DEFAULT="$(cd "${AC_SCRIPT_DIR}/.." && pwd)"

TASK_ID_REGEX='^[A-Za-z0-9_.:-]+$'
AC_RESET_COMMAND="/clear"
AC_REQUIRED_ROLE_IDS=(common coordinator task_author worker implementer tester reviewer investigation analyst)
AC_CONTROL_AGENT_SECTIONS=(coordinator task_author dispatcher)
AC_SINGLETON_WORKER_SECTIONS=(investigation analyst tester)
AC_POOL_AGENT_SECTIONS=(implementer reviewer)
AC_REQUIRED_AGENT_SECTIONS=(coordinator task_author dispatcher investigation analyst tester implementer reviewer)

ac_now_iso() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

ac_now_epoch() {
    date +%s
}

ac_now_human() {
    date '+%Y-%m-%d %H:%M:%S'
}

ac_trim() {
    local raw="${1:-}"
    raw="${raw#${raw%%[![:space:]]*}}"
    raw="${raw%${raw##*[![:space:]]}}"
    printf '%s' "$raw"
}

ac_normalize_language() {
    local raw normalized
    raw="$(ac_trim "${1:-}")"
    normalized="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
    normalized="${normalized#-}"
    normalized="${normalized%-}"
    printf '%s\n' "$normalized"
}

ac_log() {
    echo "$(ac_now_human) $*"
}

ac_fail() {
    echo "❌ $*" >&2
    exit 1
}

ac_fail_with_code() {
    local error_code="$1"
    shift || true

    if [ "${AGENT_COMM_ERROR_FORMAT:-}" = "code" ]; then
        printf '%s\n' "$error_code" >&2
        exit 1
    fi

    ac_fail "$@"
}

ac_i18n_register() {
    local key="$1"
    local value="$2"
    AC_I18N["$key"]="$value"
}

ac_load_i18n() {
    local i18n_dir base_lang file

    i18n_dir="${AC_REPO_ROOT}/i18n/bash"
    declare -gA AC_I18N=()

    file="${i18n_dir}/en.sh"
    if [ -f "$file" ]; then
        # shellcheck disable=SC1090
        source "$file"
    fi

    base_lang="${AC_RUNTIME_LANGUAGE%%-*}"
    if [ -n "$base_lang" ] && [ "$base_lang" != "en" ]; then
        file="${i18n_dir}/${base_lang}.sh"
        if [ -f "$file" ]; then
            # shellcheck disable=SC1090
            source "$file"
        fi
    fi

    if [ -n "${AC_RUNTIME_LANGUAGE:-}" ] && [ "$AC_RUNTIME_LANGUAGE" != "$base_lang" ] && [ "$AC_RUNTIME_LANGUAGE" != "en" ]; then
        file="${i18n_dir}/${AC_RUNTIME_LANGUAGE}.sh"
        if [ -f "$file" ]; then
            # shellcheck disable=SC1090
            source "$file"
        fi
    fi
}

ac_t() {
    printf '%s\n' "${AC_I18N[$1]:-}"
}

ac_t_format() {
    local key="$1"
    shift || true

    local template assignment name value
    template="$(ac_t "$key")"
    for assignment in "$@"; do
        name="${assignment%%=*}"
        value="${assignment#*=}"
        template="${template//\{$name\}/$value}"
    done
    printf '%s\n' "$template"
}

ac_realpath() {
    local target="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath -m "$target"
        return
    fi

    if command -v readlink >/dev/null 2>&1; then
        readlink -f "$target"
        return
    fi

    case "$target" in
        /*) printf '%s\n' "$target" ;;
        *) printf '%s/%s\n' "$(pwd -P)" "$target" ;;
    esac
}

ac_repo_root() {
    if [ -n "${AC_REPO_ROOT:-}" ]; then
        printf '%s\n' "$AC_REPO_ROOT"
        return
    fi

    printf '%s\n' "$AC_REPO_ROOT_DEFAULT"
}

ac_ini_path() {
    if [ -n "${AC_INI_PATH:-}" ]; then
        printf '%s\n' "$AC_INI_PATH"
        return
    fi

    printf '%s/agent-comm.ini\n' "$(ac_repo_root)"
}

ac_agents_ini_path() {
    if [ -n "${AC_AGENTS_INI_PATH:-}" ]; then
        printf '%s\n' "$AC_AGENTS_INI_PATH"
        return
    fi

    printf '%s/agents.ini\n' "$(ac_repo_root)"
}

ac_ini_dir() {
    dirname "$(ac_ini_path)"
}

ac_ini_get_from_path() {
    local ini_file="$1"
    local section="$2"
    local key="$3"
    local default_value="${4:-}"
    if [ ! -f "$ini_file" ]; then
        printf '%s\n' "$default_value"
        return
    fi

    awk -F '=' -v target_section="$section" -v target_key="$key" -v fallback="$default_value" '
        BEGIN {
            in_section = 0
            found = 0
        }
        /^[[:space:]]*[#;]/ {
            next
        }
        /^[[:space:]]*\[/ {
            section = $0
            gsub(/^[[:space:]]*\[/, "", section)
            gsub(/\][[:space:]]*$/, "", section)
            in_section = (section == target_section)
            next
        }
        in_section == 1 {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (line ~ "^" target_key "[[:space:]]*=") {
                sub(/^[^=]*=/, "", line)
                sub(/^[[:space:]]+/, "", line)
                sub(/[[:space:]]+$/, "", line)
                print line
                found = 1
                exit
            }
        }
        END {
            if (found == 0) {
                print fallback
            }
        }
    ' "$ini_file"
}

ac_ini_get() {
    local section="$1"
    local key="$2"
    local default_value="${3:-}"
    ac_ini_get_from_path "$(ac_ini_path)" "$section" "$key" "$default_value"
}

ac_agents_ini_get() {
    local section="$1"
    local key="$2"
    local default_value="${3:-}"
    ac_ini_get_from_path "$(ac_agents_ini_path)" "$section" "$key" "$default_value"
}

ac_parse_bool() {
    local raw
    raw=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    case "$raw" in
        1|true|yes|on) echo 1 ;;
        0|false|no|off|'') echo 0 ;;
        *) ac_fail "Invalid boolean value: $1" ;;
    esac
}

ac_normalize_runtime() {
    local raw normalized
    raw="$(ac_trim "${1:-}")"
    normalized="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
    case "$normalized" in
        codex|claude)
            printf '%s\n' "$normalized"
            ;;
        '')
            printf '\n'
            ;;
        *)
            ac_fail "runtime must be codex or claude: ${1:-}"
            ;;
    esac
}

ac_resolve_config_path() {
    local raw="$1"

    case "$raw" in
        "~")
            ac_realpath "$HOME"
            ;;
        "~/"*)
            ac_realpath "${HOME}/${raw:2}"
            ;;
        /*)
            ac_realpath "$raw"
            ;;
        *)
            ac_realpath "$(ac_ini_dir)/$raw"
            ;;
    esac
}

ac_csv_to_array() {
    local raw="$1"
    local item
    local -n out_ref="$2"

    out_ref=()
    IFS=',' read -r -a items <<< "$raw"
    for item in "${items[@]}"; do
        item=$(ac_trim "$item")
        [ -n "$item" ] || continue
        out_ref+=("$item")
    done
}

ac_slugify() {
    local raw="$1"
    local slug

    slug="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_.-' '-')"
    slug="${slug#-}"
    slug="${slug%-}"
    printf '%s\n' "${slug:-project}"
}

ac_default_tmux_session_name() {
    local project_slug path_hash

    project_slug="$(basename "$(dirname "$AC_REPO_ROOT")")"
    project_slug="$(ac_slugify "$project_slug")"
    project_slug="${project_slug:0:24}"

    if command -v sha1sum >/dev/null 2>&1; then
        path_hash="$(printf '%s' "$AC_REPO_ROOT" | sha1sum | awk '{print substr($1, 1, 8)}')"
    elif command -v shasum >/dev/null 2>&1; then
        path_hash="$(printf '%s' "$AC_REPO_ROOT" | shasum | awk '{print substr($1, 1, 8)}')"
    else
        path_hash="$(printf '%s' "$AC_REPO_ROOT" | cksum | awk '{print $1}')"
    fi

    printf 'agent-comm-%s-%s\n' "$project_slug" "$path_hash"
}

ac_agent_section_label() {
    case "$1" in
        coordinator) printf 'Coordinator\n' ;;
        task_author) printf 'Task Author\n' ;;
        dispatcher) printf 'Dispatcher\n' ;;
        investigation) printf 'Investigation\n' ;;
        analyst) printf 'Analyst\n' ;;
        tester) printf 'Tester\n' ;;
        implementer) printf 'Implementer\n' ;;
        reviewer) printf 'Reviewer\n' ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

ac_append_section_agent_id() {
    local section="$1"
    local agent_id="$2"
    if [ -n "${AC_SECTION_AGENT_IDS[$section]:-}" ]; then
        AC_SECTION_AGENT_IDS["$section"]+=$'\n'
    fi
    AC_SECTION_AGENT_IDS["$section"]+="$agent_id"
}

ac_load_agent_topology() {
    local section runtime model count_raw count label index agent_id

    AC_AGENTS_INI_PATH="$(ac_agents_ini_path)"
    [ -f "$AC_AGENTS_INI_PATH" ] || ac_fail "agents.ini was not found: ${AC_AGENTS_INI_PATH}"

    declare -ga AC_AGENT_IDS=()
    declare -ga AC_WORKER_AGENT_IDS=()
    declare -gA AC_AGENT_SECTION_BY_ID=()
    declare -gA AC_AGENT_RUNTIME_BY_ID=()
    declare -gA AC_AGENT_MODEL_BY_ID=()
    declare -gA AC_AGENT_LABEL_BY_ID=()
    declare -gA AC_AGENT_KIND_BY_ID=()
    declare -gA AC_AGENT_PERSONA_BY_ID=()
    declare -gA AC_SECTION_AGENT_IDS=()
    declare -gA AC_SECTION_RUNTIME=()
    declare -gA AC_SECTION_MODEL=()
    declare -gA AC_SECTION_COUNT=()

    for section in "${AC_REQUIRED_AGENT_SECTIONS[@]}"; do
        runtime="$(ac_normalize_runtime "$(ac_agents_ini_get "$section" runtime '')")"
        [ -n "$runtime" ] || ac_fail "agents.ini [${section}] runtime is required."
        model="$(ac_trim "$(ac_agents_ini_get "$section" model '')")"

        case "$section" in
            implementer|reviewer)
                count_raw="$(ac_trim "$(ac_agents_ini_get "$section" count '')")"
                [ -n "$count_raw" ] || ac_fail "agents.ini [${section}] count is required."
                [[ "$count_raw" =~ ^[0-9]+$ ]] || ac_fail "agents.ini [${section}] count must be numeric."
                [ "$count_raw" -ge 1 ] || ac_fail "agents.ini [${section}] count must be 1 or greater."
                count="$count_raw"
                ;;
            *)
                count=1
                ;;
        esac

        AC_SECTION_RUNTIME["$section"]="$runtime"
        AC_SECTION_MODEL["$section"]="$model"
        AC_SECTION_COUNT["$section"]="$count"
        label="$(ac_agent_section_label "$section")"

        if [ "$count" -eq 1 ] && [ "$section" != "implementer" ] && [ "$section" != "reviewer" ]; then
            agent_id="$section"
            AC_AGENT_IDS+=("$agent_id")
            AC_AGENT_SECTION_BY_ID["$agent_id"]="$section"
            AC_AGENT_RUNTIME_BY_ID["$agent_id"]="$runtime"
            AC_AGENT_MODEL_BY_ID["$agent_id"]="$model"
            AC_AGENT_LABEL_BY_ID["$agent_id"]="$label"
            ac_append_section_agent_id "$section" "$agent_id"

            case "$section" in
                coordinator|task_author|dispatcher)
                    AC_AGENT_KIND_BY_ID["$agent_id"]="control"
                    ;;
                *)
                    AC_AGENT_KIND_BY_ID["$agent_id"]="worker"
                    AC_AGENT_PERSONA_BY_ID["$agent_id"]="$section"
                    AC_WORKER_AGENT_IDS+=("$agent_id")
                    ;;
            esac
            continue
        fi

        index=1
        while [ "$index" -le "$count" ]; do
            agent_id="${section}${index}"
            AC_AGENT_IDS+=("$agent_id")
            AC_WORKER_AGENT_IDS+=("$agent_id")
            AC_AGENT_SECTION_BY_ID["$agent_id"]="$section"
            AC_AGENT_RUNTIME_BY_ID["$agent_id"]="$runtime"
            AC_AGENT_MODEL_BY_ID["$agent_id"]="$model"
            AC_AGENT_LABEL_BY_ID["$agent_id"]="${label} ${index}"
            AC_AGENT_KIND_BY_ID["$agent_id"]="worker"
            AC_AGENT_PERSONA_BY_ID["$agent_id"]="$section"
            ac_append_section_agent_id "$section" "$agent_id"
            index=$((index + 1))
        done
    done
}

ac_load_config() {
    AC_REPO_ROOT="$(ac_repo_root)"
    AC_INI_PATH="$(ac_ini_path)"
    AC_AGENTS_INI_PATH="$(ac_agents_ini_path)"
    AC_RUNTIME_ROOT="${AC_REPO_ROOT}/.runtime"

    AC_AGENT_WORKING_DIR="$(ac_resolve_config_path "$(ac_ini_get runtime agent_working_dir ../)")"
    AC_RUNTIME_LANGUAGE="$(ac_normalize_language "$(ac_ini_get runtime language '')")"
    AC_CODEX_HOME="$(ac_resolve_config_path "$(ac_ini_get runtime codex_home '~/.codex')")"
    AC_CODEX_DANGEROUS="$(ac_parse_bool "$(ac_ini_get runtime dangerously_bypass_approvals_and_sandbox false)")"

    local configured_session_name
    configured_session_name="$(ac_trim "$(ac_ini_get tmux session_name '')")"
    if [ -n "$configured_session_name" ]; then
        AC_TMUX_SESSION_NAME="$configured_session_name"
    else
        AC_TMUX_SESSION_NAME="$(ac_default_tmux_session_name)"
    fi
    [[ "$AC_TMUX_SESSION_NAME" =~ ^[A-Za-z0-9_.-]+$ ]] || ac_fail "tmux.session_name may contain only letters, numbers, ., _, and -."

    AC_UI_AUTO_START="$(ac_parse_bool "$(ac_ini_get ui auto_start true)")"
    AC_UI_PORT="$(ac_ini_get ui port 43861)"
    [[ "$AC_UI_PORT" =~ ^[0-9]+$ ]] || ac_fail "ui.port must be numeric."
    AC_UI_OPEN_BROWSER="$(ac_parse_bool "$(ac_ini_get ui open_browser false)")"
    AC_UI_LANGUAGE="$(ac_normalize_language "$(ac_ini_get ui language '')")"
    if [ -z "$AC_RUNTIME_LANGUAGE" ]; then
        AC_RUNTIME_LANGUAGE="$AC_UI_LANGUAGE"
    fi
    [ -n "$AC_RUNTIME_LANGUAGE" ] || AC_RUNTIME_LANGUAGE="en"
    if [ -z "$AC_UI_LANGUAGE" ]; then
        AC_UI_LANGUAGE="$AC_RUNTIME_LANGUAGE"
    fi
    [ -n "$AC_UI_LANGUAGE" ] || AC_UI_LANGUAGE="en"

    AC_ROLES_PATH="${AC_REPO_ROOT}/roles/i18n"
    AC_ROLES_EXTRA_PATHS_RAW="$(ac_ini_get roles extra_paths '')"

    declare -ga AC_ROLE_SEARCH_PATHS=()
    AC_ROLE_SEARCH_PATHS=("$AC_ROLES_PATH")

    local extra_entries extra_path
    ac_csv_to_array "$AC_ROLES_EXTRA_PATHS_RAW" extra_entries
    for extra_path in "${extra_entries[@]}"; do
        AC_ROLE_SEARCH_PATHS+=("$(ac_resolve_config_path "$extra_path")")
    done

    AC_CONFIG_DIR="${AC_RUNTIME_ROOT}/config"
    COMMANDS_DIR="${AC_RUNTIME_ROOT}/commands"
    TASKS_DIR="${AC_RUNTIME_ROOT}/tasks"
    REVIEWS_DIR="${AC_RUNTIME_ROOT}/reviews"
    QUESTIONS_DIR="${AC_RUNTIME_ROOT}/questions"
    REWORK_DIR="${AC_RUNTIME_ROOT}/rework_notes"
    EVENTS_DIR="${AC_RUNTIME_ROOT}/events"
    REPORTS_DIR="${AC_RUNTIME_ROOT}/reports"
    LOCKS_DIR="${AC_RUNTIME_ROOT}/locks"
    RUNTIME_DIR="${AC_RUNTIME_ROOT}/runtime"
    STATUS_DIR="${AC_RUNTIME_ROOT}/status"
    MANUAL_PROMPTS_DIR="${AC_RUNTIME_ROOT}/manual-prompts"
    RESEARCH_RESULTS_DIR="${AC_RUNTIME_ROOT}/research_results"
    ROLES_RUNTIME_DIR="${AC_RUNTIME_ROOT}/roles"

    TASK_PENDING_DIR="${TASKS_DIR}/pending"
    TASK_INFLIGHT_DIR="${TASKS_DIR}/inflight"
    TASK_DONE_DIR="${TASKS_DIR}/done"
    TASK_BLOCKED_DIR="${TASKS_DIR}/blocked"

    REVIEW_PENDING_DIR="${REVIEWS_DIR}/pending"
    REVIEW_INFLIGHT_DIR="${REVIEWS_DIR}/inflight"
    REVIEW_DONE_DIR="${REVIEWS_DIR}/done"

    QUESTION_OPEN_DIR="${QUESTIONS_DIR}/open"
    QUESTION_ANSWERED_DIR="${QUESTIONS_DIR}/answered"

    EVENT_OUTBOX_DIR="${EVENTS_DIR}/outbox"
    EVENT_SENT_DIR="${EVENTS_DIR}/sent"

    REPORT_EVENTS_DIR="${REPORTS_DIR}/events"
    FILE_LOCKS_DIR="${LOCKS_DIR}/files"
    TMUX_SNAPSHOT_DIR="${STATUS_DIR}/tmux"

    DISPATCH_LOCK_FILE="${LOCKS_DIR}/dispatch.lock"
    DISPATCHER_PID_FILE="${RUNTIME_DIR}/dispatcher.pid"
    DISPATCHER_TOKEN_FILE="${RUNTIME_DIR}/dispatcher.token"
    DASHBOARD_PID_FILE="${STATUS_DIR}/dashboard.pid"
    DASHBOARD_LOG_FILE="${STATUS_DIR}/dashboard.log"
    RUNTIME_ENV_FILE="${STATUS_DIR}/runtime.env"
    ROLE_MANIFEST_FILE="${ROLES_RUNTIME_DIR}/manifest.tsv"
    ROLE_MANIFEST_LANGUAGE_FILE="${ROLES_RUNTIME_DIR}/manifest.language"
    ROLE_PERSONAS_FILE="${ROLES_RUNTIME_DIR}/personas.txt"
    ROLE_PERSONAS_MARKDOWN_FILE="${ROLES_RUNTIME_DIR}/personas.md"

    ac_load_agent_topology
}

ac_role_language_score() {
    local candidate normalized requested requested_base candidate_base
    candidate="$(ac_normalize_language "${1:-}")"
    requested="${AC_RUNTIME_LANGUAGE:-en}"
    requested_base="${requested%%-*}"
    candidate_base="${candidate%%-*}"

    if [ -n "$candidate" ] && [ "$candidate" = "$requested" ]; then
        echo 500
        return
    fi

    if [ -n "$candidate" ] && [ "$candidate" = "$requested_base" ]; then
        echo 450
        return
    fi

    if [ -n "$candidate_base" ] && [ "$candidate_base" = "$requested_base" ]; then
        echo 400
        return
    fi

    if [ -n "$candidate" ] && [ "$candidate" = "en" ]; then
        echo 300
        return
    fi

    if [ -n "$candidate_base" ] && [ "$candidate_base" = "en" ]; then
        echo 250
        return
    fi

    if [ -z "$candidate" ]; then
        echo 200
        return
    fi

    echo 100
}

ac_worker_ids() {
    printf '%s\n' "${AC_WORKER_AGENT_IDS[@]}"
}

ac_all_agent_ids() {
    printf '%s\n' "${AC_AGENT_IDS[@]}"
}

ac_section_agent_ids() {
    local section="$1"
    if [ -n "${AC_SECTION_AGENT_IDS[$section]:-}" ]; then
        printf '%s\n' "${AC_SECTION_AGENT_IDS[$section]}"
    fi
}

ac_agent_section() {
    printf '%s\n' "${AC_AGENT_SECTION_BY_ID[$1]:-}"
}

ac_agent_runtime() {
    printf '%s\n' "${AC_AGENT_RUNTIME_BY_ID[$1]:-}"
}

ac_agent_model() {
    printf '%s\n' "${AC_AGENT_MODEL_BY_ID[$1]:-}"
}

ac_agent_label() {
    printf '%s\n' "${AC_AGENT_LABEL_BY_ID[$1]:-$1}"
}

ac_agent_kind() {
    printf '%s\n' "${AC_AGENT_KIND_BY_ID[$1]:-}"
}

ac_agent_is_worker() {
    [ "$(ac_agent_kind "$1")" = "worker" ]
}

ac_agent_pane_index() {
    local agent_id="$1"
    case "$agent_id" in
        implementer*)
            [[ "$agent_id" =~ ^implementer([0-9]+)$ ]] || return 1
            echo "$((BASH_REMATCH[1] - 1))"
            ;;
        reviewer*)
            [[ "$agent_id" =~ ^reviewer([0-9]+)$ ]] || return 1
            echo "$((BASH_REMATCH[1] - 1))"
            ;;
        *)
            return 1
            ;;
    esac
}

ac_validate_worker_id() {
    local worker_id="$1"
    local candidate
    while IFS= read -r candidate; do
        if [ "$candidate" = "$worker_id" ]; then
            return 0
        fi
    done < <(ac_worker_ids)
    ac_fail "Invalid worker id: ${worker_id}"
}

ac_worker_persona() {
    printf '%s\n' "${AC_AGENT_PERSONA_BY_ID[$1]:-}"
}

ac_supported_persona() {
    case "$1" in
        implementer|reviewer|tester|investigation|analyst)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

ac_agents_for_persona() {
    local persona="$1"
    case "$persona" in
        implementer|reviewer|tester|investigation|analyst)
            ac_section_agent_ids "$persona"
            ;;
    esac
}

ac_runtime_set_name() {
    local seen_codex=0 seen_claude=0 agent_id runtime
    for agent_id in "${AC_AGENT_IDS[@]}"; do
        runtime="$(ac_agent_runtime "$agent_id")"
        case "$runtime" in
            codex) seen_codex=1 ;;
            claude) seen_claude=1 ;;
        esac
    done

    if [ "$seen_codex" -eq 1 ] && [ "$seen_claude" -eq 1 ]; then
        printf 'mixed\n'
    elif [ "$seen_codex" -eq 1 ]; then
        printf 'codex\n'
    elif [ "$seen_claude" -eq 1 ]; then
        printf 'claude\n'
    else
        printf 'unknown\n'
    fi
}

ac_agent_tmux_target() {
    local agent="$1"
    case "$agent" in
        coordinator) printf '%s:coordinator\n' "$AC_TMUX_SESSION_NAME" ;;
        task_author|manager) printf '%s:task-author\n' "$AC_TMUX_SESSION_NAME" ;;
        dispatcher) printf '%s:dispatcher\n' "$AC_TMUX_SESSION_NAME" ;;
        investigation|analyst|tester)
            printf '%s:%s\n' "$AC_TMUX_SESSION_NAME" "$agent"
            ;;
        implementer*|reviewer*)
            local pane_index
            pane_index="$(ac_agent_pane_index "$agent")" || return 1
            printf '%s:%s.%s\n' "$AC_TMUX_SESSION_NAME" "$(ac_agent_section "$agent")" "$pane_index"
            ;;
        *)
            return 1
            ;;
    esac
}

ac_ensure_runtime_dirs() {
    mkdir -p \
        "${AC_CONFIG_DIR}" \
        "${COMMANDS_DIR}" \
        "${TASK_PENDING_DIR}" "${TASK_INFLIGHT_DIR}" "${TASK_DONE_DIR}" "${TASK_BLOCKED_DIR}" \
        "${REVIEW_PENDING_DIR}" "${REVIEW_INFLIGHT_DIR}" "${REVIEW_DONE_DIR}" \
        "${QUESTION_OPEN_DIR}" "${QUESTION_ANSWERED_DIR}" \
        "${REWORK_DIR}" \
        "${EVENT_OUTBOX_DIR}" "${EVENT_SENT_DIR}" \
        "${REPORTS_DIR}" "${REPORT_EVENTS_DIR}" \
        "${LOCKS_DIR}" "${FILE_LOCKS_DIR}" \
        "${RUNTIME_DIR}" "${STATUS_DIR}" "${TMUX_SNAPSHOT_DIR}" \
        "${MANUAL_PROMPTS_DIR}" "${RESEARCH_RESULTS_DIR}" "${ROLES_RUNTIME_DIR}"
    touch "${DISPATCH_LOCK_FILE}"
}

ac_ensure_dirs() {
    ac_ensure_runtime_dirs
}

ac_write_runtime_env() {
    ac_ensure_runtime_dirs
    {
        echo "AC_REPO_ROOT=\"${AC_REPO_ROOT}\""
        echo "AC_INI_PATH=\"${AC_INI_PATH}\""
        echo "AC_RUNTIME_ROOT=\"${AC_RUNTIME_ROOT}\""
        echo "AC_AGENT_WORKING_DIR=\"${AC_AGENT_WORKING_DIR}\""
        echo "AC_AGENTS_INI_PATH=\"${AC_AGENTS_INI_PATH}\""
        echo "AC_RUNTIME_LANGUAGE=\"${AC_RUNTIME_LANGUAGE}\""
        echo "AC_CODEX_HOME=\"${AC_CODEX_HOME}\""
        echo "AC_CODEX_DANGEROUS=\"${AC_CODEX_DANGEROUS}\""
        echo "AC_TMUX_SESSION_NAME=\"${AC_TMUX_SESSION_NAME}\""
        echo "AC_UI_AUTO_START=\"${AC_UI_AUTO_START}\""
        echo "AC_UI_PORT=\"${AC_UI_PORT}\""
        echo "AC_UI_OPEN_BROWSER=\"${AC_UI_OPEN_BROWSER}\""
        echo "AC_UI_LANGUAGE=\"${AC_UI_LANGUAGE}\""
        echo "AC_ROLES_PATH=\"${AC_ROLES_PATH}\""
        echo "AC_ROLES_EXTRA_PATHS_RAW=\"${AC_ROLES_EXTRA_PATHS_RAW}\""
        echo "AGENT_RUNTIME=\"$(ac_runtime_set_name)\""
        echo "AGENT_RESET_COMMAND=\"${AC_RESET_COMMAND}\""
        echo "AGENT_SESSION=\"${AC_TMUX_SESSION_NAME}\""
        echo "AGENT_COMM_ROOT=\"${AC_REPO_ROOT}\""
    } > "${RUNTIME_ENV_FILE}"
}

ac_parse_frontmatter_value() {
    local file="$1"
    local key="$2"
    awk -v target_key="$key" '
        BEGIN {
            in_frontmatter = 0
            separator_count = 0
        }
        /^---[[:space:]]*$/ {
            separator_count++
            if (separator_count == 1) {
                in_frontmatter = 1
                next
            }
            if (separator_count == 2) {
                exit
            }
        }
        in_frontmatter == 1 && $0 ~ "^[[:space:]]*" target_key ":" {
            line = $0
            sub(/^[^:]*:[[:space:]]*/, "", line)
            gsub(/^[\"\047]|[\"\047]$/, "", line)
            print line
            exit
        }
    ' "$file"
}

ac_generate_role_manifest() {
    ac_ensure_runtime_dirs

    local role_file role_id role_kind role_label role_required role_lang search_path score previous_score
    local tmp_manifest tmp_personas tmp_personas_md
    declare -A role_kind_map=()
    declare -A role_label_map=()
    declare -A role_required_map=()
    declare -A role_path_map=()
    declare -A role_lang_map=()
    declare -A role_score_map=()

    for search_path in "${AC_ROLE_SEARCH_PATHS[@]}"; do
        [ -d "$search_path" ] || continue
        while IFS= read -r role_file; do
            role_id="$(ac_parse_frontmatter_value "$role_file" "id")"
            role_kind="$(ac_parse_frontmatter_value "$role_file" "kind")"
            role_label="$(ac_parse_frontmatter_value "$role_file" "label")"
            role_required="$(ac_parse_frontmatter_value "$role_file" "required")"
            role_lang="$(ac_normalize_language "$(ac_parse_frontmatter_value "$role_file" "lang")")"
            [ -n "$role_id" ] || ac_fail "role frontmatter の id がありません: ${role_file}"
            [ -n "$role_kind" ] || ac_fail "role frontmatter の kind がありません: ${role_file}"
            [ -n "$role_label" ] || ac_fail "role frontmatter の label がありません: ${role_file}"
            [ -n "$role_lang" ] || ac_fail "role frontmatter の lang がありません: ${role_file}"
            case "$role_kind" in
                agent|persona|shared) ;;
                *) ac_fail "Invalid role kind: ${role_file} (${role_kind})" ;;
            esac
            score="$(ac_role_language_score "$role_lang")"
            previous_score="${role_score_map[$role_id]:--1}"
            if [ "$score" -lt "$previous_score" ]; then
                continue
            fi
            if [ "$score" -eq "$previous_score" ] && [ -n "${role_path_map[$role_id]:-}" ] && [[ "${role_path_map[$role_id]}" < "$role_file" ]]; then
                continue
            fi

            role_kind_map["$role_id"]="$role_kind"
            role_label_map["$role_id"]="$role_label"
            role_lang_map["$role_id"]="$role_lang"
            role_score_map["$role_id"]="$score"
            case "$(printf '%s' "$role_required" | tr '[:upper:]' '[:lower:]')" in
                1|true|yes|on) role_required_map["$role_id"]=1 ;;
                *) role_required_map["$role_id"]=0 ;;
            esac
            role_path_map["$role_id"]="$role_file"
        done < <(find "$search_path" -type f -name '*.md' | sort)
    done

    local required_id
    for required_id in "${AC_REQUIRED_ROLE_IDS[@]}"; do
        [ -n "${role_path_map[$required_id]:-}" ] || ac_fail "Missing required role: ${required_id}"
    done

    tmp_manifest="$(mktemp)"
    tmp_personas="$(mktemp)"
    tmp_personas_md="$(mktemp)"

    {
        local role_key
        for role_key in $(printf '%s\n' "${!role_path_map[@]}" | sort); do
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$role_key" \
                "${role_kind_map[$role_key]}" \
                "${role_label_map[$role_key]}" \
                "${role_required_map[$role_key]}" \
                "${role_lang_map[$role_key]:-}" \
                "${role_path_map[$role_key]}"
        done
    } > "$tmp_manifest"

    awk -F '\t' '$2 == "persona" { print $1 }' "$tmp_manifest" > "$tmp_personas"

    {
        printf '# %s\n' "$(ac_t 'role_manifest.title')"
        echo
        printf '%s\n' "$(ac_t 'role_manifest.generated')"
        echo
        awk -F '\t' '$2 == "persona" { printf "- `%s`: %s (`%s`)\n", $1, $3, $6 }' "$tmp_manifest"
    } > "$tmp_personas_md"

    mv "$tmp_manifest" "$ROLE_MANIFEST_FILE"
    printf '%s\n' "$AC_RUNTIME_LANGUAGE" > "$ROLE_MANIFEST_LANGUAGE_FILE"
    mv "$tmp_personas" "$ROLE_PERSONAS_FILE"
    mv "$tmp_personas_md" "$ROLE_PERSONAS_MARKDOWN_FILE"
}

ac_ensure_role_manifest() {
    if [ ! -f "$ROLE_MANIFEST_FILE" ] || [ ! -f "$ROLE_MANIFEST_LANGUAGE_FILE" ] || [ ! -f "$ROLE_PERSONAS_FILE" ] || [ ! -f "$ROLE_PERSONAS_MARKDOWN_FILE" ]; then
        ac_generate_role_manifest
        return
    fi

    if [ "$(cat "$ROLE_MANIFEST_LANGUAGE_FILE" 2>/dev/null || true)" != "$AC_RUNTIME_LANGUAGE" ]; then
        ac_generate_role_manifest
    fi
}

ac_role_path() {
    local role_id="$1"
    ac_ensure_role_manifest
    awk -F '\t' -v target_id="$role_id" '$1 == target_id { print $6; exit }' "$ROLE_MANIFEST_FILE"
}

ac_list_personas() {
    ac_ensure_role_manifest
    cat "$ROLE_PERSONAS_FILE"
}

ac_assert_persona_exists() {
    local persona="$1"
    local available
    if ac_list_personas | grep -Fxq "$persona"; then
        return 0
    fi

    available=$(ac_list_personas | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    [ -n "$available" ] || available="(none)"
    ac_fail "Persona definition was not found: ${persona} / available: ${available}"
}

ac_escape_yaml_double_quoted() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

ac_write_yaml_list_block() {
    local key="$1"
    shift
    local values=("$@")
    local value escaped

    if [ "${#values[@]}" -eq 0 ]; then
        echo "${key}: []"
        return
    fi

    echo "${key}:"
    for value in "${values[@]}"; do
        escaped=$(ac_escape_yaml_double_quoted "$value")
        echo "  - \"${escaped}\""
    done
}

ac_atomic_write_from_tmp() {
    local tmp_file="$1"
    local dest_file="$2"
    mkdir -p "$(dirname "$dest_file")"
    mv "$tmp_file" "$dest_file"
}

ac_atomic_write_stdin() {
    local dest_file="$1"
    local tmp_file
    tmp_file=$(mktemp)
    cat > "$tmp_file"
    ac_atomic_write_from_tmp "$tmp_file" "$dest_file"
}

ac_read_yaml_scalar() {
    local file="$1"
    local key="$2"
    local line value

    [ -f "$file" ] || return 0
    line=$(grep -E "^${key}:" "$file" 2>/dev/null | head -1 || true)
    line=$(ac_trim "$line")
    [ -n "$line" ] || return 0

    value="${line#*:}"
    value=$(ac_trim "$value")
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    printf '%s' "$value"
}

ac_read_yaml_list() {
    local file="$1"
    local key="$2"
    [ -f "$file" ] || return 0

    awk -v key="$key" '
        BEGIN {
            in_list = 0
        }
        $0 ~ "^" key ":" {
            in_list = 1
            next
        }
        in_list == 1 {
            if ($0 ~ /^  - /) {
                item = $0
                sub(/^  -[[:space:]]*/, "", item)
                gsub(/^"|"$/, "", item)
                gsub(/^\047|\047$/, "", item)
                print item
                next
            }
            if ($0 ~ /^[A-Za-z0-9_]+:/) {
                in_list = 0
            }
        }
    ' "$file"
}

ac_read_yaml_block() {
    local file="$1"
    local key="$2"
    [ -f "$file" ] || return 0

    awk -v key="$key" '
        BEGIN {
            in_block = 0
        }
        $0 ~ "^" key ":[[:space:]]*\\|" {
            in_block = 1
            next
        }
        in_block == 1 {
            if ($0 ~ /^  /) {
                line = $0
                sub(/^  /, "", line)
                print line
                next
            }
            if ($0 ~ /^[A-Za-z0-9_]+:/) {
                in_block = 0
            }
        }
    ' "$file"
}

ac_set_yaml_scalar() {
    local file="$1"
    local key="$2"
    local value_raw="$3"
    local escaped tmp

    escaped=$(ac_escape_yaml_double_quoted "$value_raw")
    tmp=$(mktemp)
    awk -v key="$key" -v value="\"${escaped}\"" '
        BEGIN {
            updated = 0
        }
        {
            if ($0 ~ "^" key ":[[:space:]]*") {
                print key ": " value
                updated = 1
            } else {
                print $0
            }
        }
        END {
            if (updated == 0) {
                print key ": " value
            }
        }
    ' "$file" > "$tmp"
    ac_atomic_write_from_tmp "$tmp" "$file"
}

ac_replace_yaml_multiline_block() {
    local file="$1"
    local key="$2"
    local content="$3"
    local tmp

    tmp=$(mktemp)
    awk -v key="$key" -v body="$content" '
        function print_body() {
            print key ": |"
            n = split(body, lines, "\n")
            for (i = 1; i <= n; i++) {
                print "  " lines[i]
            }
        }
        BEGIN {
            replaced = 0
            skipping = 0
        }
        {
            if ($0 ~ "^" key ":[[:space:]]*\\|") {
                if (replaced == 0) {
                    print_body()
                    replaced = 1
                }
                skipping = 1
                next
            }
            if (skipping == 1) {
                if ($0 ~ /^  /) {
                    next
                }
                skipping = 0
            }
            print $0
        }
        END {
            if (replaced == 0) {
                print_body()
            }
        }
    ' "$file" > "$tmp"
    ac_atomic_write_from_tmp "$tmp" "$file"
}

ac_replace_yaml_list_block() {
    local file="$1"
    local key="$2"
    shift 2
    local values=("$@")
    local tmp line skipping=0 replaced=0

    tmp=$(mktemp)
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$skipping" -eq 1 ]; then
            if [[ "$line" == "  - "* ]]; then
                continue
            fi
            if [[ ! "$line" =~ ^[A-Za-z0-9_]+: ]]; then
                continue
            fi
            skipping=0
        fi

        if [[ "$line" =~ ^${key}: ]]; then
            if [ "${#values[@]}" -eq 0 ]; then
                printf '%s: []\n' "$key" >> "$tmp"
            else
                printf '%s:\n' "$key" >> "$tmp"
                local value
                for value in "${values[@]}"; do
                    printf '  - "%s"\n' "$(ac_escape_yaml_double_quoted "$value")" >> "$tmp"
                done
            fi
            replaced=1
            skipping=1
            continue
        fi

        printf '%s\n' "$line" >> "$tmp"
    done < "$file"

    if [ "$replaced" -eq 0 ]; then
        if [ "${#values[@]}" -eq 0 ]; then
            printf '%s: []\n' "$key" >> "$tmp"
        else
            printf '%s:\n' "$key" >> "$tmp"
            local value
            for value in "${values[@]}"; do
                printf '  - "%s"\n' "$(ac_escape_yaml_double_quoted "$value")" >> "$tmp"
            done
        fi
    fi

    ac_atomic_write_from_tmp "$tmp" "$file"
}

ac_default_research_result_path() {
    local task_id="$1"
    printf '%s/%s.md\n' "$RESEARCH_RESULTS_DIR" "$task_id"
}

ac_assert_task_id() {
    local task_id="$1"
    [[ "$task_id" =~ $TASK_ID_REGEX ]] || ac_fail "Invalid task id format: ${task_id}"
}

ac_all_task_files() {
    find \
        "${TASK_PENDING_DIR}" "${TASK_INFLIGHT_DIR}" "${TASK_DONE_DIR}" "${TASK_BLOCKED_DIR}" \
        "${REVIEW_PENDING_DIR}" "${REVIEW_INFLIGHT_DIR}" "${REVIEW_DONE_DIR}" \
        -maxdepth 1 -type f -name '*.yaml' 2>/dev/null | sort
}

ac_find_task_file_by_id() {
    local task_id="$1"
    local file id
    while IFS= read -r file; do
        id=$(ac_read_yaml_scalar "$file" "id")
        if [ "$id" = "$task_id" ]; then
            printf '%s' "$file"
            return 0
        fi
    done < <(ac_all_task_files)
    return 1
}

ac_collect_task_ids() {
    local file id
    while IFS= read -r file; do
        id=$(ac_read_yaml_scalar "$file" "id")
        [ -n "$id" ] && echo "$id"
    done < <(ac_all_task_files)
}

ac_task_kind_from_path() {
    local task_file="$1"
    case "$task_file" in
        "${REVIEW_PENDING_DIR}"/*|"${REVIEW_INFLIGHT_DIR}"/*|"${REVIEW_DONE_DIR}"/*) echo review ;;
        *) echo task ;;
    esac
}

ac_task_state_from_path() {
    local task_file="$1"
    case "$task_file" in
        "${TASK_PENDING_DIR}"/*|"${REVIEW_PENDING_DIR}"/*) echo pending ;;
        "${TASK_INFLIGHT_DIR}"/*|"${REVIEW_INFLIGHT_DIR}"/*) echo inflight ;;
        "${TASK_DONE_DIR}"/*|"${REVIEW_DONE_DIR}"/*) echo done ;;
        "${TASK_BLOCKED_DIR}"/*) echo blocked ;;
        *) echo unknown ;;
    esac
}

ac_task_is_done() {
    local dep_id="$1"
    local file state

    if ! file=$(ac_find_task_file_by_id "$dep_id"); then
        return 1
    fi

    state=$(ac_task_state_from_path "$file")
    [ "$state" = "done" ]
}

ac_task_lock_path_for_write_file() {
    local write_file="$1"
    local escaped
    escaped=$(printf '%s' "$write_file" | sed -e 's#/#__#g' -e 's#[^A-Za-z0-9_.-]#_#g')
    printf '%s/%s.lock' "$FILE_LOCKS_DIR" "$escaped"
}

ac_exclusive_group_lock_path() {
    local group_name="$1"
    local escaped
    escaped=$(printf '%s' "$group_name" | sed -e 's#[^A-Za-z0-9_.-]#_#g')
    printf '%s/group_%s.lock' "$FILE_LOCKS_DIR" "$escaped"
}

ac_acquire_task_locks() {
    local task_file="$1"
    local task_id write_file lock_path exclusive_group
    local acquired_locks=()

    task_id=$(ac_read_yaml_scalar "$task_file" "id")

    while IFS= read -r write_file; do
        [ -n "$write_file" ] || continue
        lock_path=$(ac_task_lock_path_for_write_file "$write_file")
        if mkdir "$lock_path" 2>/dev/null; then
            printf '%s\n' "$task_id" > "${lock_path}/owner"
            acquired_locks+=("$lock_path")
            continue
        fi
        local rollback_lock
        for rollback_lock in "${acquired_locks[@]}"; do
            rm -rf "$rollback_lock"
        done
        return 1
    done < <(ac_read_yaml_list "$task_file" "write_files")

    exclusive_group=$(ac_read_yaml_scalar "$task_file" "exclusive_group")
    if [ -n "$exclusive_group" ] && [ "$exclusive_group" != "null" ]; then
        lock_path=$(ac_exclusive_group_lock_path "$exclusive_group")
        if mkdir "$lock_path" 2>/dev/null; then
            printf '%s\n' "$task_id" > "${lock_path}/owner"
            acquired_locks+=("$lock_path")
        else
            local rollback_lock
            for rollback_lock in "${acquired_locks[@]}"; do
                rm -rf "$rollback_lock"
            done
            return 1
        fi
    fi

    return 0
}

ac_release_task_locks() {
    local task_file="$1"
    local task_id lock_path write_file exclusive_group owner

    task_id=$(ac_read_yaml_scalar "$task_file" "id")

    while IFS= read -r write_file; do
        [ -z "$write_file" ] && continue
        lock_path=$(ac_task_lock_path_for_write_file "$write_file")
        if [ -d "$lock_path" ]; then
            owner=$(cat "$lock_path/owner" 2>/dev/null || true)
            if [ "$owner" = "$task_id" ] || [ -z "$owner" ]; then
                rm -rf "$lock_path"
            fi
        fi
    done < <(ac_read_yaml_list "$task_file" "write_files")

    exclusive_group=$(ac_read_yaml_scalar "$task_file" "exclusive_group")
    if [ -n "$exclusive_group" ] && [ "$exclusive_group" != "null" ]; then
        lock_path=$(ac_exclusive_group_lock_path "$exclusive_group")
        if [ -d "$lock_path" ]; then
            owner=$(cat "$lock_path/owner" 2>/dev/null || true)
            if [ "$owner" = "$task_id" ] || [ -z "$owner" ]; then
                rm -rf "$lock_path"
            fi
        fi
    fi
}

ac_count_lines() {
    printf '%s\n' "$1" | wc -l | tr -d '[:space:]'
}

ac_is_medium_message() {
    local message="$1"
    [ "${#message}" -gt 280 ] || [ "$(ac_count_lines "$message")" -gt 4 ]
}

ac_is_long_message() {
    local message="$1"
    [ "${#message}" -gt 700 ] || [ "$(ac_count_lines "$message")" -gt 8 ]
}

ac_should_materialize_message() {
    local message="$1"
    [ "${#message}" -gt 1200 ] || [ "$(ac_count_lines "$message")" -gt 18 ]
}

ac_materialize_message() {
    local agent_id="$1"
    local body="$2"
    local output_path
    output_path="${MANUAL_PROMPTS_DIR}/$(date '+%Y%m%d_%H%M%S')-${agent_id}-${RANDOM}.md"
    {
        printf '# %s\n' "$(ac_t 'materialized.title')"
        echo
        printf '%s\n' "$(ac_t_format 'materialized.meta_target' "agent_id=${agent_id}")"
        printf '%s\n' "$(ac_t 'materialized.meta_source')"
        printf '%s\n' "$(ac_t_format 'materialized.meta_created_at' "created_at=$(ac_now_iso)")"
        echo
        printf '## %s\n' "$(ac_t 'materialized.user_message_heading')"
        echo
        printf '%s\n' "$body"
        echo
    } > "$output_path"
    printf '%s\n' "$output_path"
}

ac_prepare_message_for_delivery() {
    local agent_id="$1"
    local message="$2"
    local reset_prefix="" body="$message" materialized_path

    if [ "$message" = "$AC_RESET_COMMAND" ]; then
        printf '%s\n' "$message"
        return
    fi

    if [[ "$message" == "$AC_RESET_COMMAND"$'\n'* ]]; then
        reset_prefix="${AC_RESET_COMMAND}"$'\n'
        body="${message#"$AC_RESET_COMMAND"$'\n'}"
    elif [[ "$message" == "$AC_RESET_COMMAND"$'\r\n'* ]]; then
        reset_prefix="${AC_RESET_COMMAND}"$'\r\n'
        body="${message#"$AC_RESET_COMMAND"$'\r\n'}"
    fi

    if ! ac_should_materialize_message "$body"; then
        printf '%s\n' "$message"
        return
    fi

    materialized_path="$(ac_materialize_message "$agent_id" "$body")"
    printf '%s%s\n' "$reset_prefix" "$(ac_t_format 'message.materialized_notice' "path=${materialized_path}")"
}

ac_send_keys_with_enter() {
    local target="$1"
    local text="$2"
    local runtime="${3:-codex}"
    local delay="0.2"

    if ac_is_long_message "$text"; then
        delay="0.9"
    elif ac_is_medium_message "$text"; then
        delay="0.5"
    fi

    tmux send-keys -t "$target" -l "$text"
    sleep "$delay"
    tmux send-keys -t "$target" C-m

    if [ "$runtime" = "codex" ] && ac_is_long_message "$text"; then
        sleep 0.8
        tmux send-keys -t "$target" C-m
    fi
}

ac_send_direct_message() {
    local agent_id="$1"
    local raw_message="$2"
    local target message body runtime

    target=$(ac_agent_tmux_target "$agent_id")
    runtime="$(ac_agent_runtime "$agent_id")"
    message="$(ac_prepare_message_for_delivery "$agent_id" "$raw_message")"

    if [ "$message" = "$AC_RESET_COMMAND" ]; then
        ac_send_keys_with_enter "$target" "$AC_RESET_COMMAND" "$runtime"
        return 0
    fi

    if [[ "$message" == "$AC_RESET_COMMAND"$'\n'* ]]; then
        body="${message#"$AC_RESET_COMMAND"$'\n'}"
        ac_send_keys_with_enter "$target" "$AC_RESET_COMMAND" "$runtime"
        sleep 2
        ac_send_keys_with_enter "$target" "$body" "$runtime"
        return 0
    fi

    ac_send_keys_with_enter "$target" "$message" "$runtime"
}

ac_dashboard_url() {
    printf 'http://127.0.0.1:%s/\n' "$AC_UI_PORT"
}

ac_is_wsl() {
    if [ -n "${WSL_INTEROP:-}" ] || [ -n "${WSL_DISTRO_NAME:-}" ]; then
        return 0
    fi

    grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null
}

ac_open_browser() {
    local url="$1"

    if ac_is_wsl; then
        if command -v cmd.exe >/dev/null 2>&1; then
            cmd.exe /c start "" "$url" >/dev/null 2>&1 && return 0
        fi
        if command -v powershell.exe >/dev/null 2>&1; then
            powershell.exe -NoProfile -Command "Start-Process '$url'" >/dev/null 2>&1 && return 0
        fi
        if command -v wslview >/dev/null 2>&1; then
            wslview "$url" >/dev/null 2>&1 && return 0
        fi
    fi

    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1 || true
    elif command -v open >/dev/null 2>&1; then
        open "$url" >/dev/null 2>&1 || true
    fi
}

ac_codex_launch_command_for_agent() {
    local agent_id="$1"
    local quoted_workdir quoted_home command model
    printf -v quoted_workdir '%q' "$AC_AGENT_WORKING_DIR"
    printf -v quoted_home '%q' "$AC_CODEX_HOME"

    command="cd ${quoted_workdir} && CODEX_HOME=${quoted_home} codex"
    model="$(ac_agent_model "$agent_id")"
    if [ -n "$model" ]; then
        command="${command} --model $(printf '%q' "$model")"
    fi
    if [ "$AC_CODEX_DANGEROUS" = "1" ]; then
        command="${command} --dangerously-bypass-approvals-and-sandbox"
    fi
    printf '%s\n' "$command"
}

ac_claude_launch_command_for_agent() {
    local agent_id="$1"
    local quoted_workdir command model
    printf -v quoted_workdir '%q' "$AC_AGENT_WORKING_DIR"

    command="cd ${quoted_workdir} && claude"
    model="$(ac_agent_model "$agent_id")"
    if [ -n "$model" ]; then
        command="${command} --model $(printf '%q' "$model")"
    fi
    if [ "$AC_CODEX_DANGEROUS" = "1" ]; then
        command="${command} --dangerously-skip-permissions"
    fi
    printf '%s\n' "$command"
}

ac_agent_launch_command() {
    local agent_id="$1"
    case "$(ac_agent_runtime "$agent_id")" in
        codex)
            ac_codex_launch_command_for_agent "$agent_id"
            ;;
        claude)
            ac_claude_launch_command_for_agent "$agent_id"
            ;;
        *)
            ac_fail "未対応 runtime です: $(ac_agent_runtime "$agent_id") / ${agent_id}"
            ;;
    esac
}

ac_agent_startup_delay_seconds() {
    printf '1\n'
}

ac_require_runtime_command() {
    case "$1" in
        codex) command -v codex >/dev/null 2>&1 || ac_fail "Required command was not found: codex" ;;
        claude) command -v claude >/dev/null 2>&1 || ac_fail "Required command was not found: claude" ;;
        *) ac_fail "未対応 runtime です: $1" ;;
    esac
}

ac_require_runtime_auth() {
    case "$1" in
        codex)
            mkdir -p "$AC_CODEX_HOME"
            if ! CODEX_HOME="$AC_CODEX_HOME" codex login status >/dev/null 2>&1; then
                ac_fail "Codex authentication was not found. Run 'CODEX_HOME=${AC_CODEX_HOME} codex login' first."
            fi
            ;;
        claude)
            if ! claude auth status >/dev/null 2>&1; then
                ac_fail "Claude authentication was not found. Run 'claude auth login' first."
            fi
            ;;
        *)
            ac_fail "未対応 runtime です: $1"
            ;;
    esac
}

ac_required_runtimes() {
    local agent_id runtime
    declare -A seen=()
    for agent_id in "${AC_AGENT_IDS[@]}"; do
        runtime="$(ac_agent_runtime "$agent_id")"
        [ -n "$runtime" ] || continue
        if [ -n "${seen[$runtime]:-}" ]; then
            continue
        fi
        seen["$runtime"]=1
        printf '%s\n' "$runtime"
    done
}

ac_render_coordinator_boot_message() {
    local common_role="$1"
    local coordinator_role="$2"
    ac_t_format "message.coordinator_boot" \
        "common_role=${common_role}" \
        "coordinator_role=${coordinator_role}" \
        "repo_root=${AC_REPO_ROOT}" \
        "dashboard_url=$(ac_dashboard_url)" \
        "write_command_path=${AC_REPO_ROOT}/scripts/write-command-task.sh"
}

ac_render_task_author_boot_message() {
    local common_role="$1"
    local task_author_role="$2"
    ac_t_format "message.task_author_boot" \
        "common_role=${common_role}" \
        "task_author_role=${task_author_role}" \
        "personas_manifest=${ROLE_PERSONAS_MARKDOWN_FILE}" \
        "repo_root=${AC_REPO_ROOT}" \
        "dashboard_url=$(ac_dashboard_url)"
}

ac_render_worker_boot_message() {
    local worker_id="$1"
    local worker_role="$2"
    local persona_role="$3"
    local common_role="$4"
    ac_t_format "message.worker_boot" \
        "common_role=${common_role}" \
        "worker_role=${worker_role}" \
        "persona_role=${persona_role}" \
        "worker_id=${worker_id}" \
        "repo_root=${AC_REPO_ROOT}" \
        "dashboard_url=$(ac_dashboard_url)"
}

ac_render_reinject_message() {
    local role_path="$1"
    local extra_block="${2:-}"
    ac_t_format "message.reinject" \
        "common_role=$(ac_role_path common)" \
        "role_path=${role_path}" \
        "repo_root=${AC_REPO_ROOT}" \
        "extra_block=${extra_block}"
}

ac_render_personas_manifest_line() {
    ac_t_format "message.personas_manifest_line" "personas_manifest=${ROLE_PERSONAS_MARKDOWN_FILE}"
}

ac_render_default_persona_line() {
    local persona_role="$1"
    ac_t_format "message.default_persona_line" "persona_role=${persona_role}"
}

ac_render_worker_notify_message() {
    local persona="$1"
    local task_id="$2"
    local task_file="${3:-}"
    local worker_role persona_role common_role

    worker_role="$(ac_role_path worker)"
    persona_role="$(ac_role_path "$persona")"
    common_role="$(ac_role_path common)"

    ac_t_format "message.worker_task" \
        "common_role=${common_role}" \
        "worker_role=${worker_role}" \
        "persona_role=${persona_role}" \
        "task_file=${task_file}" \
        "task_id=${task_id}" \
        "repo_root=${AC_REPO_ROOT}" \
        "task_finish_path=${AC_REPO_ROOT}/scripts/task-finish.sh" \
        "create_question_path=${AC_REPO_ROOT}/scripts/create-question.sh"
}

ac_render_command_notify_message() {
    local command_file="$1"
    local command_text="$2"
    ac_t_format "message.command_pending" \
        "task_author_role=$(ac_role_path task_author)" \
        "command_file=${command_file}" \
        "command_text=${command_text}"
}

ac_render_open_question_notify_message() {
    local question_id="$1"
    local task_id="$2"
    local asked_by="$3"
    local question_file="$4"
    local question="$5"
    ac_t_format "message.question_open" \
        "question_id=${question_id}" \
        "task_id=${task_id}" \
        "asked_by=${asked_by}" \
        "question_file=${question_file}" \
        "question=${question}"
}

ac_render_report_research_complete_message() {
    local task_id="$1"
    local persona="$2"
    local result="$3"
    local command_id="$4"
    local artifact="$5"
    ac_t_format "message.report_research_complete" \
        "task_id=${task_id}" \
        "persona=${persona}" \
        "result=${result}" \
        "command_id=${command_id}" \
        "artifact=${artifact}"
}

ac_render_report_research_summary_message() {
    local summary_lines="$1"
    ac_t_format "message.report_research_summary" \
        "task_author_role=$(ac_role_path task_author)" \
        "summary_lines=${summary_lines}"
}

ac_render_report_tester_update_message() {
    local task_id="$1"
    local result="$2"
    local command_id="$3"
    ac_t_format "message.report_tester_update" \
        "task_id=${task_id}" \
        "result=${result}" \
        "command_id=${command_id}"
}

ac_render_report_reviewer_update_message() {
    local task_id="$1"
    local result="$2"
    local review_decision="$3"
    local command_id="$4"
    ac_t_format "message.report_reviewer_update" \
        "task_id=${task_id}" \
        "result=${result}" \
        "review_decision=${review_decision}" \
        "command_id=${command_id}"
}

ac_render_review_group_update_message() {
    local task_id="$1"
    local result="$2"
    local review_decision="$3"
    local command_id="$4"
    local reviewer_count="$5"
    local note_path="$6"
    ac_t_format "message.report_review_group_update" \
        "task_id=${task_id}" \
        "result=${result}" \
        "review_decision=${review_decision}" \
        "command_id=${command_id}" \
        "reviewer_count=${reviewer_count}" \
        "note_path=${note_path}"
}

ac_render_report_generic_complete_message() {
    local task_id="$1"
    local persona="$2"
    local task_type="$3"
    local result="$4"
    local command_id="$5"
    ac_t_format "message.report_generic_complete" \
        "task_id=${task_id}" \
        "persona=${persona}" \
        "task_type=${task_type}" \
        "result=${result}" \
        "command_id=${command_id}"
}

ac_capture_tmux_snapshot() {
    local agent_id="$1"
    local target="$2"
    local output_file="${TMUX_SNAPSHOT_DIR}/${agent_id}.yaml"
    local history history_code running now_iso

    now_iso=$(ac_now_iso)
    if history=$(tmux capture-pane -t "$target" -p -S -120 2>/dev/null); then
        running=1
        history_code=""
    else
        history=""
        history_code="tmux_unavailable"
        running=0
    fi

    {
        echo "agent_id: \"$(ac_escape_yaml_double_quoted "$agent_id")\""
        echo "tmux_target: \"$(ac_escape_yaml_double_quoted "$target")\""
        echo "running: \"${running}\""
        echo "captured_at: \"$(ac_escape_yaml_double_quoted "$now_iso")\""
        echo "history_code: \"$(ac_escape_yaml_double_quoted "$history_code")\""
        echo "history: |"
        printf '%s\n' "$history" | sed 's/^/  /'
    } | ac_atomic_write_stdin "$output_file"
}

ac_init_runtime_files() {
    ac_ensure_runtime_dirs
    ac_write_runtime_env
    ac_generate_role_manifest

    cat > "${COMMANDS_DIR}/command.yaml" <<'CMD'
id: ""
command: |
  
priority: "high"
status: "idle"
assigned_to: "task_author"
created_at: ""
updated_at: ""
CMD

    local worker_id persona
    while IFS= read -r worker_id; do
        persona="$(ac_worker_persona "$worker_id")"
        cat > "${REPORTS_DIR}/${worker_id}_report.yaml" <<EOF_REPORT
worker_id: "${worker_id}"
task_id: ""
persona: "${persona}"
type: ""
command_id: ""
status: "idle"
result: ""
summary: |
  

details: |
  

review_decision: ""
rework_targets: []
findings: []
completed_at: ""
EOF_REPORT
    done < <(ac_worker_ids)

    cat > "${RUNTIME_DIR}/review_cycle_state.env" <<'STATE'
REVIEW_CYCLE_ID=0
REVIEW_CYCLE_ACTIVE=0
REVIEW_TARGET_SIGNATURE=""
REVIEW_LAST_APPROVED_SIGNATURE=""
REVIEW_CYCLE_STARTED_AT_EPOCH=0
STATE
}

ac_load_config
ac_load_i18n
