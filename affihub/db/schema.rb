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

ActiveRecord::Schema[8.1].define(version: 2026_10_06_032532) do
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

  create_table "affiliate_connections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "provider"
    t.string "api_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_affiliate_connections_on_user_id"
  end

  create_table "ai_connections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "access_token"
    t.string "refresh_token"
    t.datetime "access_token_expires_at"
    t.string "status", default: "disconnected", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "id_token"
    t.string "chatgpt_account_id"
    t.string "chatgpt_plan_type"
    t.datetime "connected_at"
    t.index ["user_id"], name: "index_ai_connections_on_user_id", unique: true
  end

  create_table "contents", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "user_id", null: false
    t.string "status", default: "generated", null: false
    t.string "affiliate_url"
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "generation_count", default: 0, null: false
    t.index ["product_id"], name: "index_contents_on_product_id"
    t.index ["user_id"], name: "index_contents_on_user_id"
  end

  create_table "products", force: :cascade do |t|
    t.string "affiliate_provider"
    t.string "source_product_id"
    t.string "merchant"
    t.string "title"
    t.text "description"
    t.text "images"
    t.decimal "price"
    t.decimal "original_price"
    t.decimal "discount"
    t.string "category"
    t.decimal "rating"
    t.integer "sold"
    t.decimal "commission"
    t.string "original_product_url"
    t.string "affiliate_url"
    t.text "raw_source_data"
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.boolean "is_mall"
    t.index ["user_id", "affiliate_provider", "original_product_url"], name: "index_products_on_user_provider_and_original_url", unique: true
    t.index ["user_id"], name: "index_products_on_user_id"
  end

  create_table "publications", force: :cascade do |t|
    t.bigint "content_id", null: false
    t.bigint "social_destination_id", null: false
    t.string "status", default: "draft", null: false
    t.datetime "scheduled_at"
    t.string "provider_post_id"
    t.string "published_url"
    t.datetime "published_at"
    t.string "error_code"
    t.text "error_message"
    t.integer "attempt_count", default: 0, null: false
    t.datetime "last_attempt_at"
    t.text "provider_metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["content_id"], name: "index_publications_on_content_id"
    t.index ["social_destination_id"], name: "index_publications_on_social_destination_id"
  end

  create_table "render_versions", force: :cascade do |t|
    t.bigint "source_asset_id", null: false
    t.integer "version_number", default: 1, null: false
    t.integer "status", default: 0, null: false
    t.jsonb "edit_config", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_asset_id"], name: "index_render_versions_on_source_asset_id"
  end

  create_table "social_connections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "provider"
    t.string "access_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "provider"], name: "index_social_connections_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_social_connections_on_user_id"
  end

  create_table "social_destinations", force: :cascade do |t|
    t.bigint "social_connection_id", null: false
    t.string "destination_type"
    t.string "page_id"
    t.string "name"
    t.string "page_access_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["social_connection_id", "page_id"], name: "index_social_destinations_on_social_connection_id_and_page_id", unique: true
    t.index ["social_connection_id"], name: "index_social_destinations_on_social_connection_id"
  end

  create_table "source_assets", force: :cascade do |t|
    t.bigint "video_project_id", null: false
    t.string "source_type"
    t.text "source_url"
    t.jsonb "provenance", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["video_project_id"], name: "index_source_assets_on_video_project_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "video_projects", force: :cascade do |t|
    t.string "title"
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "affiliate_connections", "users"
  add_foreign_key "ai_connections", "users"
  add_foreign_key "contents", "products"
  add_foreign_key "contents", "users"
  add_foreign_key "products", "users"
  add_foreign_key "publications", "contents"
  add_foreign_key "publications", "social_destinations"
  add_foreign_key "render_versions", "source_assets"
  add_foreign_key "social_connections", "users"
  add_foreign_key "social_destinations", "social_connections"
  add_foreign_key "source_assets", "video_projects"
end
