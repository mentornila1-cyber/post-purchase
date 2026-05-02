# frozen_string_literal: true

module PostPurchase
  module Strategies
    # Common interface for offer-selection strategies.
    #
    #   strategy.call(shop:, order_context:)
    #     => { offer:, decision_reason:, score_breakdown:, candidates: }
    #     OR nil if no offer should be shown.
    #
    # `candidates` is an array of `{ offer_id:, score: }` hashes used to
    # populate OfferDecision.candidate_offers for auditing.
    class Base < ApplicationService
      def initialize(shop:, order_context:)
        super
        @shop = shop
        @order_context = order_context
      end

      def call
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end

      protected

      attr_reader :shop, :order_context

      def active_offers
        @active_offers ||= shop.offers.active.by_priority.to_a
      end
    end
  end
end
