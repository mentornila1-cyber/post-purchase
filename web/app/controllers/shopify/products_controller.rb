# frozen_string_literal: true

module Shopify
  class ProductsController < AuthenticatedController
    def index
      shop = Shop.find_by(shopify_domain: current_shopify_session.shop)
      return render(json: { error: "Shop not found" }, status: :not_found) if shop.blank?

      products = ::Shopify::ProductCatalogService.call(shop: shop)
      render(json: products)
    rescue StandardError => e
      Rails.logger.error("[Shopify::ProductsController] #{e.class}: #{e.message}")
      render(json: { error: e.message }, status: :unprocessable_entity)
    end
  end
end
