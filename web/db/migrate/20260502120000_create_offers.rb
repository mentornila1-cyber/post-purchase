# frozen_string_literal: true

class CreateOffers < ActiveRecord::Migration[7.1]
  def change
    create_table :offers do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :title, null: false
      t.string :description
      t.string :shopify_product_id
      t.string :shopify_variant_id
      t.string :shopify_variant_legacy_id
      t.string :image_url
      t.decimal :original_price, precision: 10, scale: 2
      t.decimal :discounted_price, precision: 10, scale: 2
      t.string :currency, default: "USD"
      t.string :discount_type, default: "percentage"
      t.decimal :discount_value, precision: 10, scale: 2
      t.json :trigger_product_ids, default: []
      t.json :trigger_variant_ids, default: []
      t.json :trigger_product_types, default: []
      t.json :trigger_tags, default: []
      t.integer :priority, default: 0
      t.boolean :active, default: true, null: false
      t.json :metadata, default: {}
      t.timestamps
    end

    add_index :offers, [:shop_id, :active]
    add_index :offers, [:shop_id, :priority]
  end
end
