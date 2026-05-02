# frozen_string_literal: true

module PostPurchase
  # POST /api/post_purchase/sign_changeset
  # Looks up the offer server-side, builds the changeset, and signs it with
  # the Shopify app secret. The extension never sees the secret.
  class ChangesetsController < BaseController
    def create
      reference_id = extension_payload["reference_id"]
      offer_id = extension_payload["offer_id"]

      return render_error("Missing reference_id", :bad_request) if reference_id.blank?
      return render_error("Missing offer_id", :bad_request) if offer_id.blank?

      offer = current_shop.offers.active.find_by(id: offer_id)
      return render_error("Offer not found or inactive", :not_found) if offer.blank?

      changes = ::PostPurchase::ChangesetBuilder.call(offer: offer)
      token = ::PostPurchase::ChangesetSigner.call(reference_id: reference_id, changes: changes)

      render(json: { token: token })
    rescue ::PostPurchase::ChangesetBuilder::InvalidOfferError => e
      render_error(e.message, :unprocessable_entity)
    rescue StandardError => e
      Rails.logger.error("[ChangesetsController] #{e.class}: #{e.message}")
      ::PostPurchase::EventTracker.track_error(
        shop: current_shop,
        error_message: e.message,
        reference_id: extension_payload["reference_id"],
        offer: current_shop.offers.find_by(id: extension_payload["offer_id"]),
      )
      render_error("Failed to sign changeset", :internal_server_error)
    end

    private

    def render_error(message, status)
      render(json: { error: message }, status: status)
    end
  end
end
