# frozen_string_literal: true

# GET /api/events?type=accepted&limit=100
# Powers the admin Events Log page.
class EventsController < AuthenticatedController
  def index
    shop = Shop.find_by(shopify_domain: current_shopify_session.shop)
    return render(json: []) if shop.blank?

    scope = shop.offer_events.includes(:offer).order(created_at: :desc)
    scope = scope.where(event_type: params[:type]) if params[:type].present?
    scope = scope.limit([params[:limit].to_i, 200].min.nonzero? || 100)

    render(json: scope.map { |event| serialize(event) })
  rescue StandardError => e
    logger.error("Failed to load events: #{e.message}")
    render(json: { error: e.message }, status: :internal_server_error)
  end

  private

  def serialize(event)
    {
      id: event.id,
      event_type: event.event_type,
      offer_title: event.offer&.title,
      reference_id: event.reference_id,
      order_id: event.order_id,
      revenue_added: event.revenue_added.to_f,
      offered_price: event.offered_price.to_f,
      error_message: event.error_message,
      created_at: event.created_at,
    }
  end
end
