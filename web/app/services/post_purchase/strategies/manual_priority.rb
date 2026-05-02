# frozen_string_literal: true

module PostPurchase
  module Strategies
    # Pure priority-ordered selection. Picks the highest-priority active
    # offer whose product wasn't already in the order. No scoring logic —
    # the merchant is in full control via the `priority` field.
    class ManualPriority < Base
      def call
        purchased_product_ids = Array(order_context[:line_items]).map { |li| li[:product_id] }.compact
        purchased_variant_ids = Array(order_context[:line_items]).map { |li| li[:variant_id] }.compact

        eligible = active_offers.reject do |offer|
          purchased_product_ids.include?(offer.shopify_product_id) ||
            purchased_variant_ids.include?(offer.shopify_variant_id)
        end

        chosen = eligible.first
        return nil if chosen.blank?

        {
          offer: chosen,
          decision_reason: "Manual priority: highest-priority eligible offer (priority #{chosen.priority})",
          score_breakdown: { priority: chosen.priority.to_i },
          candidates: eligible.map { |o| { offer_id: o.id, score: o.priority.to_i } },
        }
      end
    end
  end
end
