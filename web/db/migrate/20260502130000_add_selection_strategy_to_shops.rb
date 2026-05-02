# frozen_string_literal: true

class AddSelectionStrategyToShops < ActiveRecord::Migration[7.1]
  def change
    add_column :shops, :selection_strategy, :string, default: "rule_based", null: false
  end
end
