# frozen_string_literal: true

class CreateOfferDecisions < ActiveRecord::Migration[7.1]
  def change
    create_table :offer_decisions do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :offer, null: true, foreign_key: true
      t.string :reference_id
      t.string :order_id
      t.json :candidate_offers, default: []
      t.json :score_breakdown, default: {}
      t.text :decision_reason
      t.timestamps
    end

    add_index :offer_decisions, :reference_id
  end
end
