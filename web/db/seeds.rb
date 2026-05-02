# frozen_string_literal: true

# Seeded demo offers attached to every existing Shop. Re-running is safe —
# offers are upserted by title.

DEMO_OFFERS = [
  {
    title: "Add Ski Wax to your kit",
    description: "Keep your new snowboard fast and protected with our best-selling ski wax.",
    shopify_product_id: "gid://shopify/Product/8906386538556",
    shopify_variant_id: "gid://shopify/ProductVariant/44848377561148",
    shopify_variant_legacy_id: "44848377561148",
    image_url: "https://cdn.shopify.com/s/files/1/0716/0378/1692/files/snowboard_wax.png?v=1777732559",
    original_price: 24.95,
    discounted_price: 19.95,
    discount_type: "percentage",
    discount_value: 20,
    priority: 100,
  },
]

Shop.find_each do |shop|
  DEMO_OFFERS.each do |attrs|
    offer = shop.offers.find_or_initialize_by(title: attrs[:title])
    offer.assign_attributes(attrs)
    offer.active = true if offer.active.nil?
    offer.save!
  end
  puts "Seeded #{DEMO_OFFERS.size} offer(s) for shop #{shop.shopify_domain}"
end

puts "Seed complete. If no shops exist yet, install the app first then re-run db:seed."
