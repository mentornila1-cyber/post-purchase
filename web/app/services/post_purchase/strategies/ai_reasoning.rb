# frozen_string_literal: true

module PostPurchase
  module Strategies
    # AI-driven selection: send the purchase context + active offer catalog
    # to Claude and let it reason about the best cross-sell. Falls back to
    # rule-based scoring on any error so we never block the buyer.
    #
    # This is a scaffold — wire up an actual Anthropic SDK call when ready.
    # Configuration: set ANTHROPIC_API_KEY in the Rails env. Without it, the
    # strategy short-circuits to RuleBased so the flow never breaks in dev.
    class AiReasoning < Base
      def call
        return fallback unless anthropic_configured?
        return nil if active_offers.empty?

        # TODO: replace with a real Anthropic client call. Suggested prompt
        # shape: "Given this purchase: <context>, and these candidates:
        # <offers>, return JSON {offer_id:, rationale:}".
        Rails.logger.info("[AiReasoning] not yet implemented — falling back to rule-based")
        fallback
      rescue StandardError => e
        Rails.logger.error("[AiReasoning] error: #{e.message} — falling back to rule-based")
        fallback
      end

      private

      def anthropic_configured?
        ENV["ANTHROPIC_API_KEY"].present?
      end

      def fallback
        RuleBased.call(shop: shop, order_context: order_context)
      end
    end
  end
end
