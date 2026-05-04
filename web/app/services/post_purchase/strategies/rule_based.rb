# frozen_string_literal: true

module PostPurchase
  module Strategies
    # Deterministic, score-based strategy. Excludes products / variants already
    # purchased, then awards points for trigger matches, price fit, and
    # discount. Priority is intentionally ignored here; use ManualPriority when
    # merchant-defined priority should control selection.
    class RuleBased < Base
      def call
        return nil if active_offers.empty?

        scored = eligible_offers.sort_by(&:id).map do |offer|
          result = OfferScoringService.call(offer: offer, order_context: order_context)
          { offer: offer, score: result[:total_score], breakdown: result[:breakdown] }
        end
        return nil if scored.empty?

        best = scored.max_by { |s| s[:score] }
        return nil if best[:score] <= 0

        {
          offer: best[:offer],
          decision_reason: build_reason(best),
          score_breakdown: best[:breakdown],
          candidates: scored.map { |s| { offer_id: s[:offer].id, score: s[:score] } },
        }
      end

      private

      def eligible_offers
        active_offers.reject { |offer| already_purchased?(offer) }
      end

      def already_purchased?(offer)
        purchased_product_ids.include?(offer.shopify_product_id) ||
          purchased_variant_ids.include?(offer.shopify_variant_id)
      end

      def purchased_product_ids
        @purchased_product_ids ||= Array(order_context[:line_items]).filter_map { |li| li[:product_id] }
      end

      def purchased_variant_ids
        @purchased_variant_ids ||= Array(order_context[:line_items]).filter_map { |li| li[:variant_id] }
      end

      def build_reason(scored)
        reasons = scored[:breakdown].select { |_, v| v.is_a?(Numeric) && v.positive? }.keys
        return "Default offer (no specific match)" if reasons.empty?

        "Rule-based: matched on #{reasons.join(", ")}"
      end
    end
  end
end
