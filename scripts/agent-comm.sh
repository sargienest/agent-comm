#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

usage() {
    cat <<'USAGE'
Usage:
  bin/agent-comm validate-config
  bin/agent-comm start
  bin/agent-comm stop
  bin/agent-comm restart <coordinator|task_author|dispatcher|investigation|analyst|tester|implementers|reviewers|workers|implementerN|reviewerN|all>
  bin/agent-comm status
  bin/agent-comm dashboard [start] [--foreground]
  bin/agent-comm dashboard stop
  bin/agent-comm dashboard status
  bin/agent-comm send --agent <id> --message <text|file>
USAGE
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || ac_fail "Required command was not found: $1"
}

cmd_validate_config() {
    require_command tmux

    [ -d "$AC_AGENT_WORKING_DIR" ] || ac_fail "runtime.agent_working_dir was not found: ${AC_AGENT_WORKING_DIR}"
    mkdir -p "$AC_ROLES_PATH/en/personas" "$AC_ROLES_PATH/ja/personas"
    while IFS= read -r runtime; do
        [ -n "$runtime" ] || continue
        ac_require_runtime_command "$runtime"
    done < <(ac_required_runtimes)

    ac_generate_role_manifest

    local agent_id
    while IFS= read -r agent_id; do
        [ -n "$agent_id" ] || continue
        ac_validate_worker_id "$agent_id"
        ac_assert_persona_exists "$(ac_worker_persona "$agent_id")"
    done < <(ac_worker_ids)

    ac_write_runtime_env

    echo "config: ok"
    echo "repo_root: ${AC_REPO_ROOT}"
    echo "agents_ini: ${AC_AGENTS_INI_PATH}"
    echo "working_dir: ${AC_AGENT_WORKING_DIR}"
    echo "codex_home: ${AC_CODEX_HOME}"
    echo "runtime_language: ${AC_RUNTIME_LANGUAGE}"
    echo "session_name: ${AC_TMUX_SESSION_NAME}"
    echo "implementer_count: ${AC_SECTION_COUNT[implementer]}"
    echo "reviewer_count: ${AC_SECTION_COUNT[reviewer]}"
    echo "ui_auto_start: ${AC_UI_AUTO_START}"
    echo "ui_port: ${AC_UI_PORT}"
    echo "ui_language: ${AC_UI_LANGUAGE}"
}

stop_dashboard_server() {
    if [ -f "$DASHBOARD_PID_FILE" ]; then
        local pid
        pid="$(cat "$DASHBOARD_PID_FILE" 2>/dev/null || true)"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
        rm -f "$DASHBOARD_PID_FILE"
    fi
}

dashboard_server_running() {
    local pid

    if [ ! -f "$DASHBOARD_PID_FILE" ]; then
        return 1
    fi

    pid="$(cat "$DASHBOARD_PID_FILE" 2>/dev/null || true)"
    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    kill -0 "$pid" 2>/dev/null
}

start_dashboard_server() {
    require_command python3
    stop_dashboard_server

    if [ "${1:-}" = "--foreground" ]; then
        exec python3 "${SCRIPT_DIR}/internal/dashboard_server.py" --repo-root "$AC_REPO_ROOT" --port "$AC_UI_PORT"
    fi

    if command -v setsid >/dev/null 2>&1; then
        setsid python3 "${SCRIPT_DIR}/internal/dashboard_server.py" \
            --repo-root "$AC_REPO_ROOT" \
            --port "$AC_UI_PORT" \
            >"$DASHBOARD_LOG_FILE" 2>&1 < /dev/null &
    else
        nohup python3 "${SCRIPT_DIR}/internal/dashboard_server.py" \
            --repo-root "$AC_REPO_ROOT" \
            --port "$AC_UI_PORT" \
            >"$DASHBOARD_LOG_FILE" 2>&1 < /dev/null &
    fi
    echo "$!" > "$DASHBOARD_PID_FILE"
    sleep 1
    echo "dashboard: $(ac_dashboard_url)"
    if [ "$AC_UI_OPEN_BROWSER" = "1" ]; then
        ac_open_browser "$(ac_dashboard_url)"
    fi
}

