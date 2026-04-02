alias RestaurantDash.{Orders, Repo}
alias RestaurantDash.Orders.Order

# Clear existing orders
Repo.delete_all(Order)

demo_orders = [
  %{
    customer_name: "Marcus Chen",
    phone: "(415) 555-0101",
    items: ["Margherita Pizza (Large)", "Garlic Bread", "Tiramisu", "San Pellegrino"],
    status: "new",
    delivery_address: "742 Market St, San Francisco, CA 94103",
    lat: 37.7897,
    lng: -122.4001
  },
  %{
    customer_name: "Priya Patel",
    phone: "(415) 555-0102",
    items: ["Pepperoni Pizza (Medium)", "Caesar Salad", "Diet Coke x2"],
    status: "preparing",
    delivery_address: "1600 Fillmore St, San Francisco, CA 94115",
    lat: 37.7843,
    lng: -122.4329
  },
  %{
    customer_name: "Jordan Williams",
    phone: "(415) 555-0103",
    items: [
      "BBQ Chicken Pizza (Large)",
      "Buffalo Wings (12pc)",
      "Ranch Dipping Sauce",
      "Lemonade"
    ],
    status: "out_for_delivery",
    delivery_address: "555 California St, San Francisco, CA 94104",
    lat: 37.7929,
    lng: -122.4034
  },
  %{
    customer_name: "Sofia Rosario",
    phone: "(415) 555-0104",
    items: ["Veggie Supreme Pizza (Small)", "Greek Salad"],
    status: "delivered",
    delivery_address: "2200 Judah St, San Francisco, CA 94122",
    lat: 37.7612,
    lng: -122.4871
  },
  %{
    customer_name: "Tyler Nguyen",
    phone: "(415) 555-0105",
    items: [
      "Meat Lovers Pizza (XL)",
      "Breadsticks (8pc)",
      "Marinara Sauce",
      "Root Beer x3",
      "Chocolate Lava Cake"
    ],
    status: "preparing",
    delivery_address: "88 Divisadero St, San Francisco, CA 94117",
    lat: 37.7732,
    lng: -122.4376
  },
  %{
    customer_name: "Amara Johnson",
    phone: "(415) 555-0106",
    items: ["Hawaiian Pizza (Large)", "Mozzarella Sticks", "Sprite"],
    status: "new",
    delivery_address: "1400 Valencia St, San Francisco, CA 94110",
    lat: 37.7635,
    lng: -122.4198
  },
  %{
    customer_name: "Devon Kim",
    phone: "(415) 555-0107",
    items: ["Four Cheese Pizza (Medium)", "Caprese Salad", "Sparkling Water"],
    status: "out_for_delivery",
    delivery_address: "450 Hayes St, San Francisco, CA 94102",
    lat: 37.7762,
    lng: -122.4232
  },
  %{
    customer_name: "Isabella Torres",
    phone: "(415) 555-0108",
    items: ["Spicy Arrabbiata Pizza", "Cannoli (2pc)"],
    status: "delivered",
    delivery_address: "3200 16th St, San Francisco, CA 94103",
    lat: 37.7651,
    lng: -122.4294
  }
]

Enum.each(demo_orders, fn attrs ->
  {:ok, _order} = Orders.create_order(attrs)
end)

IO.puts("✅ Seeded #{length(demo_orders)} demo orders")
