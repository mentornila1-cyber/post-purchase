# frozen_string_literal: true

class Shop < ActiveRecord::Base
  include ShopifyApp::ShopSessionStorage

  has_many :offers, dependent: :destroy
  has_many :offer_events, dependent: :destroy
  has_many :offer_decisions, dependent: :destroy

  SELECTION_STRATEGIES = %w[rule_based manual_priority ai_reasoning].freeze

  validates :selection_strategy, inclusion: { in: SELECTION_STRATEGIES }

  def api_version
    ShopifyApp.configuration.api_version
  end
end
