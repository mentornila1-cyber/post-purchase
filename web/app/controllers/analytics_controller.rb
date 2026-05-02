# frozen_string_literal: true

# GET /api/analytics/offers — powers the embedded admin dashboard.
class AnalyticsController < AuthenticatedController
  def offers
    shop = Shop.find_by(shopify_domain: current_shopify_session.shop)
    return render(json: empty_metrics) if shop.blank?

    render(json: ::PostPurchase::AnalyticsService.call(shop: shop))
  rescue StandardError => e
    logger.error("Failed to load analytics: #{e.message}")
    render(json: { success: false, error: e.message }, status: :internal_server_error)
  end

  private

  def empty_metrics
    {
      total_impressions: 0,
      total_acceptances: 0,
      total_rejections: 0,
      conversion_rate: 0.0,
      revenue_generated: 0.0,
      top_offers: [],
      recent_events: [],
    }
  end
end
