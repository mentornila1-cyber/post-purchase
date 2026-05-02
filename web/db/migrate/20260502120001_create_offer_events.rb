# frozen_string_literal: true

class CreateOfferEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :offer_events do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :offer, null: true, foreign_key: true
      t.string :event_type, null: false
      t.string :reference_id
      t.string :order_id
      t.string :checkout_token
      t.string :customer_id
      t.decimal :order_subtotal, precision: 10, scale: 2
      t.decimal :offered_price, precision: 10, scale: 2
      t.decimal :revenue_added, precision: 10, scale: 2
      t.json :metadata, default: {}
      t.text :error_message
      t.timestamps
    end

    add_index :offer_events, [:shop_id, :event_type]
    add_index :offer_events, :reference_id
    add_index :offer_events, :created_at
  end
end
