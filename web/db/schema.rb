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

ActiveRecord::Schema[7.1].define(version: 2026_05_02_130000) do
  create_table "offer_decisions", force: :cascade do |t|
    t.integer "shop_id", null: false
    t.integer "offer_id"
    t.string "reference_id"
    t.string "order_id"
    t.json "candidate_offers", default: []
    t.json "score_breakdown", default: {}
    t.text "decision_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["offer_id"], name: "index_offer_decisions_on_offer_id"
    t.index ["reference_id"], name: "index_offer_decisions_on_reference_id"
    t.index ["shop_id"], name: "index_offer_decisions_on_shop_id"
  end

  create_table "offer_events", force: :cascade do |t|
    t.integer "shop_id", null: false
    t.integer "offer_id"
    t.string "event_type", null: false
    t.string "reference_id"
    t.string "order_id"
    t.string "checkout_token"
    t.string "customer_id"
    t.decimal "order_subtotal", precision: 10, scale: 2
    t.decimal "offered_price", precision: 10, scale: 2
    t.decimal "revenue_added", precision: 10, scale: 2
    t.json "metadata", default: {}
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_offer_events_on_created_at"
    t.index ["offer_id"], name: "index_offer_events_on_offer_id"
    t.index ["reference_id"], name: "index_offer_events_on_reference_id"
    t.index ["shop_id", "event_type"], name: "index_offer_events_on_shop_id_and_event_type"
    t.index ["shop_id"], name: "index_offer_events_on_shop_id"
  end

  create_table "offers", force: :cascade do |t|
    t.integer "shop_id", null: false
    t.string "title", null: false
    t.string "description"
    t.string "shopify_product_id"
    t.string "shopify_variant_id"
    t.string "shopify_variant_legacy_id"
    t.string "image_url"
    t.decimal "original_price", precision: 10, scale: 2
    t.decimal "discounted_price", precision: 10, scale: 2
    t.string "currency", default: "USD"
    t.string "discount_type", default: "percentage"
    t.decimal "discount_value", precision: 10, scale: 2
    t.json "trigger_product_ids", default: []
    t.json "trigger_variant_ids", default: []
    t.json "trigger_product_types", default: []
    t.json "trigger_tags", default: []
    t.integer "priority", default: 0
    t.boolean "active", default: true, null: false
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "active"], name: "index_offers_on_shop_id_and_active"
    t.index ["shop_id", "priority"], name: "index_offers_on_shop_id_and_priority"
    t.index ["shop_id"], name: "index_offers_on_shop_id"
  end

  create_table "shops", force: :cascade do |t|
    t.string "shopify_domain", null: false
    t.string "shopify_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "access_scopes"
    t.datetime "expires_at"
    t.string "refresh_token"
    t.datetime "refresh_token_expires_at"
    t.string "selection_strategy", default: "rule_based", null: false
    t.index ["shopify_domain"], name: "index_shops_on_shopify_domain", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.bigint "shopify_user_id", null: false
    t.string "shopify_domain", null: false
    t.string "shopify_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "access_scopes", default: "", null: false
    t.datetime "expires_at"
    t.index ["shopify_user_id"], name: "index_users_on_shopify_user_id", unique: true
  end

  add_foreign_key "offer_decisions", "offers"
  add_foreign_key "offer_decisions", "shops"
  add_foreign_key "offer_events", "offers"
  add_foreign_key "offer_events", "shops"
  add_foreign_key "offers", "shops"
end
