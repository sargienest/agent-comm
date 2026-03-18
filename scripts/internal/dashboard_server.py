#!/usr/bin/env python3

from __future__ import annotations

import argparse
import configparser
import hashlib
import json
import os
import pathlib
import re
import subprocess
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
from typing import Any

AGENT_SECTION_ORDER = [
    "coordinator",
    "task_author",
    "dispatcher",
    "investigation",
    "analyst",
    "tester",
    "implementer",
    "reviewer",
]
CONTROL_AGENT_SECTIONS = {"coordinator", "task_author", "dispatcher"}
POOL_AGENT_SECTIONS = {"implementer", "reviewer"}


def count_indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def parse_scalar(raw: str) -> Any:
    text = raw.strip()
    if text == "[]":
        return []
    if text in {"null", "~"}:
        return ""
    if text.startswith('"') and text.endswith('"'):
        return text[1:-1].replace('\\"', '"').replace("\\\\", "\\")
    if text.startswith("'") and text.endswith("'"):
        return text[1:-1]
    return text


def parse_list(lines: list[str], index: int, indent: int) -> tuple[list[Any], int]:
    items: list[Any] = []
    while index < len(lines):
        line = lines[index]
        if not line.strip():
            index += 1
            continue
        current_indent = count_indent(line)
        if current_indent < indent:
            break
        if current_indent != indent:
            break
        stripped = line.strip()
        if not stripped.startswith("- "):
            break
        items.append(parse_scalar(stripped[2:]))
        index += 1
    return items, index


def parse_mapping(lines: list[str], index: int = 0, indent: int = 0) -> tuple[dict[str, Any], int]:
    result: dict[str, Any] = {}
    while index < len(lines):
        line = lines[index]
        if not line.strip():
            index += 1
            continue
        current_indent = count_indent(line)
        if current_indent < indent:
            break
        if current_indent != indent:
            break
        stripped = line.strip()
        if stripped.startswith("- "):
            break
        if ":" not in stripped:
            index += 1
            continue
        key, remainder = stripped.split(":", 1)
        key = key.strip()
        remainder = remainder.lstrip()
        index += 1
        if remainder == "|":
            block_lines: list[str] = []
            while index < len(lines):
                block_line = lines[index]
                if not block_line.strip():
                    block_lines.append("")
                    index += 1
                    continue
                block_indent = count_indent(block_line)
                if block_indent <= current_indent:
                    break
                block_lines.append(block_line[current_indent + 2 :])
                index += 1
            result[key] = "\n".join(block_lines).rstrip()
            continue
        if remainder == "":
            lookahead = index
            while lookahead < len(lines) and not lines[lookahead].strip():
                lookahead += 1
            if lookahead >= len(lines) or count_indent(lines[lookahead]) <= current_indent:
                result[key] = ""
                continue
            if lines[lookahead].strip().startswith("- "):
                parsed_list, index = parse_list(lines, lookahead, current_indent + 2)
                result[key] = parsed_list
                continue
            parsed_map, index = parse_mapping(lines, lookahead, current_indent + 2)
            result[key] = parsed_map
            continue
        result[key] = parse_scalar(remainder)
    return result, index


