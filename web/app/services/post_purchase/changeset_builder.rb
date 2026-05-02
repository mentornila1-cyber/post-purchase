# frozen_string_literal: true

module PostPurchase
  # Builds the Shopify post-purchase changeset payload from an Offer.
  # The Shopify post-purchase API expects numeric variant IDs, so we prefer
  # shopify_variant_legacy_id and fall back to extracting the numeric ID
  # from a global ID.
  class ChangesetBuilder < ApplicationService
    class InvalidOfferError < StandardError; end

    def initialize(offer:)
      super
      @offer = offer
    end

    def call
      raise InvalidOfferError, "Offer is not active" unless @offer.active?

      variant_id = numeric_variant_id
      raise InvalidOfferError, "Offer is missing a variant ID" if variant_id.blank?

      [
        {
          type: "add_variant",
          variant_id: variant_id.to_i,
          quantity: 1,
          discount: discount_payload,
        }.compact,
      ]
    end

    private

    def numeric_variant_id
      return @offer.shopify_variant_legacy_id if @offer.shopify_variant_legacy_id.present?

      @offer.shopify_variant_id.to_s[/\d+\z/]
    end

    def discount_payload
      return nil if @offer.discount_value.to_f <= 0

      {
        value: @offer.discount_value.to_f,
        valueType: @offer.discount_type == "fixed_amount" ? "fixed_amount" : "percentage",
        title: "Post-purchase offer",
      }
    end
  end
end