cmd_start() {
    cmd_validate_config >/dev/null

    "${SCRIPT_DIR}/start-agents.sh"
    if ! "${SCRIPT_DIR}/launch-agents.sh"; then
        "${SCRIPT_DIR}/stop-agents.sh" >/dev/null 2>&1 || true
        exit 1
    fi
    if [ "$AC_UI_AUTO_START" = "1" ]; then
        start_dashboard_server
    fi
    cmd_status
}

cmd_stop() {
    stop_dashboard_server
    "${SCRIPT_DIR}/stop-agents.sh"
}

cmd_restart() {
    local target="${1:-}"
    [ -n "$target" ] || ac_fail "restart target is required."
    "${SCRIPT_DIR}/restart-agent.sh" "$target"
    if [ "$AC_UI_AUTO_START" = "1" ] && [ ! -f "$DASHBOARD_PID_FILE" ]; then
        start_dashboard_server
    fi
}

cmd_status() {
    local session_state="stopped"
    if tmux has-session -t "$AC_TMUX_SESSION_NAME" 2>/dev/null; then
        session_state="running"
    fi

    echo "session: ${session_state}"
    echo "tmux_session_name: ${AC_TMUX_SESSION_NAME}"
    echo "agents_ini: ${AC_AGENTS_INI_PATH}"
    echo "working_dir: ${AC_AGENT_WORKING_DIR}"
    echo "runtime_root: ${AC_RUNTIME_ROOT}"
    echo "implementer_count: ${AC_SECTION_COUNT[implementer]}"
    echo "reviewer_count: ${AC_SECTION_COUNT[reviewer]}"
    if dashboard_server_running; then
        echo "dashboard: $(ac_dashboard_url)"
    else
        if [ -f "$DASHBOARD_PID_FILE" ]; then
            rm -f "$DASHBOARD_PID_FILE"
        fi
        echo "dashboard: stopped"
    fi
}

cmd_dashboard_status() {
    if dashboard_server_running; then
        echo "dashboard: running"
        echo "url: $(ac_dashboard_url)"
        echo "pid: $(cat "$DASHBOARD_PID_FILE")"
    else
        if [ -f "$DASHBOARD_PID_FILE" ]; then
            rm -f "$DASHBOARD_PID_FILE"
        fi
        echo "dashboard: stopped"
    fi
}

cmd_dashboard() {
    local action="${1:-start}"

    case "$action" in
        start)
            shift || true
            start_dashboard_server "${1:-}"
            ;;
        stop)
            stop_dashboard_server
            echo "dashboard: stopped"
            ;;
        status)
            cmd_dashboard_status
            ;;
        --foreground)
            start_dashboard_server --foreground
            ;;
        *)
            ac_fail "Invalid dashboard argument: ${action}"
            ;;
    esac
}

cmd_send() {
    local agent_id="" message_arg="" message_text=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --agent)
                agent_id="${2:-}"
                shift 2
                ;;
            --message)
                message_arg="${2:-}"
                shift 2
                ;;
            *)
                ac_fail_with_code "invalid_request" "Invalid send argument: $1"
                ;;
        esac
    done

    [ -n "$agent_id" ] || ac_fail_with_code "agent_required" "--agent is required."
    [ -n "$message_arg" ] || ac_fail_with_code "message_required" "--message is required."

    if [ -f "$message_arg" ]; then
        message_text="$(cat "$message_arg")"
    else
        message_text="$message_arg"
    fi

    "${SCRIPT_DIR}/send-msg.sh" "$agent_id" "$message_text"
}

main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        validate-config) cmd_validate_config "$@" ;;
        start) cmd_start "$@" ;;
        stop) cmd_stop "$@" ;;
        restart) cmd_restart "$@" ;;
        status) cmd_status "$@" ;;
        dashboard) cmd_dashboard "$@" ;;
        send) cmd_send "$@" ;;
        -h|--help|help|'') usage ;;
        *) ac_fail "Unknown command: ${command}" ;;
    esac
}

main "$@"
