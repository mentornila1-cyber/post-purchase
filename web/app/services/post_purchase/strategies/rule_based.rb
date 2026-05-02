# frozen_string_literal: true

module PostPurchase
  module Strategies
    # Deterministic, score-based strategy. Awards points for product / variant
    # / product type / tag matches, plus discount and priority bonuses, minus
    # a heavy penalty for offers whose product was already purchased.
    class RuleBased < Base
      def call
        return nil if active_offers.empty?

        scored = active_offers.map do |offer|
          result = OfferScoringService.call(offer: offer, order_context: order_context)
          { offer: offer, score: result[:total_score], breakdown: result[:breakdown] }
        end

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

      def build_reason(scored)
        reasons = scored[:breakdown].select { |_, v| v.is_a?(Numeric) && v.positive? }.keys
        return "Default offer (no specific match)" if reasons.empty?

        "Rule-based: matched on #{reasons.join(", ")}"
      end
    end
  end
end
