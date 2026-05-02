# frozen_string_literal: true

module PostPurchase
  # Base controller for post-purchase extension endpoints.
  #
  # Auth: the extension sends a JWT (issued by Shopify, signed with
  # SHOPIFY_API_SECRET) inside the JSON body — *not* the Authorization header.
  # We do this so the browser treats the request as a "simple" CORS request
  # (text/plain content-type, no custom headers) and skips the preflight.
  # Some dev tunnels (cloudflared) strip CORS headers from OPTIONS responses
  # and break preflight, so we sidestep the issue entirely.
  class BaseController < ActionController::Base
    protect_from_forgery with: :null_session

    attr_reader :current_shop, :decoded_token, :extension_payload

    before_action :set_cors_headers
    before_action :parse_extension_payload
    before_action :authenticate_post_purchase_token!

    private

    def set_cors_headers
      response.set_header("Access-Control-Allow-Origin", "*")
      response.set_header("Access-Control-Allow-Methods", "POST, OPTIONS")
      response.set_header("Access-Control-Allow-Headers", "Content-Type")
      response.set_header("Access-Control-Max-Age", "3600")
    end

    def parse_extension_payload
      raw = request.raw_post.to_s
      @extension_payload = raw.present? ? JSON.parse(raw) : {}
    rescue JSON::ParserError => e
      Rails.logger.warn("[PostPurchase] body parse failed: #{e.message}")
      @extension_payload = {}
    end

    def authenticate_post_purchase_token!
      token = @extension_payload["token"].to_s
      if token.blank?
        Rails.logger.warn("[PostPurchase] auth failed: missing token in body. Payload keys: #{@extension_payload.keys.inspect}")
        return render_unauthorized("Missing token")
      end

      @decoded_token = decode_token(token)
      if @decoded_token.blank?
        Rails.logger.warn("[PostPurchase] auth failed: token decode returned nil")
        return render_unauthorized("Invalid token")
      end

      Rails.logger.info("[PostPurchase] decoded JWT claims: #{@decoded_token.inspect}")

      @current_shop = lookup_shop(@decoded_token)
      if @current_shop.blank?
        Rails.logger.warn("[PostPurchase] auth failed: no Shop found. Extracted domain: #{extract_shop_domain(@decoded_token).inspect}")
        return render_unauthorized("Unknown shop")
      end
    end

    def decode_token(token)
      secret = ShopifyApp.configuration.secret
      payload, _header = JWT.decode(token, secret, true, algorithm: "HS256")
      payload
    rescue JWT::DecodeError => e
      Rails.logger.warn("[PostPurchase] JWT decode failed: #{e.message}")
      nil
    end

    def lookup_shop(payload)
      domain = extract_shop_domain(payload)
      return nil if domain.blank?

      Shop.find_by(shopify_domain: domain)
    end

    # Post-purchase tokens nest the shop under `input_data.shop.domain`. We
    # also fall back to the standard session-token claims (`dest`, `iss`,
    # etc.) so this works for any Shopify-issued JWT.
    def extract_shop_domain(payload)
      nested = payload.dig("input_data", "shop", "domain")
      return nested if nested.to_s.end_with?(".myshopify.com")

      candidates = [payload["dest"], payload["shop_domain"], payload["shop"],
        payload["iss"], payload["aud"]].compact

      candidates.each do |raw|
        domain = parse_shop_domain(raw.to_s)
        return domain if domain&.end_with?(".myshopify.com")
      end

      nil
    end

    def parse_shop_domain(raw)
      return raw if raw.end_with?(".myshopify.com") && !raw.include?("/")

      uri = URI.parse(raw)
      uri.host if uri.host&.end_with?(".myshopify.com")
    rescue URI::InvalidURIError
      nil
    end

    def render_unauthorized(message)
      render(json: { error: message }, status: :unauthorized)
    end
  end
end
