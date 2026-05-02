# frozen_string_literal: true

class OfferDecision < ApplicationRecord
  belongs_to :shop
  belongs_to :offer, optional: true
end
