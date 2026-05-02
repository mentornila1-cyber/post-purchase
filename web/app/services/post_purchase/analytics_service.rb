# frozen_string_literal: true

module PostPurchase
  # Computes dashboard metrics for the embedded admin app.
  class AnalyticsService < ApplicationService
    def initialize(shop:, recent_limit: 20, top_offers_limit: 5)
      super
      @shop = shop
      @recent_limit = recent_limit
      @top_offers_limit = top_offers_limit
    end

    def call
      events = @shop.offer_events
      impressions = events.impressions.count
      acceptances = events.acceptances.count
      rejections = events.rejections.count
      revenue = events.acceptances.sum(:revenue_added).to_f

      {
        total_impressions: impressions,
        total_acceptances: acceptances,
        total_rejections: rejections,
        conversion_rate: conversion_rate(acceptances, impressions),
        revenue_generated: revenue,
        top_offers: top_offers,
        recent_events: recent_events,
      }
    end

    private

    def conversion_rate(acceptances, impressions)
      return 0.0 if impressions.zero?

      ((acceptances.to_f / impressions) * 100).round(2)
    end

    def top_offers
      @shop.offers.includes(:offer_events).map do |offer|
        offer_events = offer.offer_events
        impressions = offer_events.impressions.count
        acceptances = offer_events.acceptances.count
        rejections = offer_events.rejections.count

        {
          offer_id: offer.id,
          title: offer.title,
          impressions: impressions,
          acceptances: acceptances,
          rejections: rejections,
          conversion_rate: conversion_rate(acceptances, impressions),
          revenue: offer_events.acceptances.sum(:revenue_added).to_f,
        }
      end.sort_by { |o| -o[:revenue] }.first(@top_offers_limit)
    end

    def recent_events
      @shop.offer_events.includes(:offer).order(created_at: :desc).limit(@recent_limit).map do |event|
        {
          event_type: event.event_type,
          offer_title: event.offer&.title,
          reference_id: event.reference_id,
          revenue_added: event.revenue_added.to_f,
          created_at: event.created_at,
        }
      end
    end
  end
end