def parse_yaml_file(path: pathlib.Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        content = path.read_text(encoding="utf-8")
    except OSError:
        return {}
    parsed, _ = parse_mapping(content.splitlines())
    return parsed


def normalize_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    if isinstance(value, int):
        return value == 1
    return False


def iso_now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat()


def short_text(value: str, limit: int) -> str:
    compact = " ".join(value.split())
    if len(compact) <= limit:
        return compact
    return compact[: limit - 1] + "…"


def read_ini(repo_root: pathlib.Path) -> dict[str, Any]:
    parser = configparser.ConfigParser(interpolation=None)
    ini_path = repo_root / "agent-comm.ini"
    if ini_path.is_file():
        parser.read(ini_path, encoding="utf-8")
    return {
        "session_name": parser.get("tmux", "session_name", fallback="agent-comm"),
        "ui_port": parser.getint("ui", "port", fallback=43861),
        "runtime_language": parser.get("runtime", "language", fallback="").strip().lower(),
        "ui_language": parser.get("ui", "language", fallback="").strip().lower(),
    }


def agent_section_label(section: str) -> str:
    labels = {
        "coordinator": "Coordinator",
        "task_author": "Task Author",
        "dispatcher": "Dispatcher",
        "investigation": "Investigation",
        "analyst": "Analyst",
        "tester": "Tester",
        "implementer": "Implementer",
        "reviewer": "Reviewer",
    }
    return labels.get(section, section)


def read_agent_definitions(repo_root: pathlib.Path) -> list[dict[str, Any]]:
    parser = configparser.ConfigParser(interpolation=None)
    ini_path = repo_root / "agents.ini"
    if ini_path.is_file():
        parser.read(ini_path, encoding="utf-8")

    definitions: list[dict[str, Any]] = []
    for section in AGENT_SECTION_ORDER:
        runtime = parser.get(section, "runtime", fallback="").strip().lower() or "codex"
        model = parser.get(section, "model", fallback="").strip()
        count = 1
        if section in POOL_AGENT_SECTIONS:
            count = max(parser.getint(section, "count", fallback=1), 1)

        label = agent_section_label(section)
        if section in CONTROL_AGENT_SECTIONS:
            definitions.append(
                {
                    "id": section,
                    "section": section,
                    "label": label,
                    "kind": "control",
                    "runtime": runtime,
                    "model": model,
                    "persona": "",
                }
            )
            continue

        if section in POOL_AGENT_SECTIONS:
            for index in range(1, count + 1):
                definitions.append(
                    {
                        "id": f"{section}{index}",
                        "section": section,
                        "label": f"{label} {index}",
                        "kind": "worker",
                        "runtime": runtime,
                        "model": model,
                        "persona": section,
                    }
                )
            continue

        definitions.append(
            {
                "id": section,
                "section": section,
                "label": label,
                "kind": "worker",
                "runtime": runtime,
                "model": model,
                "persona": section,
            }
        )

    return definitions


def read_simple_env(path: pathlib.Path) -> dict[str, str]:
    if not path.is_file():
        return {}

    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def read_json_file(path: pathlib.Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def build_i18n_catalog(repo_root: pathlib.Path) -> dict[str, Any]:
    config = read_ini(repo_root)
    i18n_dir = repo_root / "i18n" / "dashboard"
    items: list[dict[str, str]] = []

    if i18n_dir.is_dir():
        for file_path in sorted(i18n_dir.glob("*.json")):
            payload = read_json_file(file_path)
            meta = payload.get("meta", {})
            if not isinstance(meta, dict):
                meta = {}

            code = str(meta.get("code", file_path.stem)).strip().lower()
            if not code:
                continue

            label = str(meta.get("label", code)).strip() or code
            native_label = str(meta.get("native_label", label)).strip() or label
            locale = str(meta.get("locale", code)).strip() or code

            items.append(
                {
                    "code": code,
                    "label": label,
                    "native_label": native_label,
                    "locale": locale,
                }
            )

    available_codes = [item["code"] for item in items]
    configured_default = (
        str(config.get("ui_language", "")).strip().lower()
        or str(config.get("runtime_language", "")).strip().lower()
    )

    def resolve_language(value: str) -> str:
        normalized = str(value or "").strip().lower().replace("_", "-")
        if not normalized:
            return ""
        if normalized in available_codes:
            return normalized
        base_code = normalized.split("-", 1)[0]
        if base_code in available_codes:
            return base_code
        return ""

    default_language = (
        resolve_language(configured_default)
        or resolve_language("en")
        or (available_codes[0] if available_codes else "en")
    )
    return {
        "items": items,
        "default_language": default_language,
    }


KNOWN_TMUX_SEND_ERROR_CODES = {
    "invalid_json",
    "invalid_request",
    "agent_required",
    "message_required",
    "agent_and_message_required",
    "invalid_agent",
    "tmux_target_missing",
    "tmux_unavailable",
    "send_failed",
}


def normalize_machine_code(value: str) -> str:
    normalized = str(value or "").strip().lower().replace("-", "_")
    normalized = re.sub(r"[^a-z0-9_]+", "_", normalized)
    normalized = re.sub(r"_+", "_", normalized).strip("_")
    if normalized in KNOWN_TMUX_SEND_ERROR_CODES:
        return normalized
    return "send_failed"


def tmux_send_error_status(error_code: str) -> HTTPStatus:
    if error_code in {"invalid_json", "invalid_request", "agent_required", "message_required", "agent_and_message_required", "invalid_agent"}:
        return HTTPStatus.BAD_REQUEST
    if error_code == "tmux_target_missing":
        return HTTPStatus.CONFLICT
    if error_code == "tmux_unavailable":
        return HTTPStatus.SERVICE_UNAVAILABLE
    return HTTPStatus.INTERNAL_SERVER_ERROR


def tmux_send_error_payload(error_code: str) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "ok": False,
        "error": error_code,
        "error_code": error_code,
        "message": error_code,
    }

    return payload


class SnapshotBuilder:
    def __init__(self, repo_root: pathlib.Path):
        self.repo_root = repo_root
        self.runtime_root = repo_root / ".runtime"
        self.config = read_ini(repo_root)
        self.agent_definitions = read_agent_definitions(repo_root)

    def tmux_session_running(self, session_name: str) -> bool:
        session = str(session_name or "").strip()
        if not session:
            return False
        try:
            result = subprocess.run(
                ["tmux", "has-session", "-t", session],
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError:
            return False
        return result.returncode == 0

    def latest_mtime_iso(self) -> str | None:
        latest = 0.0
        if not self.runtime_root.is_dir():
            return None
        for entry in self.runtime_root.rglob("*"):
            if entry.is_file():
                latest = max(latest, entry.stat().st_mtime)
        if latest == 0:
            return None
        return datetime.fromtimestamp(latest, timezone.utc).astimezone().isoformat()

    def count_yaml_files(self, directory: pathlib.Path) -> int:
        if not directory.is_dir():
            return 0
        return len(list(directory.glob("*.yaml")))

    def collect_items(self, base_path: pathlib.Path, statuses: list[str], limit: int) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        for status in statuses:
            for file_path in (base_path / status).glob("*.yaml"):
                data = parse_yaml_file(file_path)
                depends_on = data.get("depends_on", [])
                depends_on_count = len(depends_on) if isinstance(depends_on, list) else 0
                items.append(
                    {
                        "id": data.get("id", file_path.stem),
                        "title": data.get("title", ""),
                        "description": data.get("description", ""),
                        "type": data.get("type", ""),
                        "persona": data.get("persona", ""),
                        "status": data.get("status", status),
                        "result": data.get("result", ""),
                        "assigned_to": data.get("assigned_to", ""),
                        "command_id": data.get("command_id", ""),
                        "result_artifact_path": data.get("result_artifact_path", ""),
                        "rework_note_paths": data.get("rework_note_paths", []),
                        "blocked_reason": data.get("blocked_reason", ""),
                        "depends_on": depends_on if isinstance(depends_on, list) else [],
                        "write_files": data.get("write_files", []),
                        "read_files": data.get("read_files", []),
                        "depends_on_count": depends_on_count,
                        "created_at": data.get("created_at", ""),
                        "updated_at": data.get("updated_at", ""),
                        "completed_at": data.get("completed_at", ""),
                        "_sort_time": file_path.stat().st_mtime,
                    }
                )
        items.sort(key=lambda item: item["_sort_time"], reverse=True)
        for item in items:
            item.pop("_sort_time", None)
        return items[:limit]

    def build_runtime(self) -> dict[str, Any]:
        current = parse_yaml_file(self.runtime_root / "status" / "current.yaml")
        review_cycle = read_simple_env(self.runtime_root / "runtime" / "review_cycle_state.env")
        session_name = str(current.get("session", self.config["session_name"]))
        session_running = self.tmux_session_running(session_name)
        agent_meta: dict[str, dict[str, str]] = {}
        workers_map = current.get("workers", {})
        if not isinstance(workers_map, dict):
            workers_map = {}

        workers: list[dict[str, str]] = []
        for definition in self.agent_definitions:
            agent_id = str(definition["id"])
            agent_meta[agent_id] = {
                "runtime": str(definition.get("runtime", "")),
                "model": str(definition.get("model", "")),
            }
            if definition.get("kind") != "worker":
                continue
            worker_id = agent_id
            snapshot = parse_yaml_file(self.runtime_root / "status" / "tmux" / f"{worker_id}.yaml")
            state = str(workers_map.get(worker_id, "idle"))
            if not session_running or (snapshot and not normalize_bool(snapshot.get("running", "0"))):
                state = "offline"
            workers.append(
                {
                    "id": worker_id,
                    "label": str(definition.get("label", worker_id)),
                    "section": str(definition.get("section", "")),
                    "runtime": str(definition.get("runtime", "")),
                    "model": str(definition.get("model", "")),
                    "persona": str(definition.get("persona", "")),
                    "state": state,
                }
            )

        def resolved_state(agent_id: str, fallback_key: str) -> str:
            fallback = str(current.get(fallback_key, "unknown"))
            snapshot = parse_yaml_file(self.runtime_root / "status" / "tmux" / f"{agent_id}.yaml")
            if not session_running or (snapshot and not normalize_bool(snapshot.get("running", "0"))):
                return "offline"
            return fallback

        return {
            "session": session_name,
            "started_at": current.get("started_at", ""),
            "coordinator": resolved_state("coordinator", "coordinator"),
            "task_author": resolved_state("task_author", "task_author"),
            "dispatcher": resolved_state("dispatcher", "dispatcher"),
            "agent_meta": agent_meta,
            "workers": workers,
            "review_cycle": {
                "cycle_id": review_cycle.get("REVIEW_CYCLE_ID", ""),
                "active": review_cycle.get("REVIEW_CYCLE_ACTIVE", "0") == "1",
                "target_signature": review_cycle.get("REVIEW_TARGET_SIGNATURE", ""),
                "last_approved_signature": review_cycle.get("REVIEW_LAST_APPROVED_SIGNATURE", ""),
            },
        }

    def build_events(self) -> list[dict[str, Any]]:
        files = sorted(
            (self.runtime_root / "reports" / "events").glob("*.yaml"),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
        events: list[dict[str, Any]] = []
        for file_path in files[:40]:
            data = parse_yaml_file(file_path)
            events.append(
                {
                    "id": file_path.stem,
                    "worker_id": data.get("worker_id", ""),
                    "task_id": data.get("task_id", ""),
                    "persona": data.get("persona", ""),
                    "type": data.get("type", ""),
                    "command_id": data.get("command_id", ""),
                    "status": data.get("status", ""),
                    "result": data.get("result", ""),
                    "review_decision": data.get("review_decision", ""),
                    "completed_at": data.get("completed_at", ""),
                    "summary": short_text(str(data.get("summary", "")), 280),
                }
            )
        return events

    def build_reports(self) -> list[dict[str, Any]]:
        files = sorted(
            [
                self.runtime_root / "reports" / f"{definition['id']}_report.yaml"
                for definition in self.agent_definitions
                if definition.get("kind") == "worker"
            ],
            key=lambda path: path.stat().st_mtime if path.is_file() else 0,
            reverse=True,
        )
        reports: list[dict[str, Any]] = []
        for file_path in files[:8]:
            if not file_path.is_file():
                continue
            data = parse_yaml_file(file_path)
            reports.append(
                {
                    "worker_id": data.get("worker_id", ""),
                    "task_id": data.get("task_id", ""),
                    "persona": data.get("persona", ""),
                    "type": data.get("type", ""),
                    "command_id": data.get("command_id", ""),
                    "status": data.get("status", ""),
                    "result": data.get("result", ""),
                    "review_decision": data.get("review_decision", ""),
                    "completed_at": data.get("completed_at", ""),
                    "summary": short_text(str(data.get("summary", "")), 160),
                }
            )
        return reports

    def build_command(self) -> dict[str, Any]:
        data = parse_yaml_file(self.runtime_root / "commands" / "command.yaml")
        return {
            "id": data.get("id", ""),
            "status": data.get("status", ""),
            "priority": data.get("priority", ""),
            "assigned_to": data.get("assigned_to", ""),
            "created_at": data.get("created_at", ""),
            "updated_at": data.get("updated_at", ""),
            "command": data.get("command", ""),
        }

    def build_snapshot(self) -> dict[str, Any]:
        payload = {
            "generated_at": iso_now(),
            "last_modified_at": self.latest_mtime_iso(),
            "root_exists": self.runtime_root.is_dir(),
            "agent_comm_root": str(self.repo_root),
            "runtime": self.build_runtime(),
            "tasks": {
                "counts": {
                    "pending": self.count_yaml_files(self.runtime_root / "tasks" / "pending"),
                    "inflight": self.count_yaml_files(self.runtime_root / "tasks" / "inflight"),
                    "done": self.count_yaml_files(self.runtime_root / "tasks" / "done"),
                    "blocked": self.count_yaml_files(self.runtime_root / "tasks" / "blocked"),
                },
                "items": self.collect_items(self.runtime_root / "tasks", ["inflight", "pending", "blocked", "done"], 20),
            },
            "reviews": {
                "counts": {
                    "pending": self.count_yaml_files(self.runtime_root / "reviews" / "pending"),
                    "inflight": self.count_yaml_files(self.runtime_root / "reviews" / "inflight"),
                    "done": self.count_yaml_files(self.runtime_root / "reviews" / "done"),
                },
                "items": self.collect_items(self.runtime_root / "reviews", ["inflight", "pending", "done"], 20),
            },
            "events": self.build_events(),
            "command": self.build_command(),
            "reports": self.build_reports(),
        }

        checksum_payload = dict(payload)
        checksum_payload.pop("generated_at", None)
        payload["checksum"] = hashlib.sha256(
            json.dumps(checksum_payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
        ).hexdigest()
        return payload

    def sanitize_history(self, history: str) -> str:
        normalized = history.replace("\r\n", "\n").replace("\r", "\n").rstrip()
        if not normalized:
            return ""
        lines = normalized.split("\n")
        if len(lines) >= 2:
            status = lines[-1].strip()
            prompt = lines[-2].strip()
            if ("·" in status or "•" in status) and "left" in status and (prompt.startswith("›") or prompt.startswith(">")):
                lines = lines[:-2]
        sanitized = "\n".join(lines).rstrip()
        return sanitized

    def build_tmux_snapshot(self) -> dict[str, Any]:
        agents: list[dict[str, Any]] = []
        runtime = self.build_runtime()
        session_name = str(runtime.get("session", self.config["session_name"]))
        session_running = self.tmux_session_running(session_name)
        state_map = {
            "coordinator": runtime["coordinator"],
            "task_author": runtime["task_author"],
            "dispatcher": runtime["dispatcher"],
        }
        for worker in runtime["workers"]:
            state_map[worker["id"]] = worker["state"]

        for definition in self.agent_definitions:
            agent_id = str(definition["id"])
            label = str(definition["label"])
            snapshot = parse_yaml_file(self.runtime_root / "status" / "tmux" / f"{agent_id}.yaml")
            running = normalize_bool(snapshot.get("running", "0"))
            history = self.sanitize_history(str(snapshot.get("history", "")))
            history_code = str(snapshot.get("history_code", "")).strip()
            if not session_running or not snapshot or not running:
                running = False
                history = ""
                history_code = "tmux_unavailable"
            elif not history_code and history == "__AC_TMUX_UNAVAILABLE__":
                history_code = "tmux_unavailable"
                history = ""
            agents.append(
                {
                    "id": agent_id,
                    "label": label,
                    "section": str(definition.get("section", "")),
                    "kind": str(definition.get("kind", "")),
                    "runtime": str(definition.get("runtime", "")),
                    "model": str(definition.get("model", "")),
                    "persona": str(definition.get("persona", "")),
                    "tmux_target": snapshot.get("tmux_target", ""),
                    "state": state_map.get(agent_id, "unknown"),
                    "running": running,
                    "history_code": history_code,
                    "history": history,
                    "captured_at": snapshot.get("captured_at", ""),
                }
            )
        return {
            "generated_at": iso_now(),
            "root_exists": self.runtime_root.is_dir(),
            "session": runtime.get("session", self.config["session_name"]),
            "agents": agents,
        }


class AgentCommHandler(SimpleHTTPRequestHandler):
    server_version = "agent-comm-dashboard/1.0"

    def __init__(self, *args: Any, directory: str, repo_root: pathlib.Path, **kwargs: Any) -> None:
        self.repo_root = repo_root
        self.builder = SnapshotBuilder(repo_root)
        super().__init__(*args, directory=directory, **kwargs)

    def log_message(self, format: str, *args: Any) -> None:
        return

    def send_json(self, status: int, payload: Any) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_json_file(self, path: pathlib.Path) -> None:
        if not path.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        data = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/i18n/catalog":
            self.send_json(HTTPStatus.OK, build_i18n_catalog(self.repo_root))
            return
        if parsed.path.startswith("/i18n/dashboard/") and parsed.path.endswith(".json"):
            file_name = pathlib.Path(parsed.path).name
            self.send_json_file(self.repo_root / "i18n" / "dashboard" / file_name)
            return
        if parsed.path == "/api/snapshot":
            self.send_json(HTTPStatus.OK, self.builder.build_snapshot())
            return
        if parsed.path == "/api/tmux/snapshot":
            self.send_json(HTTPStatus.OK, self.builder.build_tmux_snapshot())
            return
        if parsed.path == "/api/stream":
            self.handle_stream(parsed)
            return
        if parsed.path in {"/", "/index.html", "/dashboard", "/dashboard/", "/dashboard/index.html"}:
            self.path = "/index.html"
        return super().do_GET()

    def handle_stream(self, parsed: Any) -> None:
        query = parse_qs(parsed.query)
        last_checksum = ""
        if "last_checksum" in query and query["last_checksum"]:
            last_checksum = str(query["last_checksum"][0])

        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()

        current_snapshot = self.builder.build_snapshot()
        current_checksum = str(current_snapshot.get("checksum", ""))
        if current_checksum != last_checksum:
            self.wfile.write(b"event: snapshot\n")
            self.wfile.write(f"data: {json.dumps(current_snapshot, ensure_ascii=False)}\n\n".encode("utf-8"))
            self.wfile.flush()
            last_checksum = current_checksum

        try:
            for _ in range(12):
                next_snapshot = self.builder.build_snapshot()
                next_checksum = str(next_snapshot.get("checksum", ""))
                if next_checksum != last_checksum:
                    self.wfile.write(b"event: snapshot\n")
                    self.wfile.write(f"data: {json.dumps(next_snapshot, ensure_ascii=False)}\n\n".encode("utf-8"))
                    self.wfile.flush()
                    last_checksum = next_checksum
                else:
                    self.wfile.write(b"event: heartbeat\n")
                    self.wfile.write(f"data: {json.dumps({'generated_at': iso_now()}, ensure_ascii=False)}\n\n".encode("utf-8"))
                    self.wfile.flush()
                import time
                time.sleep(2)
            self.wfile.write(b"event: close\n")
            self.wfile.write(b"data: {}\n\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            return

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path != "/api/tmux/send":
            self.send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not found", "message": "not found"})
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length) if content_length > 0 else b"{}"
        try:
            payload = json.loads(raw_body.decode("utf-8"))
        except json.JSONDecodeError:
            self.send_json(HTTPStatus.BAD_REQUEST, tmux_send_error_payload("invalid_json"))
            return

        agent = str(payload.get("agent", "") or payload.get("agent_id", "")).strip()
        message = str(payload.get("message", "")).strip()
        if not agent or not message:
            if not agent and not message:
                error_code = "agent_and_message_required"
            elif not agent:
                error_code = "agent_required"
            else:
                error_code = "message_required"
            self.send_json(HTTPStatus.BAD_REQUEST, tmux_send_error_payload(error_code))
            return

        command = [
            str(self.repo_root / "bin" / "agent-comm"),
            "send",
            "--agent",
            agent,
            "--message",
            message,
        ]
        env = dict(os.environ)
        env["AGENT_COMM_ERROR_FORMAT"] = "code"
        result = subprocess.run(command, capture_output=True, text=True, env=env)
        if result.returncode != 0:
            error_code = normalize_machine_code(result.stderr.strip() or result.stdout.strip() or "")
            self.send_json(tmux_send_error_status(error_code), tmux_send_error_payload(error_code))
            return

        self.send_json(HTTPStatus.OK, {"ok": True, "sent_at": iso_now(), "mode": "direct", "message": "sent"})


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--port", required=True, type=int)
    args = parser.parse_args()

    repo_root = pathlib.Path(args.repo_root).resolve()
    dashboard_dir = repo_root / "dashboard"

    def handler(*handler_args: Any, **handler_kwargs: Any) -> AgentCommHandler:
        return AgentCommHandler(*handler_args, directory=str(dashboard_dir), repo_root=repo_root, **handler_kwargs)

    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
