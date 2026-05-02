# frozen_string_literal: true

# Admin CRUD for Offers. Used by the embedded admin Offers page.
class OffersController < AuthenticatedController
  before_action :load_shop
  before_action :load_offer, only: [:update, :destroy]

  def index
    render(json: @shop.offers.by_priority.map { |o| serialize(o) })
  end

  def create
    offer = @shop.offers.new(offer_params)
    if offer.save
      render(json: serialize(offer), status: :created)
    else
      render(json: { errors: offer.errors.full_messages }, status: :unprocessable_entity)
    end
  end

  def update
    if @offer.update(offer_params)
      render(json: serialize(@offer))
    else
      render(json: { errors: @offer.errors.full_messages }, status: :unprocessable_entity)
    end
  end

  def destroy
    @offer.destroy
    head(:no_content)
  end

  private

  def load_shop
    @shop = Shop.find_by(shopify_domain: current_shopify_session.shop)
    render(json: { error: "Shop not found" }, status: :not_found) if @shop.blank?
  end

  def load_offer
    @offer = @shop.offers.find_by(id: params[:id])
    render(json: { error: "Offer not found" }, status: :not_found) if @offer.blank?
  end

  def offer_params
    params.require(:offer).permit(
      :title, :description, :shopify_product_id, :shopify_variant_id,
      :shopify_variant_legacy_id, :image_url, :original_price, :discounted_price,
      :currency, :discount_type, :discount_value, :priority, :active,
      trigger_product_ids: [], trigger_variant_ids: [],
      metadata: {},
    )
  end

  def serialize(offer)
    offer.as_json.merge(
      original_price: offer.original_price.to_s,
      discounted_price: offer.discounted_price.to_s,
      discount_value: offer.discount_value.to_f,
    )
  end
end
