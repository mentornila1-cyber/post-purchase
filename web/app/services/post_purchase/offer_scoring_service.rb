# frozen_string_literal: true

module PostPurchase
  # Deterministic scorer. Returns { total_score:, breakdown: } so we can store
  # decisions and explain why an offer was picked.
  #
  # Tag and product-type matching is intentionally not scored — the
  # post-purchase JWT does not carry those fields, so any check would always
  # be a no-op. Adding them back requires enriching line items via the Admin
  # API, which is documented as a future improvement.
  class OfferScoringService < ApplicationService
    def initialize(offer:, order_context:)
      super
      @offer = offer
      @order_context = order_context
    end

    def call
      breakdown = {
        product_match: product_match_score,
        variant_match: variant_match_score,
        price_fit: price_fit_score,
        discount: discount_score,
      }

      { total_score: breakdown.values.sum, breakdown: breakdown }
    end

    private

    def product_match_score
      (Array(@offer.trigger_product_ids) & purchased_product_ids).any? ? 50 : 0
    end

    def variant_match_score
      (Array(@offer.trigger_variant_ids) & purchased_variant_ids).any? ? 40 : 0
    end

    def price_fit_score
      subtotal = @order_context[:subtotal].to_f
      return 0 if subtotal <= 0 || @offer.discounted_price.to_f <= 0

      ratio = @offer.discounted_price.to_f / subtotal
      ratio.between?(0.15, 0.50) ? 15 : 0
    end

    def discount_score
      @offer.discount_value.to_f.positive? ? 10 : 0
    end

    def purchased_product_ids
      Array(@order_context[:line_items]).map { |li| li[:product_id] }.compact
    end

    def purchased_variant_ids
      Array(@order_context[:line_items]).map { |li| li[:variant_id] }.compact
    end
  end
end
