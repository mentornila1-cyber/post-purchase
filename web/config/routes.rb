# frozen_string_literal: true

Rails.application.routes.draw do
  root to: "home#index"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  scope path: :api, format: :json do
    namespace :post_purchase do
      post "offer", to: "offers#create"
      post "sign_changeset", to: "changesets#create"
      post "events", to: "events#create"
    end

    get "analytics/offers", to: "analytics#offers"
    get "events", to: "events#index"
    get "shop_settings", to: "shop_settings#show"
    patch "shop_settings", to: "shop_settings#update"
    get "shopify/products", to: "shopify/products#index"
    resources :offers, only: [:index, :create, :update, :destroy]

    namespace :webhooks do
      post "/app_uninstalled", to: "app_uninstalled#receive"
      post "/app_scopes_update", to: "app_scopes_update#receive"
      post "/customers_data_request", to: "customers_data_request#receive"
      post "/customers_redact", to: "customers_redact#receive"
      post "/shop_redact", to: "shop_redact#receive"
    end
  end

  mount ShopifyApp::Engine, at: "/api"
  get "/api", to: redirect(path: "/") # Needed because our engine root is /api but that breaks frontend routing

  # If you are adding routes outside of the /api path, remember to also add a proxy rule for
  # them in web/frontend/vite.config.js

  # Any other routes will just render the react app
  match "*path" => "home#index", via: [:get, :post]
end
