# frozen_string_literal: true

module PostPurchase
  # POST /api/post_purchase/offer
  # Called from the extension's ShouldRender. Picks an offer, tracks an
  # impression, and returns a render: true/false response.
  class OffersController < BaseController
    def create
      reference_id = extension_payload["reference_id"]
      return render_no_offer if reference_id.blank?

      order_context = ::PostPurchase::OrderContextParser.call(
        reference_id: reference_id,
        shop: current_shop,
        decoded_token: decoded_token,
      )

      result = ::PostPurchase::OfferSelector.call(shop: current_shop, order_context: order_context)
      return render_no_offer if result.nil?

      offer = result[:offer]

      ::PostPurchase::EventTracker.track_impression_once(
        shop: current_shop,
        offer: offer,
        reference_id: reference_id,
        offered_price: offer.discounted_price,
        order_subtotal: order_context[:subtotal],
        metadata: { decision_reason: result[:decision_reason] },
      )

      render(json: { render: true, offer: serialize_offer(offer, result[:decision_reason]) })
    rescue StandardError => e
      Rails.logger.error("[OffersController] #{e.class}: #{e.message}")
      ::PostPurchase::EventTracker.track_error(
        shop: current_shop,
        error_message: e.message,
        reference_id: extension_payload["reference_id"],
      )
      render_no_offer
    end

    private

    def render_no_offer
      render(json: { render: false, offer: nil })
    end

    def serialize_offer(offer, decision_reason)
      changes = ::PostPurchase::ChangesetBuilder.call(offer: offer)

      {
        id: offer.id,
        title: offer.title,
        description: offer.description,
        shopify_product_id: offer.shopify_product_id,
        shopify_variant_id: offer.shopify_variant_id,
        image_url: offer.image_url,
        original_price: offer.original_price.to_s,
        discounted_price: offer.discounted_price.to_s,
        currency: offer.currency,
        discount_type: offer.discount_type,
        discount_value: offer.discount_value.to_f,
        changes: changes,
        decision_reason: decision_reason,
      }
    end
  end
end
