# frozen_string_literal: true

module PostPurchase
  # Dispatches to the configured offer-selection strategy and persists an
  # OfferDecision record so we can explain why a particular offer was shown.
  class OfferSelector < ApplicationService
    STRATEGIES = {
      "rule_based" => Strategies::RuleBased,
      "manual_priority" => Strategies::ManualPriority,
      "ai_reasoning" => Strategies::AiReasoning,
    }.freeze

    DEFAULT_STRATEGY = "rule_based"

    def initialize(shop:, order_context:)
      super
      @shop = shop
      @order_context = order_context
    end

    def call
      cached = cached_decision
      return result_from_decision(cached) if cached

      strategy_klass = STRATEGIES[strategy_key] || STRATEGIES[DEFAULT_STRATEGY]
      result = strategy_klass.call(shop: @shop, order_context: @order_context)
      return nil if result.blank?

      OfferDecision.create!(
        shop: @shop,
        offer: result[:offer],
        reference_id: @order_context[:reference_id],
        order_id: @order_context[:order_id],
        candidate_offers: result[:candidates] || [],
        score_breakdown: result[:score_breakdown] || {},
        decision_reason: result[:decision_reason],
      )

      {
        offer: result[:offer],
        decision_reason: result[:decision_reason],
        score_breakdown: result[:score_breakdown] || {},
        cached: false,
      }
    end

    private

    def cached_decision
      reference_id = @order_context[:reference_id]
      return nil if reference_id.blank?

      OfferDecision.includes(:offer)
        .where(shop: @shop, reference_id: reference_id)
        .order(:created_at)
        .detect { |decision| decision.offer&.active? }
    end

    def result_from_decision(decision)
      {
        offer: decision.offer,
        decision_reason: decision.decision_reason,
        score_breakdown: decision.score_breakdown || {},
        cached: true,
      }
    end

    def strategy_key
      @shop.respond_to?(:selection_strategy) ? @shop.selection_strategy : DEFAULT_STRATEGY
    end
  end
end
