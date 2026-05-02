# frozen_string_literal: true

# Shop-level settings (currently just selection_strategy).
class ShopSettingsController < AuthenticatedController
  before_action :load_shop

  def show
    render(json: serialize)
  end

  def update
    if @shop.update(shop_settings_params)
      render(json: serialize)
    else
      render(json: { errors: @shop.errors.full_messages }, status: :unprocessable_entity)
    end
  end

  private

  def load_shop
    @shop = Shop.find_by(shopify_domain: current_shopify_session.shop)
    render(json: { error: "Shop not found" }, status: :not_found) if @shop.blank?
  end

  def shop_settings_params
    params.require(:shop).permit(:selection_strategy)
  end

  def serialize
    {
      shopify_domain: @shop.shopify_domain,
      selection_strategy: @shop.selection_strategy,
      available_strategies: Shop::SELECTION_STRATEGIES,
    }
  end
end
