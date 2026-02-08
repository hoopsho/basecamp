# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_02_08_000011) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "agent_memories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "agent_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.integer "importance", default: 5
    t.integer "memory_type", null: false
    t.uuid "related_task_id"
    t.datetime "updated_at", null: false
    t.index ["agent_id", "created_at"], name: "index_agent_memories_on_agent_id_and_created_at"
    t.index ["agent_id", "importance"], name: "index_agent_memories_on_agent_id_and_importance"
    t.index ["agent_id"], name: "index_agent_memories_on_agent_id"
    t.index ["expires_at"], name: "index_agent_memories_on_expires_at"
    t.index ["importance"], name: "index_agent_memories_on_importance"
    t.index ["memory_type"], name: "index_agent_memories_on_memory_type"
    t.index ["related_task_id"], name: "index_agent_memories_on_related_task_id"
  end

  create_table "agents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "capabilities", default: {}
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "loop_interval_minutes"
    t.string "name", null: false
    t.string "slack_channel"
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["capabilities"], name: "index_agents_on_capabilities", using: :gin
    t.index ["slug"], name: "index_agents_on_slug", unique: true
    t.index ["status"], name: "index_agents_on_status"
  end

  create_table "credentials", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "credential_type", null: false
    t.text "encrypted_refresh_token"
    t.text "encrypted_value", null: false
    t.datetime "expires_at"
    t.string "scopes", default: [], array: true
    t.string "service_name", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["credential_type"], name: "index_credentials_on_credential_type"
    t.index ["expires_at"], name: "index_credentials_on_expires_at"
    t.index ["scopes"], name: "index_credentials_on_scopes", using: :gin
    t.index ["service_name", "status"], name: "index_credentials_on_service_name_and_status"
    t.index ["service_name"], name: "index_credentials_on_service_name"
    t.index ["status"], name: "index_credentials_on_status"
  end

  create_table "sessions", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["id"], name: "index_sessions_on_id", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "sops", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "agent_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "max_tier", default: 3, null: false
    t.string "name", null: false
    t.string "required_services", default: [], array: true
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "trigger_config", default: {}
    t.integer "trigger_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["agent_id"], name: "index_sops_on_agent_id"
    t.index ["required_services"], name: "index_sops_on_required_services", using: :gin
    t.index ["slug"], name: "index_sops_on_slug", unique: true
    t.index ["status"], name: "index_sops_on_status"
    t.index ["trigger_type"], name: "index_sops_on_trigger_type"
  end

  create_table "steps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "config", default: {}
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "llm_tier", default: 0
    t.integer "max_llm_tier", default: 3
    t.integer "max_retries", default: 3
    t.string "name", null: false
    t.string "on_failure", default: "fail"
    t.string "on_success", default: "next"
    t.string "on_uncertain", default: "escalate_tier"
    t.integer "position", null: false
    t.uuid "sop_id", null: false
    t.integer "step_type", default: 0, null: false
    t.integer "timeout_seconds", default: 300
    t.datetime "updated_at", null: false
    t.index ["sop_id", "position"], name: "index_steps_on_sop_id_and_position", unique: true
    t.index ["sop_id"], name: "index_steps_on_sop_id"
    t.index ["step_type"], name: "index_steps_on_step_type"
  end

  create_table "task_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.float "confidence_score"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.integer "event_type", null: false
    t.jsonb "input_data", default: {}
    t.string "llm_model"
    t.integer "llm_tier_used"
    t.integer "llm_tokens_in"
    t.integer "llm_tokens_out"
    t.jsonb "output_data", default: {}
    t.uuid "step_id"
    t.uuid "task_id", null: false
    t.index ["created_at"], name: "index_task_events_on_created_at"
    t.index ["event_type"], name: "index_task_events_on_event_type"
    t.index ["step_id"], name: "index_task_events_on_step_id"
    t.index ["task_id", "created_at"], name: "index_task_events_on_task_id_and_created_at"
    t.index ["task_id"], name: "index_task_events_on_task_id"
  end

  create_table "tasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "agent_id", null: false
    t.datetime "completed_at"
    t.jsonb "context", default: {}
    t.datetime "created_at", null: false
    t.integer "current_step_position", default: 1
    t.text "error_message"
    t.uuid "parent_task_id"
    t.integer "priority", default: 5
    t.string "slack_thread_ts"
    t.uuid "sop_id", null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "status"], name: "index_tasks_on_agent_id_and_status"
    t.index ["agent_id"], name: "index_tasks_on_agent_id"
    t.index ["context"], name: "index_tasks_on_context", using: :gin
    t.index ["parent_task_id"], name: "index_tasks_on_parent_task_id"
    t.index ["priority"], name: "index_tasks_on_priority"
    t.index ["sop_id", "status"], name: "index_tasks_on_sop_id_and_status"
    t.index ["sop_id"], name: "index_tasks_on_sop_id"
    t.index ["status"], name: "index_tasks_on_status"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.integer "theme_preference", default: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  create_table "watchers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "agent_id", null: false
    t.jsonb "check_config", default: {}
    t.integer "check_type", null: false
    t.datetime "created_at", null: false
    t.integer "interval_minutes", null: false
    t.datetime "last_checked_at"
    t.string "name", null: false
    t.uuid "sop_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_watchers_on_agent_id"
    t.index ["check_type"], name: "index_watchers_on_check_type"
    t.index ["last_checked_at"], name: "index_watchers_on_last_checked_at"
    t.index ["sop_id"], name: "index_watchers_on_sop_id"
    t.index ["status"], name: "index_watchers_on_status"
  end

  add_foreign_key "agent_memories", "agents"
  add_foreign_key "agent_memories", "tasks", column: "related_task_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "sops", "agents"
  add_foreign_key "steps", "sops"
  add_foreign_key "task_events", "steps"
  add_foreign_key "task_events", "tasks"
  add_foreign_key "tasks", "agents"
  add_foreign_key "tasks", "sops"
  add_foreign_key "tasks", "tasks", column: "parent_task_id"
  add_foreign_key "watchers", "agents"
  add_foreign_key "watchers", "sops"
end
