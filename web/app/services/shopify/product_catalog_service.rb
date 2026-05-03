# frozen_string_literal: true

module Shopify
  class ProductCatalogService < ApplicationService
    QUERY = <<~GRAPHQL
      query ProductCatalog($first: Int!, $query: String!) {
        products(first: $first, query: $query, sortKey: TITLE) {
          nodes {
            id
            title
            featuredImage {
              url
            }
            variants(first: 50) {
              nodes {
                id
                title
                price
              }
            }
          }
        }
      }
    GRAPHQL

    def initialize(shop:, limit: 50)
      super
      @shop = shop
      @limit = limit.to_i.clamp(1, 50)
    end

    def call
      response = client.query(
        query: QUERY,
        variables: { first: @limit, query: "status:active" },
      )
      raise "Shopify Admin API returned #{response.code}" unless response.ok?

      body = response.body
      errors = body["errors"]
      raise "Shopify Admin API error: #{errors.to_json}" if errors.present?

      Array(body.dig("data", "products", "nodes")).map { |product| serialize_product(product) }
    end

    private

    def client
      session = Shop.retrieve_by_shopify_domain(@shop.shopify_domain)
      ShopifyAPI::Clients::Graphql::Admin.new(session: session)
    end

    def serialize_product(product)
      {
        id: product["id"],
        title: product["title"],
        image_url: product.dig("featuredImage", "url"),
        variants: Array(product.dig("variants", "nodes")).map do |variant|
          {
            id: variant["id"],
            title: variant["title"],
            price: variant["price"].to_f,
          }
        end,
      }
    end
  end
end
