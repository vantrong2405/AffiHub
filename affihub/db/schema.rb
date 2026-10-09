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

ActiveRecord::Schema[8.1].define(version: 2026_10_09_150000) do
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

  create_table "ai_generation_scenes", force: :cascade do |t|
    t.bigint "ai_generation_id", null: false
    t.integer "scene_index", null: false
    t.string "status", null: false
    t.text "prompt_snapshot"
    t.text "narration_snapshot", null: false
    t.string "voice_name", null: false
    t.jsonb "estimate_snapshot", default: {}, null: false
    t.jsonb "consent_snapshot", default: {}, null: false
    t.jsonb "actual_costs", default: {}, null: false
    t.string "safe_error_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_generation_id", "scene_index"], name: "index_ai_generation_scenes_on_ai_generation_id_and_scene_index", unique: true
    t.index ["ai_generation_id", "status"], name: "index_ai_generation_scenes_on_ai_generation_id_and_status"
    t.index ["ai_generation_id"], name: "index_ai_generation_scenes_on_ai_generation_id"
  end

  create_table "ai_generations", force: :cascade do |t|
    t.bigint "video_project_id", null: false
    t.bigint "source_asset_id"
    t.string "status", null: false
    t.string "correlation_id", null: false
    t.string "task_id"
    t.integer "provider_state"
    t.string "safe_error_code"
    t.jsonb "input_snapshot", default: {}, null: false
    t.jsonb "estimate_snapshot", default: {}, null: false
    t.jsonb "consent_snapshot", default: {}, null: false
    t.jsonb "actual_costs", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["correlation_id"], name: "index_ai_generations_on_correlation_id", unique: true
    t.index ["source_asset_id"], name: "index_ai_generations_on_source_asset_id"
    t.index ["task_id"], name: "index_ai_generations_on_task_id", unique: true, where: "(task_id IS NOT NULL)"
    t.index ["video_project_id"], name: "index_ai_generations_on_video_project_id"
  end

  create_table "ai_provider_connections", force: :cascade do |t|
    t.string "provider", null: false
    t.string "provider_subject", null: false
    t.string "provider_client_id", null: false
    t.string "account_email"
    t.string "display_name"
    t.text "access_token", null: false
    t.text "refresh_token"
    t.text "id_token"
    t.datetime "access_token_expires_at"
    t.jsonb "scopes", default: [], null: false
    t.jsonb "available_models", default: [], null: false
    t.string "selected_model"
    t.datetime "last_verified_at"
    t.string "status", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "provider_client_id", "provider_subject"], name: "index_ai_provider_connections_on_provider_client_and_subject", unique: true
    t.index ["provider", "status"], name: "index_ai_provider_connections_on_provider_and_status"
  end

  create_table "drive_exports", force: :cascade do |t|
    t.bigint "google_connection_id", null: false
    t.bigint "render_version_id", null: false
    t.string "status", null: false
    t.string "folder_key", null: false
    t.string "file_key", null: false
    t.string "drive_folder_id"
    t.string "drive_folder_url"
    t.string "drive_file_id"
    t.string "drive_url"
    t.text "upload_session_uri"
    t.bigint "upload_offset", default: 0, null: false
    t.string "safe_error_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["file_key"], name: "index_drive_exports_on_file_key", unique: true
    t.index ["folder_key"], name: "index_drive_exports_on_folder_key"
    t.index ["google_connection_id"], name: "index_drive_exports_on_google_connection_id"
    t.index ["render_version_id", "google_connection_id"], name: "index_drive_exports_on_render_and_connection", unique: true
    t.index ["render_version_id"], name: "index_drive_exports_on_render_version_id"
    t.index ["status", "updated_at"], name: "index_drive_exports_on_status_and_updated_at"
  end

  create_table "google_connections", force: :cascade do |t|
    t.string "integration", null: false
    t.string "google_account_id", null: false
    t.string "email", null: false
    t.text "access_token", null: false
    t.text "refresh_token"
    t.datetime "access_token_expires_at"
    t.jsonb "scopes", default: [], null: false
    t.string "status", null: false
    t.string "safe_error_code"
    t.string "drive_parent_folder_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "spreadsheet_id"
    t.string "worksheet_title"
    t.index ["integration", "google_account_id"], name: "index_google_connections_on_integration_and_account", unique: true
    t.index ["integration", "status"], name: "index_google_connections_on_integration_and_status"
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

  create_table "preflight_reports", force: :cascade do |t|
    t.bigint "render_version_id", null: false
    t.jsonb "checked_destination_ids", default: [], null: false
    t.jsonb "destination_results", default: {}, null: false
    t.datetime "checked_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["render_version_id", "checked_at"], name: "index_preflight_reports_on_render_version_id_and_checked_at"
    t.index ["render_version_id"], name: "index_preflight_reports_on_render_version_id"
  end

  create_table "project_media_assets", force: :cascade do |t|
    t.bigint "video_project_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["video_project_id"], name: "index_project_media_assets_on_video_project_id"
  end

  create_table "publication_quota_reservations", force: :cascade do |t|
    t.bigint "publication_id", null: false
    t.bigint "social_destination_id", null: false
    t.datetime "reserved_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["publication_id"], name: "index_publication_quota_reservations_on_publication_id", unique: true
    t.index ["social_destination_id", "reserved_at"], name: "index_publication_quota_reservations_on_destination_and_time"
    t.index ["social_destination_id"], name: "index_publication_quota_reservations_on_social_destination_id"
  end

  create_table "publications", force: :cascade do |t|
    t.bigint "render_version_id", null: false
    t.bigint "social_destination_id", null: false
    t.string "status", null: false
    t.text "caption", default: "", null: false
    t.datetime "scheduled_at"
    t.string "schedule_occurrence_key"
    t.string "platform_post_id"
    t.text "permalink"
    t.datetime "published_at"
    t.jsonb "provider_reference", default: {}, null: false
    t.string "safe_error_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "consent_snapshot", default: {}, null: false
    t.bigint "schedule_occurrence_id"
    t.index ["render_version_id", "social_destination_id"], name: "idx_on_render_version_id_social_destination_id_249e75c052"
    t.index ["render_version_id"], name: "index_publications_on_render_version_id"
    t.index ["schedule_occurrence_id", "social_destination_id"], name: "index_publications_on_occurrence_and_destination", unique: true
    t.index ["schedule_occurrence_id"], name: "index_publications_on_schedule_occurrence_id"
    t.index ["schedule_occurrence_key"], name: "index_publications_on_schedule_occurrence_key"
    t.index ["social_destination_id", "status"], name: "index_publications_on_social_destination_id_and_status"
    t.index ["social_destination_id"], name: "index_publications_on_social_destination_id"
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

  create_table "schedule_destinations", force: :cascade do |t|
    t.bigint "schedule_id", null: false
    t.bigint "social_destination_id", null: false
    t.text "caption", default: "", null: false
    t.jsonb "consent_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["schedule_id", "social_destination_id"], name: "index_schedule_destinations_on_schedule_and_destination", unique: true
    t.index ["schedule_id"], name: "index_schedule_destinations_on_schedule_id"
    t.index ["social_destination_id"], name: "index_schedule_destinations_on_social_destination_id"
  end

  create_table "schedule_occurrences", force: :cascade do |t|
    t.bigint "schedule_id", null: false
    t.bigint "preflight_report_id"
    t.string "occurrence_key", null: false
    t.datetime "scheduled_at", null: false
    t.datetime "dispatch_at", null: false
    t.string "status", default: "scheduled", null: false
    t.datetime "processed_at"
    t.string "safe_error_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["preflight_report_id"], name: "index_schedule_occurrences_on_preflight_report_id"
    t.index ["schedule_id", "occurrence_key"], name: "index_schedule_occurrences_on_schedule_and_key", unique: true
    t.index ["schedule_id"], name: "index_schedule_occurrences_on_schedule_id"
    t.index ["status", "dispatch_at"], name: "index_schedule_occurrences_on_status_and_dispatch_at"
  end

  create_table "schedules", force: :cascade do |t|
    t.bigint "render_version_id", null: false
    t.string "status", default: "active", null: false
    t.string "recurrence", default: "once", null: false
    t.string "time_zone", null: false
    t.string "local_time", null: false
    t.datetime "next_occurrence_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["render_version_id"], name: "index_schedules_on_render_version_id"
    t.index ["status", "next_occurrence_at"], name: "index_schedules_on_status_and_next_occurrence_at"
  end

  create_table "sheet_syncs", force: :cascade do |t|
    t.bigint "google_connection_id", null: false
    t.bigint "render_version_id", null: false
    t.bigint "social_destination_id", null: false
    t.string "sheet_row_key", null: false
    t.integer "row_number"
    t.string "status", null: false
    t.string "safe_error_code"
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["google_connection_id", "render_version_id", "social_destination_id"], name: "index_sheet_syncs_on_connection_render_destination", unique: true
    t.index ["google_connection_id"], name: "index_sheet_syncs_on_google_connection_id"
    t.index ["render_version_id"], name: "index_sheet_syncs_on_render_version_id"
    t.index ["sheet_row_key"], name: "index_sheet_syncs_on_sheet_row_key"
    t.index ["social_destination_id"], name: "index_sheet_syncs_on_social_destination_id"
    t.index ["status", "updated_at"], name: "index_sheet_syncs_on_status_and_updated_at"
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
    t.text "refresh_token"
    t.datetime "refresh_token_expires_at"
    t.jsonb "scopes", default: [], null: false
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
    t.string "download_error_code"
    t.text "download_error"
    t.index ["video_project_id"], name: "index_source_assets_on_video_project_id"
  end

  create_table "source_discoveries", force: :cascade do |t|
    t.bigint "video_project_id", null: false
    t.string "search_type", null: false
    t.string "search_query"
    t.string "region_code", null: false
    t.string "video_category_id"
    t.datetime "searched_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["video_project_id", "searched_at"], name: "index_source_discoveries_on_video_project_id_and_searched_at"
    t.index ["video_project_id"], name: "index_source_discoveries_on_video_project_id"
  end

  create_table "source_discovery_results", force: :cascade do |t|
    t.bigint "source_discovery_id", null: false
    t.bigint "youtube_discovery_metadata_id", null: false
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_discovery_id", "position"], name: "idx_on_source_discovery_id_position_f02ae32b56", unique: true
    t.index ["source_discovery_id", "youtube_discovery_metadata_id"], name: "index_source_discovery_results_on_search_and_metadata", unique: true
    t.index ["source_discovery_id"], name: "index_source_discovery_results_on_source_discovery_id"
    t.index ["youtube_discovery_metadata_id"], name: "idx_on_youtube_discovery_metadata_id_b486f46dc8"
  end

  create_table "source_download_gates", force: :cascade do |t|
    t.string "key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_source_download_gates_on_key", unique: true
  end

  create_table "source_download_slots", force: :cascade do |t|
    t.datetime "started_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["started_at"], name: "index_source_download_slots_on_started_at"
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

  create_table "youtube_discovery_metadata", force: :cascade do |t|
    t.string "video_id", null: false
    t.string "title", null: false
    t.string "channel_title", null: false
    t.text "thumbnail_url", null: false
    t.text "attribution_url", null: false
    t.string "discovery_type", null: false
    t.string "search_query"
    t.string "region_code"
    t.string "video_category_id"
    t.datetime "fetched_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fetched_at"], name: "index_youtube_discovery_metadata_on_fetched_at"
    t.index ["video_id"], name: "index_youtube_discovery_metadata_on_video_id", unique: true
  end

  create_table "youtube_quota_counters", force: :cascade do |t|
    t.string "bucket", null: false
    t.date "usage_date", null: false
    t.integer "requests_count", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bucket", "usage_date"], name: "index_youtube_quota_counters_on_bucket_and_usage_date", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_generation_scenes", "ai_generations"
  add_foreign_key "ai_generations", "source_assets"
  add_foreign_key "ai_generations", "video_projects"
  add_foreign_key "drive_exports", "google_connections"
  add_foreign_key "drive_exports", "render_versions"
  add_foreign_key "outbound_attempts", "workflow_runs"
  add_foreign_key "preflight_reports", "render_versions"
  add_foreign_key "project_media_assets", "video_projects"
  add_foreign_key "publication_quota_reservations", "publications"
  add_foreign_key "publication_quota_reservations", "social_destinations"
  add_foreign_key "publications", "render_versions"
  add_foreign_key "publications", "schedule_occurrences"
  add_foreign_key "publications", "social_destinations"
  add_foreign_key "render_versions", "source_assets"
  add_foreign_key "render_versions", "video_projects"
  add_foreign_key "schedule_destinations", "schedules"
  add_foreign_key "schedule_destinations", "social_destinations"
  add_foreign_key "schedule_occurrences", "preflight_reports"
  add_foreign_key "schedule_occurrences", "schedules"
  add_foreign_key "schedules", "render_versions"
  add_foreign_key "sheet_syncs", "google_connections"
  add_foreign_key "sheet_syncs", "render_versions"
  add_foreign_key "sheet_syncs", "social_destinations"
  add_foreign_key "social_destinations", "social_connections"
  add_foreign_key "source_assets", "video_projects"
  add_foreign_key "source_discoveries", "video_projects"
  add_foreign_key "source_discovery_results", "source_discoveries", on_delete: :cascade
  add_foreign_key "source_discovery_results", "youtube_discovery_metadata", column: "youtube_discovery_metadata_id", on_delete: :cascade
  add_foreign_key "workflow_audit_events", "outbound_attempts"
  add_foreign_key "workflow_audit_events", "workflow_runs"
end
