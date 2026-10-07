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

ActiveRecord::Schema[8.1].define(version: 2026_10_07_090100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "outbound_attempts", force: :cascade do |t|
    t.bigint "workflow_run_id", null: false
    t.string "attempt_id", null: false
    t.integer "attempt_number", null: false
    t.string "stage", null: false
    t.string "status", null: false
    t.string "idempotency_key"
    t.datetime "request_started_at"
    t.datetime "sender_stopped_at"
    t.datetime "request_timeout_at", null: false
    t.jsonb "provider_reference", default: {}, null: false
    t.string "safe_error_code"
    t.text "manual_evidence"
    t.string "actor_reference"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["attempt_id"], name: "index_outbound_attempts_on_attempt_id", unique: true
    t.index ["workflow_run_id", "stage", "attempt_number"], name: "index_outbound_attempts_on_run_stage_number", unique: true
    t.index ["workflow_run_id", "status"], name: "index_outbound_attempts_on_workflow_run_id_and_status"
    t.index ["workflow_run_id"], name: "index_outbound_attempts_on_workflow_run_id"
  end

  create_table "project_media_assets", force: :cascade do |t|
    t.bigint "video_project_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["video_project_id"], name: "index_project_media_assets_on_video_project_id"
  end

  create_table "render_versions", force: :cascade do |t|
    t.bigint "video_project_id", null: false
    t.bigint "source_asset_id", null: false
    t.integer "version_number", default: 1, null: false
    t.string "status", null: false
    t.jsonb "edit_config", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "render_error"
    t.index ["source_asset_id", "version_number"], name: "index_render_versions_on_source_asset_id_and_version_number", unique: true
    t.index ["source_asset_id"], name: "index_render_versions_on_source_asset_id"
    t.index ["video_project_id"], name: "index_render_versions_on_video_project_id"
  end

  create_table "social_connections", force: :cascade do |t|
    t.string "provider", null: false
    t.string "external_user_id", null: false
    t.string "name", null: false
    t.text "access_token", null: false
    t.datetime "token_expires_at"
    t.string "status", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "external_user_id"], name: "index_social_connections_on_provider_and_external_user_id", unique: true
    t.index ["provider", "status"], name: "index_social_connections_on_provider_and_status"
  end

  create_table "social_destinations", force: :cascade do |t|
    t.bigint "social_connection_id", null: false
    t.string "provider", null: false
    t.string "external_id", null: false
    t.string "name", null: false
    t.text "access_token", null: false
    t.datetime "token_expires_at"
    t.string "status", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "status"], name: "index_social_destinations_on_provider_and_status"
    t.index ["social_connection_id", "external_id"], name: "index_social_destinations_on_connection_and_external_id", unique: true
    t.index ["social_connection_id"], name: "index_social_destinations_on_social_connection_id"
  end

  create_table "source_assets", force: :cascade do |t|
    t.bigint "video_project_id", null: false
    t.string "source_type"
    t.text "source_url"
    t.jsonb "provenance", default: {}, null: false
    t.string "status", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "media_metadata", default: {}, null: false
    t.text "inspection_error"
    t.index ["video_project_id"], name: "index_source_assets_on_video_project_id"
  end

  create_table "video_projects", force: :cascade do |t|
    t.string "name", null: false
    t.string "status", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "workflow_audit_events", force: :cascade do |t|
    t.bigint "workflow_run_id", null: false
    t.bigint "outbound_attempt_id"
    t.string "event_type", null: false
    t.string "stage"
    t.string "worker_id"
    t.bigint "fencing_token"
    t.string "actor_reference"
    t.jsonb "details", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["outbound_attempt_id"], name: "index_workflow_audit_events_on_outbound_attempt_id"
    t.index ["workflow_run_id", "created_at"], name: "index_workflow_audit_events_on_workflow_run_id_and_created_at"
    t.index ["workflow_run_id"], name: "index_workflow_audit_events_on_workflow_run_id"
  end

  create_table "workflow_runs", force: :cascade do |t|
    t.string "workflowable_type", null: false
    t.bigint "workflowable_id", null: false
    t.string "operation_id", null: false
    t.string "operation", null: false
    t.string "stage", null: false
    t.string "status", null: false
    t.string "worker_id"
    t.datetime "lease_expires_at"
    t.datetime "heartbeat_at"
    t.bigint "fencing_token", default: 0, null: false
    t.jsonb "checkpoint", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operation_id"], name: "index_workflow_runs_on_operation_id", unique: true
    t.index ["status", "lease_expires_at"], name: "index_workflow_runs_on_status_and_lease_expires_at"
    t.index ["workflowable_type", "workflowable_id", "operation"], name: "idx_on_workflowable_type_workflowable_id_operation_ee5e2f5ea7"
    t.index ["workflowable_type", "workflowable_id"], name: "index_workflow_runs_on_workflowable"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "outbound_attempts", "workflow_runs"
  add_foreign_key "project_media_assets", "video_projects"
  add_foreign_key "render_versions", "source_assets"
  add_foreign_key "render_versions", "video_projects"
  add_foreign_key "social_destinations", "social_connections"
  add_foreign_key "source_assets", "video_projects"
  add_foreign_key "workflow_audit_events", "outbound_attempts"
  add_foreign_key "workflow_audit_events", "workflow_runs"
end
