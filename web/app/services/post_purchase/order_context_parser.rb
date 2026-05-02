# frozen_string_literal: true

module PostPurchase
  # Builds a normalized order/purchase context from the decoded post-purchase
  # JWT. The token's `input_data.initialPurchase` block contains line items,
  # totals, customer ID, and destination — enough for scoring without an
  # Admin API call.
  class OrderContextParser < ApplicationService
    def initialize(reference_id:, shop:, decoded_token: nil, request_metadata: nil)
      super
      @reference_id = reference_id
      @shop = shop
      @decoded_token = decoded_token || {}
      @request_metadata = request_metadata || {}
    end

    def call
      initial_purchase = @decoded_token.dig("input_data", "initialPurchase") || @request_metadata

      {
        reference_id: @reference_id,
        order_id: initial_purchase["order_id"],
        subtotal: extract_subtotal(initial_purchase),
        currency: extract_currency(initial_purchase),
        customer_id: initial_purchase["customerId"] || initial_purchase["customer_id"],
        destination_country: initial_purchase["destinationCountryCode"],
        line_items: extract_line_items(initial_purchase),
      }
    end

    private

    def extract_subtotal(initial_purchase)
      initial_purchase.dig("totalPriceSet", "shopMoney", "amount").to_f
    end

    def extract_currency(initial_purchase)
      initial_purchase.dig("totalPriceSet", "shopMoney", "currencyCode") || "USD"
    end

    def extract_line_items(initial_purchase)
      Array(initial_purchase["lineItems"]).map do |li|
        product = li["product"] || {}
        variant = product["variant"] || {}

        {
          product_id: gid_for("Product", product["id"]),
          variant_id: gid_for("ProductVariant", variant["id"]),
          title: product["title"],
          quantity: li["quantity"].to_i,
          price: li.dig("totalPriceSet", "shopMoney", "amount").to_f,
        }
      end
    end

    def gid_for(type, id)
      return nil if id.blank?
      return id if id.to_s.start_with?("gid://")

      "gid://shopify/#{type}/#{id}"
    end
  end
end
