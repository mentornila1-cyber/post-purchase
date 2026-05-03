# frozen_string_literal: true

module PostPurchase
  # Persists OfferEvent rows. Tracking failures must never break the buyer
  # flow, so all methods rescue and log instead of raising.
  class EventTracker
    class << self
      def track(shop:, event_type:, offer: nil, **attrs)
        OfferEvent.create!(
          shop: shop,
          offer: offer,
          event_type: event_type,
          **attrs.slice(
            :reference_id, :order_id, :checkout_token, :customer_id,
            :order_subtotal, :offered_price, :revenue_added, :metadata, :error_message
          ),
        )
      rescue StandardError => e
        Rails.logger.error("[PostPurchase::EventTracker] failed to track #{event_type}: #{e.message}")
        nil
      end

      def track_impression(shop:, offer:, **attrs)
        track(shop: shop, offer: offer, event_type: "impression", **attrs)
      end

      def track_impression_once(shop:, offer:, **attrs)
        reference_id = attrs[:reference_id]
        if reference_id.present? && OfferEvent.exists?(
          shop: shop,
          offer: offer,
          event_type: "impression",
          reference_id: reference_id,
        )
          return nil
        end

        track_impression(shop: shop, offer: offer, **attrs)
      end

      def track_acceptance(shop:, offer:, revenue_added:, **attrs)
        track(shop: shop, offer: offer, event_type: "accepted", revenue_added: revenue_added, **attrs)
      end

      def track_rejection(shop:, offer:, **attrs)
        track(shop: shop, offer: offer, event_type: "rejected", **attrs)
      end

      def track_error(shop:, error_message:, offer: nil, **attrs)
        track(shop: shop, offer: offer, event_type: "error", error_message: error_message, **attrs)
      end
    end
  end
end
