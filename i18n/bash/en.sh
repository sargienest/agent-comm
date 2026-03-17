ac_i18n_register "role_manifest.title" "Available Personas"
ac_i18n_register "role_manifest.generated" "Generated from role scan."

ac_i18n_register "materialized.title" "Dashboard Instruction"
ac_i18n_register "materialized.meta_target" "- target: {agent_id}"
ac_i18n_register "materialized.meta_source" "- source: agent-comm"
ac_i18n_register "materialized.meta_created_at" "- created_at: {created_at}"
ac_i18n_register "materialized.user_message_heading" "User Message"

ac_i18n_register "message.materialized_notice" $'Instruction file: {path}\nPlease execute it.'
ac_i18n_register "message.coordinator_boot" $'Read the following to understand your role.\n- common: {common_role}\n- coordinator: {coordinator_role}\n\nagent-comm root: {repo_root}\ndashboard: {dashboard_url}\n\nWhen you receive a user request, create the command with {write_command_path}, then wait.'
ac_i18n_register "message.task_author_boot" $'Read the following to understand your role.\n- common: {common_role}\n- task_author: {task_author_role}\n- personas manifest: {personas_manifest}\n\nagent-comm root: {repo_root}\ndashboard: {dashboard_url}\n\nWait until coordinator or dispatcher sends you the next instruction.'
ac_i18n_register "message.worker_boot" $'Read the following to understand your role.\n- common: {common_role}\n- worker: {worker_role}\n- default persona: {persona_role}\n\nworker id: {worker_id}\nagent-comm root: {repo_root}\ndashboard: {dashboard_url}\n\nWait until dispatcher sends you a task file.'
ac_i18n_register "message.reinject" $'+Reinjection. Re-read the following.\n- common: {common_role}\n- role: {role_path}\n\nagent-comm root: {repo_root}\n{extra_block}'
ac_i18n_register "message.personas_manifest_line" "personas manifest: {personas_manifest}"
ac_i18n_register "message.default_persona_line" "default persona: {persona_role}"
ac_i18n_register "message.worker_task" $'Read the following before starting work.\n- common: {common_role}\n- worker role: {worker_role}\n- persona: {persona_role}\n\ntask file: {task_file}\ntask id: {task_id}\nagent-comm root: {repo_root}\n\nUse {task_finish_path} when you complete the task.\nUse {create_question_path} if you need to ask a question.'
ac_i18n_register "message.command_pending" $'A new command is available.\nfile: {command_file}\npersonas: {personas_manifest}\n\nFirst create the investigation and analyst tasks. After reviewing those results, split the work into implementation tasks.\n\ncommand:\n{command_text}'
ac_i18n_register "message.question_open" $'User input is required.\nquestion_id: {question_id}\ntask_id: {task_id}\nasked_by: {asked_by}\nfile: {question_file}\n\n{question}'
ac_i18n_register "message.report_research_complete" $'A research task has completed.\ntask_id: {task_id}\npersona: {persona}\nresult: {result}\ncommand_id: {command_id}\nartifact: {artifact}\n\nReview the results and split the next tasks.'
ac_i18n_register "message.report_tester_update" $'The test execution task was updated.\ntask_id: {task_id}\nresult: {result}\ncommand_id: {command_id}\n\nCreate the next review task if needed.'
ac_i18n_register "message.report_reviewer_update" $'The review task was updated.\ntask_id: {task_id}\nresult: {result}\nreview_decision: {review_decision}\ncommand_id: {command_id}\n\nCreate a rework task if needed.'
ac_i18n_register "message.report_review_group_update" $'The overall review completed.\ntask_id: {task_id}\nresult: {result}\nreview_decision: {review_decision}\ncommand_id: {command_id}\nreviewer_count: {reviewer_count}\nrework_note: {note_path}\n\nCreate the next rework task if needed.'
ac_i18n_register "message.report_generic_complete" $'Task completion notification.\ntask_id: {task_id}\npersona: {persona}\ntype: {task_type}\nresult: {result}\ncommand_id: {command_id}'
