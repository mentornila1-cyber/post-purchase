# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module PostPurchase
  module Strategies
    # AI-driven selection: send the purchase context + active offer catalog
    # to OpenAI and let it reason about the best cross-sell. The backend still
    # validates the chosen offer and stores deterministic scoring details.
    # Falls back to rule-based scoring on any error so we never block the buyer.
    #
    # Configuration: set OPENAI_API_KEY in the Rails env. OPENAI_MODEL is
    # optional and defaults to gpt-5. Without a key, the strategy short-circuits
    # to RuleBased so the flow never breaks in dev.
    class AiReasoning < Base
      OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses"
      DEFAULT_MODEL = "gpt-5"
      REQUEST_TIMEOUT_SECONDS = 6

      def call
        return fallback unless openai_configured?
        return nil if active_offers.empty?
        return fallback if eligible_offers.empty?

        ai_decision = request_ai_decision
        selected_offer = eligible_offers.find { |offer| offer.id.to_s == ai_decision.fetch("offer_id").to_s }
        return fallback unless selected_offer

        scoring = deterministic_score(selected_offer, ai_decision)

        {
          offer: selected_offer,
          decision_reason: "AI-assisted: #{ai_decision.fetch("rationale")}",
          score_breakdown: scoring[:breakdown],
          candidates: candidate_scores(ai_decision),
        }
      rescue StandardError => e
        Rails.logger.error("[AiReasoning] error: #{e.message} — falling back to rule-based")
        fallback
      end

      private

      def openai_configured?
        ENV["OPENAI_API_KEY"].present?
      end

      def eligible_offers
        @eligible_offers ||= active_offers.reject { |offer| already_purchased?(offer) }
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

      def request_ai_decision
        response = post_to_openai(openai_payload)
        parsed = JSON.parse(extract_output_text(response))
        validate_ai_decision!(parsed)
        parsed
      end

      def post_to_openai(payload)
        uri = URI(OPENAI_RESPONSES_URL)
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{ENV.fetch("OPENAI_API_KEY")}"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = REQUEST_TIMEOUT_SECONDS
        http.read_timeout = REQUEST_TIMEOUT_SECONDS

        response = http.request(request)
        raise "OpenAI request failed with status #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end

      def openai_payload
        {
          model: ENV.fetch("OPENAI_MODEL", DEFAULT_MODEL),
          instructions: instructions,
          input: JSON.pretty_generate(prompt_context),
          max_output_tokens: 500,
          store: false,
          text: {
            format: {
              type: "json_schema",
              name: "post_purchase_offer_selection",
              strict: true,
              schema: response_schema,
            },
          },
        }
      end

      def instructions
        <<~PROMPT
          You select one Shopify post-purchase upsell or cross-sell offer.
          Choose only from the provided offer IDs.
          Do not choose a product or variant the customer already purchased.
          Prefer offers that are relevant to the purchased item, priced as a
          low-friction add-on, discounted enough to feel urgent, and likely to
          increase order value.
          Return concise JSON only.
        PROMPT
      end

      def prompt_context
        {
          order: order_payload,
          offers: offer_payloads,
          scoring_guidance: {
            relevance: "0-30 points for how naturally this complements the purchased items",
            margin_fit: "0-15 points for price/discount fit relative to order subtotal",
            customer_intent: "0-15 points for matching likely buyer intent from line-item titles",
          },
        }
      end

      def order_payload
        {
          subtotal: order_context[:subtotal],
          currency: order_context[:currency],
          destination_country: order_context[:destination_country],
          line_items: Array(order_context[:line_items]).map do |item|
            {
              product_id: item[:product_id],
              variant_id: item[:variant_id],
              title: item[:title],
              quantity: item[:quantity],
              price: item[:price],
            }
          end,
        }
      end

      def offer_payloads
        eligible_offers.map do |offer|
          base = OfferScoringService.call(offer: offer, order_context: order_context)

          {
            id: offer.id.to_s,
            title: offer.title,
            description: offer.description,
            product_id: offer.shopify_product_id,
            variant_id: offer.shopify_variant_id,
            original_price: offer.original_price&.to_f,
            discounted_price: offer.discounted_price&.to_f,
            currency: offer.currency,
            discount_type: offer.discount_type,
            discount_value: offer.discount_value&.to_f,
            priority: offer.priority,
            deterministic_base_score: base[:total_score],
            deterministic_breakdown: base[:breakdown],
          }
        end
      end

      def response_schema
        {
          type: "object",
          additionalProperties: false,
          required: %w[offer_id rationale score_adjustments],
          properties: {
            offer_id: {
              type: "string",
              description: "The selected offer ID from the provided offers list.",
            },
            rationale: {
              type: "string",
              description: "Short merchant-readable reason this offer is relevant.",
            },
            score_adjustments: {
              type: "object",
              additionalProperties: false,
              required: %w[relevance margin_fit customer_intent],
              properties: {
                relevance: { type: "number" },
                margin_fit: { type: "number" },
                customer_intent: { type: "number" },
              },
            },
          },
        }
      end

      def extract_output_text(response)
        return response["output_text"] if response["output_text"].present?

        Array(response["output"]).each do |item|
          Array(item["content"]).each do |content|
            return content["text"] if content["type"] == "output_text" && content["text"].present?
          end
        end

        raise "OpenAI response did not include output text"
      end

      def validate_ai_decision!(decision)
        raise "OpenAI response missing offer_id" if decision["offer_id"].blank?
        raise "OpenAI response missing rationale" if decision["rationale"].blank?

        adjustments = decision["score_adjustments"]
        raise "OpenAI response missing score_adjustments" unless adjustments.is_a?(Hash)

        %w[relevance margin_fit customer_intent].each do |key|
          raise "OpenAI response score_adjustments.#{key} must be numeric" unless adjustments[key].is_a?(Numeric)
        end
      end

      def deterministic_score(offer, ai_decision)
        base = OfferScoringService.call(offer: offer, order_context: order_context)
        adjustments = normalized_adjustments(ai_decision)
        total = base[:total_score] + adjustments.values.sum

        {
          total_score: total,
          breakdown: base[:breakdown].merge(
            ai_relevance: adjustments["relevance"],
            ai_margin_fit: adjustments["margin_fit"],
            ai_customer_intent: adjustments["customer_intent"],
            ai_total_score: total,
          ),
        }
      end

      def candidate_scores(ai_decision)
        selected_offer_id = ai_decision.fetch("offer_id").to_s

        eligible_offers.map do |offer|
          base = OfferScoringService.call(offer: offer, order_context: order_context)
          selected = offer.id.to_s == selected_offer_id
          score = selected ? deterministic_score(offer, ai_decision)[:total_score] : base[:total_score]

          { offer_id: offer.id, score: score, ai_selected: selected }
        end
      end

      def normalized_adjustments(ai_decision)
        ai_decision.fetch("score_adjustments").transform_values do |value|
          value.to_f.clamp(0, 30)
        end
      end

      def fallback
        RuleBased.call(shop: shop, order_context: order_context)
      end
    end
  end
end
