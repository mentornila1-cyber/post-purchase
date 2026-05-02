# frozen_string_literal: true

require "jwt"
require "securerandom"

module PostPurchase
  # Signs a post-purchase changeset using the Shopify app secret. The signed
  # JWT is what the extension passes to applyChangeset(token).
  class ChangesetSigner < ApplicationService
    def initialize(reference_id:, changes:)
      super
      @reference_id = reference_id
      @changes = changes
    end

    def call
      payload = {
        iss: ShopifyApp.configuration.api_key,
        jti: SecureRandom.uuid,
        iat: Time.current.to_i,
        sub: @reference_id,
        changes: @changes,
      }

      JWT.encode(payload, ShopifyApp.configuration.secret, "HS256")
    end
  end
end
