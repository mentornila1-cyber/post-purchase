# frozen_string_literal: true

module PostPurchase
  # POST /api/post_purchase/events
  # Records buyer-side events from the extension. Never breaks the buyer
  # flow on failure — always returns success: true to the extension.
  class EventsController < BaseController
    def create
      event_type = extension_payload["event_type"].to_s
      unless OfferEvent::EVENT_TYPES.include?(event_type)
        return render(json: { success: false, error: "Invalid event_type" }, status: :bad_request)
      end

      offer_id = extension_payload["offer_id"]
      offer = current_shop.offers.find_by(id: offer_id) if offer_id.present?

      ::PostPurchase::EventTracker.track(
        shop: current_shop,
        offer: offer,
        event_type: event_type,
        reference_id: extension_payload["reference_id"],
        order_id: extension_payload["order_id"],
        revenue_added: extension_payload["revenue_added"],
        offered_price: extension_payload["offered_price"],
        error_message: extension_payload["error_message"],
        metadata: extension_payload["metadata"] || {},
      )

      render(json: { success: true })
    rescue StandardError => e
      Rails.logger.error("[EventsController] #{e.class}: #{e.message}")
      render(json: { success: true })
    end
  end
end
