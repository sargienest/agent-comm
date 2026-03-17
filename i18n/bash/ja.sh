ac_i18n_register "role_manifest.title" "利用可能な Persona"
ac_i18n_register "role_manifest.generated" "role scan から自動生成。"

ac_i18n_register "materialized.title" "Dashboard 指示"
ac_i18n_register "materialized.meta_target" "- target: {agent_id}"
ac_i18n_register "materialized.meta_source" "- source: agent-comm"
ac_i18n_register "materialized.meta_created_at" "- created_at: {created_at}"
ac_i18n_register "materialized.user_message_heading" "User Message"

ac_i18n_register "message.materialized_notice" $'指示ファイル: {path}\nこれを実施してください。'
ac_i18n_register "message.coordinator_boot" $'以下を読んで役割を理解してください。\n- common: {common_role}\n- coordinator: {coordinator_role}\n\nagent-comm root: {repo_root}\ndashboard: {dashboard_url}\n\nユーザー指示を受けたら {write_command_path} で command を投入し、あとは待機してください。'
ac_i18n_register "message.task_author_boot" $'以下を読んで役割を理解してください。\n- common: {common_role}\n- task_author: {task_author_role}\n- personas manifest: {personas_manifest}\n\nagent-comm root: {repo_root}\ndashboard: {dashboard_url}\n\ncoordinator または dispatcher の指示があるまで待機してください。'
ac_i18n_register "message.worker_boot" $'以下を読んで役割を理解してください。\n- common: {common_role}\n- worker: {worker_role}\n- default persona: {persona_role}\n\nworker id: {worker_id}\nagent-comm root: {repo_root}\ndashboard: {dashboard_url}\n\ndispatcher から task file が届くまで待機してください。'
ac_i18n_register "message.reinject" $'+再注入です。以下を読み直してください。\n- common: {common_role}\n- role: {role_path}\n\nagent-comm root: {repo_root}\n{extra_block}'
ac_i18n_register "message.personas_manifest_line" "personas manifest: {personas_manifest}"
ac_i18n_register "message.default_persona_line" "default persona: {persona_role}"
ac_i18n_register "message.worker_task" $'以下を読んで作業してください。\n- common: {common_role}\n- worker role: {worker_role}\n- persona: {persona_role}\n\ntask file: {task_file}\ntask id: {task_id}\nagent-comm root: {repo_root}\n\n完了時は {task_finish_path} を使ってください。\n質問が必要なら {create_question_path} を使ってください。'
ac_i18n_register "message.command_pending" $'新しい command があります。\nfile: {command_file}\npersonas: {personas_manifest}\n\nまず investigation と analyst の調査タスクを作成し、その結果を見てから実装タスクへ分解してください。\n\ncommand:\n{command_text}'
ac_i18n_register "message.question_open" $'ユーザー確認が必要です。\nquestion_id: {question_id}\ntask_id: {task_id}\nasked_by: {asked_by}\nfile: {question_file}\n\n{question}'
ac_i18n_register "message.report_research_complete" $'調査タスクが完了しました。\ntask_id: {task_id}\npersona: {persona}\nresult: {result}\ncommand_id: {command_id}\nartifact: {artifact}\n\n結果を確認して次のタスクを分解してください。'
ac_i18n_register "message.report_tester_update" $'テスト実行タスクが更新されました。\ntask_id: {task_id}\nresult: {result}\ncommand_id: {command_id}\n\n必要なら次の review タスクを作成してください。'
ac_i18n_register "message.report_reviewer_update" $'review タスクが更新されました。\ntask_id: {task_id}\nresult: {result}\nreview_decision: {review_decision}\ncommand_id: {command_id}\n\n必要なら rework を作成してください。'
ac_i18n_register "message.report_review_group_update" $'全体レビューが完了しました。\ntask_id: {task_id}\nresult: {result}\nreview_decision: {review_decision}\ncommand_id: {command_id}\nreviewer_count: {reviewer_count}\nrework_note: {note_path}\n\n必要なら次の rework を作成してください。'
ac_i18n_register "message.report_generic_complete" $'タスク完了通知です。\ntask_id: {task_id}\npersona: {persona}\ntype: {task_type}\nresult: {result}\ncommand_id: {command_id}'
