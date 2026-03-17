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
ac_i18n_register "message.command_pending" $'新しい command があります。\n- common: {common_role}\n- task_author: {task_author_role}\n- personas manifest: {personas_manifest}\n\nagent-comm root: {repo_root}\nfile: {command_file}\n\n次の順でただちに実行してください。\n1. command を inflight に更新する\n2. investigation task を作成する\n3. analyst task を作成する\n4. その完了通知が来るまで待機する\n\ncommand が明示的に要求していない限り、最初の2つの task を作る前に無関係な repository file や runtime 内部を調べないでください。\n\ncommand:\n{command_text}'
ac_i18n_register "message.question_open" $'ユーザー確認が必要です。\nquestion_id: {question_id}\ntask_id: {task_id}\nasked_by: {asked_by}\nfile: {question_file}\n\n{question}'
ac_i18n_register "message.report_research_complete" $'調査タスクが完了しました。\ntask_id: {task_id}\npersona: {persona}\nresult: {result}\ncommand_id: {command_id}\nartifact: {artifact}\n\n成果物は確認してください。ただし、この command の `investigation` と `analyst` が両方完了するまでは implementation task を作成しないでください。'
ac_i18n_register "message.report_tester_update" $'テスト実行タスクが更新されました。\ntask_id: {task_id}\nresult: {result}\ncommand_id: {command_id}\n\n必要なら次の review タスクを作成してください。'
ac_i18n_register "message.report_reviewer_update" $'review タスクが更新されました。\ntask_id: {task_id}\nresult: {result}\nreview_decision: {review_decision}\ncommand_id: {command_id}\n\n必要なら rework を作成してください。'
ac_i18n_register "message.report_review_group_update" $'全体レビューが完了しました。\ntask_id: {task_id}\nresult: {result}\nreview_decision: {review_decision}\ncommand_id: {command_id}\nreviewer_count: {reviewer_count}\nrework_note: {note_path}\n\n必要なら次の rework を作成してください。'
ac_i18n_register "message.report_generic_complete" $'タスク完了通知です。\ntask_id: {task_id}\npersona: {persona}\ntype: {task_type}\nresult: {result}\ncommand_id: {command_id}'
