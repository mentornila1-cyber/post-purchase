# frozen_string_literal: true

class Offer < ApplicationRecord
  belongs_to :shop
  has_many :offer_events, dependent: :nullify
  has_many :offer_decisions, dependent: :nullify

  validates :title, presence: true

  scope :active, -> { where(active: true) }
  scope :by_priority, -> { order(priority: :desc, id: :asc) }

  DISCOUNT_TYPES = %w[percentage fixed_amount].freeze
end
