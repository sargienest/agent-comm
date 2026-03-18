ac_i18n_register "role_manifest.title" "利用可能な Persona"
ac_i18n_register "role_manifest.generated" "role scan から自動生成。"

ac_i18n_register "materialized.title" "Dashboard 指示"
ac_i18n_register "materialized.meta_target" "- target: {agent_id}"
ac_i18n_register "materialized.meta_source" "- source: agent-comm"
ac_i18n_register "materialized.meta_created_at" "- created_at: {created_at}"
ac_i18n_register "materialized.user_message_heading" "User Message"

ac_i18n_register "message.materialized_notice" $'指示ファイル: {path}\nこれを実施してください。'
ac_i18n_register "message.coordinator_boot" $'初期化メッセージです。これはユーザー依頼ではありません。\n以下を読んで役割を理解してください。\n- common: {common_role}\n- coordinator: {coordinator_role}\n\nagent-comm root: {repo_root}\ndashboard: {dashboard_url}\n\nこの boot message から command を作成しないでください。\n実際のユーザー指示が届いたら {write_command_path} で command を投入し、あとは待機してください。'
ac_i18n_register "message.task_author_boot" $'初期化メッセージです。これは command ではありません。\n以下を読んで役割を理解してください。\n- common: {common_role}\n- task_author: {task_author_role}\n- personas manifest: {personas_manifest}\n\nagent-comm root: {repo_root}\ndashboard: {dashboard_url}\n\nこの boot message から task を作成しないでください。\ncoordinator または dispatcher の指示があるまで待機してください。'
ac_i18n_register "message.worker_boot" $'初期化メッセージです。これは task ではありません。\n以下を読んで役割を理解してください。\n- common: {common_role}\n- worker: {worker_role}\n- default persona: {persona_role}\n\nworker id: {worker_id}\nagent-comm root: {repo_root}\ndashboard: {dashboard_url}\n\nこの boot message から作業を始めないでください。\ndispatcher から task file が届くまで待機してください。'
ac_i18n_register "message.reinject" $'+再注入です。以下を読み直してください。\n- common: {common_role}\n- role: {role_path}\n\nagent-comm root: {repo_root}\n{extra_block}'
ac_i18n_register "message.personas_manifest_line" "personas manifest: {personas_manifest}"
ac_i18n_register "message.default_persona_line" "default persona: {persona_role}"
ac_i18n_register "message.worker_task" $'以下を読んで作業してください。\n- common: {common_role}\n- worker role: {worker_role}\n- persona: {persona_role}\n\ntask file: {task_file}\ntask id: {task_id}\nagent-comm root: {repo_root}\n\n完了時は {task_finish_path} を使ってください。\n質問が必要なら {create_question_path} を使ってください。'
ac_i18n_register "message.command_pending" $'以下を読んでから続行してください。\n- common: {common_role}\n- task_author: {task_author_role}\n- personas manifest: {personas_manifest}\n\ncommand file: {command_file}\nagent-comm root: {repo_root}\ndashboard: {dashboard_url}\n\nまず investigation と analyst の調査タスクを配布し、完了後の `result_artifact_path` を基に実装タスクへ分解してください。\n\ncommand:\n{command_text}'
ac_i18n_register "message.question_open" $'ユーザー確認が必要です。\nquestion_id: {question_id}\ntask_id: {task_id}\nasked_by: {asked_by}\nfile: {question_file}\n\n{question}'
ac_i18n_register "message.report_research_complete" $'調査タスクが完了しました。\ntask_id: {task_id}\npersona: {persona}\nresult: {result}\ncommand_id: {command_id}\nartifact: {artifact}\n\n成果物は確認してください。ただし、この command の `investigation` と `analyst` が両方完了するまでは implementation task を作成しないでください。'
ac_i18n_register "message.report_research_summary" $'以下を読んでから続行してください。\n- common: {common_role}\n- task_author: {task_author_role}\n- personas manifest: {personas_manifest}\n\nagent-comm root: {repo_root}\ndashboard: {dashboard_url}\n\ninvestigation / analyst の完了タスクがあります。以下の結果ファイルを確認して次の実装タスクを分解してください。\n{summary_lines}'
ac_i18n_register "message.report_tester_update" $'テスト実行タスクが更新されました。\ntask_id: {task_id}\nresult: {result}\ncommand_id: {command_id}\n\n必要なら次の review タスクを作成してください。'
ac_i18n_register "message.report_reviewer_update" $'review タスクが更新されました。\ntask_id: {task_id}\nresult: {result}\nreview_decision: {review_decision}\ncommand_id: {command_id}\n\n必要なら rework を作成してください。'
ac_i18n_register "message.report_review_group_update" $'全体レビューが完了しました。\ntask_id: {task_id}\nresult: {result}\nreview_decision: {review_decision}\ncommand_id: {command_id}\nreviewer_count: {reviewer_count}\nrework_note: {note_path}\n\n必要なら次の rework を作成してください。'
ac_i18n_register "message.report_generic_complete" $'タスク完了通知です。\ntask_id: {task_id}\npersona: {persona}\ntype: {task_type}\nresult: {result}\ncommand_id: {command_id}'
ac_i18n_register "stop.session_missing_cleared" "セッション '{session}' は存在しません。状態をクリアしました。"
ac_i18n_register "stop.session_detached_started" "セッション '{session}' の停止をバックグラウンドで開始しました。"
ac_i18n_register "stop.session_stop_failed" "セッション '{sessions}' の停止に失敗しました。"
ac_i18n_register "stop.session_stopped" "セッション '{sessions}' を停止しました。"
ac_i18n_register "task.pre_review_gate.title" "プレレビュー テストゲート ({short_sig})"
ac_i18n_register "task.pre_review_gate.description" $'全体レビュー前のテストゲートです。現在の実装差分に対してテストを実行し、失敗が今回変更に起因する場合は修正して再実行してください。\n\n完了条件:\n- 必要なテストを実行し、結果を summary / details に残すこと\n- 今回変更に起因する失敗があれば修正まで完了させること\n- 不明点があれば推測せず create-question.sh を使うこと'
ac_i18n_register "task.review_rework.title" "レビュー指摘対応 (cycle {cycle_id})"
ac_i18n_register "task.review_rework.description.with_note" $'全体レビュー cycle {cycle_id} で requestchange が出ました。\nrework_note_path を確認して全指摘を反映してください。\n完了後は dispatcher が再度 tester と overall review を回します。'
ac_i18n_register "task.review_rework.description.without_note" $'全体レビュー cycle {cycle_id} で requestchange が出ました。\n全指摘を反映して実装を更新してください。\n完了後は dispatcher が再度 tester と overall review を回します。'
ac_i18n_register "task.overall_review.title" "全体レビュー cycle {cycle_id} ({short_sig})"
ac_i18n_register "task.overall_review.description" $'全体差分をレビューし、approve か requestchange を判定してください。\nrequestchange の場合は summary / details / rework_targets / findings を正しく記載してください。\nrequestchange は dispatcher が集約して再作業を再配布します。'
ac_i18n_register "command.pending_fallback" "command.yaml を確認してください。"
ac_i18n_register "cli.error.unknown_argument" "エラー: 不明な引数です: {arg}"
ac_i18n_register "common.error.role_frontmatter_missing" "role frontmatter の {field} がありません: {role_file}"
ac_i18n_register "common.error.unsupported_runtime" "未対応 runtime です: {runtime}"
ac_i18n_register "start.error.session_exists" "セッション '{session}' は既に存在します。"
ac_i18n_register "launch.error.session_missing" "tmux セッションが存在しません: {session}"
ac_i18n_register "usage.write_task" $'使い方:\n  ./scripts/write-task.sh \\\n    --persona <persona> \\\n    --title <title> \\\n    --description <description> \\\n    --write-file <path> [--write-file <path> ...] \\\n    [--id <task_id>] \\\n    [--type <implementation|investigation|analyst|rework|review>] \\\n    [--depends-on <task_id>]... \\\n    [--read-file <path>]... \\\n    [--exclusive-group <group>] \\\n    [--assigned-to <implementer1|reviewer1|investigation|analyst|tester>] \\\n    [--command-id <command_id>] \\\n    [--result-artifact-path <path>] \\\n    [--output <path>]\n\n例:\n  ./scripts/write-task.sh \\\n    --id task_refactor_dispatcher_001 \\\n    --type implementation \\\n    --persona implementer \\\n    --title "dispatcherの競合ロック追加" \\\n    --description "write_files ロックに対応する" \\\n    --write-file scripts/watch-reports.sh \\\n    --write-file scripts/agent-comm-common.sh \\\n    --depends-on task_refactor_base_000'
ac_i18n_register "write_task.error.invalid_type" "エラー: type は implementation|investigation|analyst|rework|review を指定してください（入力: {task_type}）"
ac_i18n_register "write_task.error.persona_required" "エラー: persona は必須です。"
ac_i18n_register "write_task.error.title_required" "エラー: title は必須です。"
ac_i18n_register "write_task.error.description_required" "エラー: description は必須です。"
ac_i18n_register "write_task.error.write_files_required" "エラー: write_files は必須です。最低1件指定してください。"
ac_i18n_register "write_task.error.write_file_empty" "エラー: write_files に空文字は指定できません。"
ac_i18n_register "write_task.error.research_active" "エラー: research task がまだ進行中のため、implementation task は作成できません。investigation と analyst の完了後に再実行してください。"
ac_i18n_register "write_task.error.task_exists" "エラー: 同じ task_id が既に存在します: {task_id}"
ac_i18n_register "write_task.error.self_dependency" "エラー: 自己依存は禁止です: {task_id} -> {dependency}"
ac_i18n_register "write_task.error.dep_not_found" "エラー: depends_on の参照先が存在しません: {dependency}"
ac_i18n_register "write_task.error.dep_cycle" "エラー: depends_on に循環があります。タスクを生成できません。"
ac_i18n_register "write_task.success.written" "タスクを書き込みました: {output_path}"
ac_i18n_register "usage.create_question" $'使い方:\n  ./scripts/create-question.sh --task-id <task_id> --question <text>'
ac_i18n_register "create_question.error.task_not_found" "エラー: task_id が見つかりません: {task_id}"
ac_i18n_register "create_question.error.inflight_only" "エラー: inflight タスクのみ質問作成できます（現在: {state}）"
ac_i18n_register "create_question.success.created" "質問を作成しました: {question_file}"
ac_i18n_register "usage.write_command_task" $'使い方:\n  ./scripts/write-command-task.sh --command <指示本文> [--id <command_id>] [--priority <high|medium|low>] [--output <path>]'
ac_i18n_register "write_command_task.error.command_required" "エラー: --command は必須です。"
ac_i18n_register "write_command_task.error.invalid_priority" "エラー: --priority は high|medium|low のみ指定できます。"
ac_i18n_register "write_command_task.success.updated" "command を更新しました: {output_path}"
ac_i18n_register "usage.answer_question" $'使い方:\n  ./scripts/answer-question.sh --question-id <task_id_qN> --answer <text>'
ac_i18n_register "answer_question.error.open_question_missing" "エラー: open 質問が見つかりません: {question_id}"
ac_i18n_register "answer_question.success.answered" "質問に回答しました: {destination}"
ac_i18n_register "usage.update_command_status" $'使い方:\n  ./scripts/update-command-status.sh --status <pending|inflight|done|blocked> [--output <path>]'
ac_i18n_register "update_command_status.error.invalid_status" "エラー: --status は pending|inflight|done|blocked を指定してください。"
ac_i18n_register "update_command_status.error.command_file_missing" "エラー: command ファイルが見つかりません: {output_path}"
ac_i18n_register "update_command_status.success.updated" "command status を更新しました: {status}"
ac_i18n_register "usage.task_heartbeat" $'使い方:\n  ./scripts/task-heartbeat.sh --task-id <task_id>'
ac_i18n_register "task_heartbeat.error.task_not_found" "エラー: task_id が見つかりません: {task_id}"
ac_i18n_register "task_heartbeat.error.inflight_only" "エラー: inflight 以外は heartbeat できません（現在: {state}）"
ac_i18n_register "task_heartbeat.success.updated" "heartbeat 更新: {task_id}"
ac_i18n_register "usage.send_msg" $'使い方:\n  ./scripts/send-msg.sh <target> <message>\n\ntarget:\n  coordinator | task_author | dispatcher | investigation | analyst | tester | implementerN | reviewerN'
ac_i18n_register "send_msg.error.invalid_agent" "送信先 agent が不正です: {target_name}"
ac_i18n_register "send_msg.error.tmux_target_missing" "tmux ターゲットが存在しません: {target}"
ac_i18n_register "send_msg.success.sent" "送信しました: {target_name}"
ac_i18n_register "usage.restart_agent" "使い方: ./scripts/restart-agent.sh <coordinator|task_author|dispatcher|investigation|analyst|tester|implementers|reviewers|workers|implementerN|reviewerN|all>"
ac_i18n_register "restart_agent.error.session_missing" "tmux セッションが存在しません: {session}"
ac_i18n_register "restart_agent.error.invalid_target" "不明な restart 対象です: {target}"
ac_i18n_register "usage.request_send" $'使い方:\n  ./scripts/request-send.sh --target <agent> --message <text> [--title <text>] [--channel agent]\n\n例:\n  ./scripts/request-send.sh --target implementer1 --message "タスクを確認してください"\n  ./scripts/request-send.sh --channel agent --target coordinator --title "質問" --message "ユーザー確認が必要です"'
ac_i18n_register "request_send.error.target_required" "エラー: --target は必須です。"
ac_i18n_register "request_send.error.message_required" "エラー: --message は必須です。"
ac_i18n_register "request_send.error.invalid_channel" "エラー: --channel は agent を指定してください。"
ac_i18n_register "request_send.success.created" "送信要求を作成しました: {out_file}"
ac_i18n_register "usage.task_finish" $'使い方:\n  ./scripts/task-finish.sh \\\n    --task-id <task_id> \\\n    --result <success|failure|blocked> \\\n    --summary <summary> \\\n    [--details <details>] \\\n    [--review-decision <approve|requestchange>] \\\n    [--rework-target <task_id>]... \\\n    [--finding <text>]...'
ac_i18n_register "task_finish.error.invalid_result" "エラー: --result は success|failure|blocked を指定してください。"
ac_i18n_register "task_finish.error.invalid_review_decision" "エラー: --review-decision は approve|requestchange を指定してください。"
ac_i18n_register "task_finish.error.rework_target_required" "エラー: requestchange の場合は --rework-target を最低1件指定してください。"
ac_i18n_register "task_finish.error.rework_target_not_found" "エラー: --rework-target で指定した task_id が存在しません: {target_id}"
ac_i18n_register "task_finish.error.task_not_found" "エラー: task_id が見つかりません: {task_id}"
ac_i18n_register "task_finish.error.inflight_only" "エラー: inflight 以外は完了処理できません（現在: {state}）"
ac_i18n_register "task_finish.error.assigned_to_missing" "エラー: assigned_to が空です（task: {task_id}）。"
ac_i18n_register "task_finish.info.artifact_preserved" "既存の調査成果物を保持しました（上書きしません）: {artifact_path}"
ac_i18n_register "task_finish.artifact.header" "# {task_type} タスク結果"
ac_i18n_register "task_finish.warn.artifact_save_failed" "調査成果物の保存に失敗しました: {artifact_path}"
ac_i18n_register "task_finish.success.completed" "完了処理: {task_id} -> {new_status} ({destination})"
ac_i18n_register "usage.reinject_role" "使い方: ./scripts/reinject-role.sh <coordinator|task_author|investigation|analyst|tester|implementers|reviewers|implementerN|reviewerN|all>"
ac_i18n_register "reinject_role.error.invalid_target" "不明な対象です: {target}"
