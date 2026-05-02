# frozen_string_literal: true

class OfferEvent < ApplicationRecord
  belongs_to :shop
  belongs_to :offer, optional: true

  EVENT_TYPES = %w[impression accepted rejected error].freeze

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }

  scope :impressions, -> { where(event_type: "impression") }
  scope :acceptances, -> { where(event_type: "accepted") }
  scope :rejections, -> { where(event_type: "rejected") }
end
