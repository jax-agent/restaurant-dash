alias RestaurantDash.{Menu, Orders, Repo, Tenancy}
alias RestaurantDash.Menu.{Category, Item, Modifier, ModifierGroup}
alias RestaurantDash.Orders.Order
alias RestaurantDash.Tenancy.Restaurant

# Clear existing data (order matters due to FK constraints)
Repo.delete_all(Modifier)
Repo.delete_all(ModifierGroup)
Repo.delete_all(Item)
Repo.delete_all(Category)
Repo.delete_all(Order)
Repo.delete_all(Restaurant)

# ─── Demo Restaurants ─────────────────────────────────────────────────────

{:ok, sals} =
  Tenancy.create_restaurant(%{
    name: "Sal's Pizza",
    slug: "sals-pizza",
    description: "Authentic New York-style pizza since 1987",
    phone: "(415) 555-0200",
    address: "500 Columbus Ave",
    city: "San Francisco",
    state: "CA",
    zip: "94133",
    primary_color: "#E63946",
    timezone: "America/Los_Angeles",
    is_active: true
  })

{:ok, green_dragon} =
  Tenancy.create_restaurant(%{
    name: "Green Dragon Sushi",
    slug: "green-dragon",
    description: "Fresh sushi and Japanese cuisine",
    phone: "(415) 555-0201",
    address: "220 Kearny St",
    city: "San Francisco",
    state: "CA",
    zip: "94108",
    primary_color: "#2D6A4F",
    timezone: "America/Los_Angeles",
    is_active: true
  })

IO.puts("✅ Seeded 2 demo restaurants")

# ─── Sal's Pizza Menu ─────────────────────────────────────────────────────

{:ok, sals_apps} =
  Menu.create_category(%{
    restaurant_id: sals.id,
    name: "Appetizers",
    description: "Start your meal right",
    position: 10
  })

{:ok, sals_pizzas} =
  Menu.create_category(%{
    restaurant_id: sals.id,
    name: "Pizzas",
    description: "Hand-tossed New York-style",
    position: 20
  })

{:ok, sals_drinks} =
  Menu.create_category(%{
    restaurant_id: sals.id,
    name: "Drinks",
    description: "Cold beverages",
    position: 30
  })

# Appetizers
{:ok, _} =
  Menu.create_item(%{
    restaurant_id: sals.id,
    menu_category_id: sals_apps.id,
    name: "Garlic Bread",
    description: "Toasted bread with garlic butter",
    price: 599,
    position: 10
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: sals.id,
    menu_category_id: sals_apps.id,
    name: "Mozzarella Sticks",
    description: "Fried mozzarella with marinara sauce",
    price: 899,
    position: 20
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: sals.id,
    menu_category_id: sals_apps.id,
    name: "Buffalo Wings",
    description: "Crispy wings with your choice of sauce",
    price: 1299,
    position: 30
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: sals.id,
    menu_category_id: sals_apps.id,
    name: "Caesar Salad",
    description: "Romaine lettuce, croutons, parmesan",
    price: 999,
    position: 40
  })

# Pizzas
{:ok, _} =
  Menu.create_item(%{
    restaurant_id: sals.id,
    menu_category_id: sals_pizzas.id,
    name: "Margherita",
    description: "San Marzano tomato, fresh mozzarella, basil",
    price: 1499,
    position: 10
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: sals.id,
    menu_category_id: sals_pizzas.id,
    name: "Pepperoni",
    description: "Loaded with classic pepperoni",
    price: 1699,
    position: 20
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: sals.id,
    menu_category_id: sals_pizzas.id,
    name: "BBQ Chicken",
    description: "Tangy BBQ sauce, grilled chicken, red onion",
    price: 1899,
    position: 30
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: sals.id,
    menu_category_id: sals_pizzas.id,
    name: "Veggie Supreme",
    description: "Bell peppers, mushrooms, olives, onions",
    price: 1699,
    position: 40
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: sals.id,
    menu_category_id: sals_pizzas.id,
    name: "Meat Lovers",
    description: "Pepperoni, sausage, ham, bacon",
    price: 1999,
    position: 50
  })

# Drinks
{:ok, _} =
  Menu.create_item(%{
    restaurant_id: sals.id,
    menu_category_id: sals_drinks.id,
    name: "Coke",
    description: "Classic Coca-Cola",
    price: 299,
    position: 10
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: sals.id,
    menu_category_id: sals_drinks.id,
    name: "Diet Coke",
    description: "Coca-Cola Zero Sugar",
    price: 299,
    position: 20
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: sals.id,
    menu_category_id: sals_drinks.id,
    name: "San Pellegrino",
    description: "Italian sparkling mineral water",
    price: 399,
    position: 30
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: sals.id,
    menu_category_id: sals_drinks.id,
    name: "Lemonade",
    description: "Fresh-squeezed house lemonade",
    price: 399,
    position: 40
  })

IO.puts("✅ Seeded Sal's Pizza menu (3 categories, 13 items)")

# ─── Sal's Pizza Modifier Groups ─────────────────────────────────────────────

{:ok, pizza_sizes} =
  Menu.create_modifier_group(%{
    restaurant_id: sals.id,
    name: "Size",
    min_selections: 1,
    max_selections: 1
  })

{:ok, _} =
  Menu.create_modifier(%{
    modifier_group_id: pizza_sizes.id,
    name: "Small (10\")",
    price_adjustment: 0,
    position: 10
  })

{:ok, _} =
  Menu.create_modifier(%{
    modifier_group_id: pizza_sizes.id,
    name: "Medium (14\")",
    price_adjustment: 300,
    position: 20
  })

{:ok, _} =
  Menu.create_modifier(%{
    modifier_group_id: pizza_sizes.id,
    name: "Large (18\")",
    price_adjustment: 600,
    position: 30
  })

{:ok, pizza_toppings} =
  Menu.create_modifier_group(%{
    restaurant_id: sals.id,
    name: "Extra Toppings",
    min_selections: 0,
    max_selections: nil
  })

toppings = [
  "Pepperoni",
  "Mushrooms",
  "Bell Peppers",
  "Black Olives",
  "Onions",
  "Jalapeños",
  "Extra Cheese"
]

toppings
|> Enum.with_index(10)
|> Enum.each(fn {name, pos} ->
  {:ok, _} =
    Menu.create_modifier(%{
      modifier_group_id: pizza_toppings.id,
      name: name,
      price_adjustment: 150,
      position: pos * 10
    })
end)

IO.puts("✅ Seeded Sal's Pizza modifier groups (Size, Extra Toppings)")

# ─── Green Dragon Sushi Menu ──────────────────────────────────────────────

{:ok, gd_starters} =
  Menu.create_category(%{
    restaurant_id: green_dragon.id,
    name: "Starters",
    description: "Begin your journey",
    position: 10
  })

{:ok, gd_rolls} =
  Menu.create_category(%{
    restaurant_id: green_dragon.id,
    name: "Rolls",
    description: "Handcrafted maki and specialty rolls",
    position: 20
  })

{:ok, gd_entrees} =
  Menu.create_category(%{
    restaurant_id: green_dragon.id,
    name: "Entrees",
    description: "Full Japanese plates",
    position: 30
  })

# Starters
{:ok, _} =
  Menu.create_item(%{
    restaurant_id: green_dragon.id,
    menu_category_id: gd_starters.id,
    name: "Edamame",
    description: "Steamed salted soybeans",
    price: 499,
    position: 10
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: green_dragon.id,
    menu_category_id: gd_starters.id,
    name: "Miso Soup",
    description: "Traditional dashi broth with tofu and wakame",
    price: 399,
    position: 20
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: green_dragon.id,
    menu_category_id: gd_starters.id,
    name: "Gyoza",
    description: "Pan-fried pork and cabbage dumplings (6 pcs)",
    price: 899,
    position: 30
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: green_dragon.id,
    menu_category_id: gd_starters.id,
    name: "Agedashi Tofu",
    description: "Crispy tofu in savory dashi broth",
    price: 799,
    position: 40
  })

# Rolls
{:ok, _} =
  Menu.create_item(%{
    restaurant_id: green_dragon.id,
    menu_category_id: gd_rolls.id,
    name: "California Roll",
    description: "Crab, avocado, cucumber",
    price: 1099,
    position: 10
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: green_dragon.id,
    menu_category_id: gd_rolls.id,
    name: "Spicy Tuna Roll",
    description: "Fresh tuna with spicy aioli",
    price: 1299,
    position: 20
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: green_dragon.id,
    menu_category_id: gd_rolls.id,
    name: "Dragon Roll",
    description: "Shrimp tempura, avocado on top",
    price: 1599,
    position: 30
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: green_dragon.id,
    menu_category_id: gd_rolls.id,
    name: "Rainbow Roll",
    description: "California roll topped with assorted fish",
    price: 1799,
    position: 40
  })

# Entrees
{:ok, _} =
  Menu.create_item(%{
    restaurant_id: green_dragon.id,
    menu_category_id: gd_entrees.id,
    name: "Salmon Teriyaki",
    description: "Grilled salmon with house teriyaki glaze, rice",
    price: 2199,
    position: 10
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: green_dragon.id,
    menu_category_id: gd_entrees.id,
    name: "Chicken Katsu",
    description: "Crispy panko chicken cutlet, tonkatsu sauce",
    price: 1899,
    position: 20
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: green_dragon.id,
    menu_category_id: gd_entrees.id,
    name: "Ramen",
    description: "Rich tonkotsu broth, pork belly, soft egg, nori",
    price: 1699,
    position: 30
  })

IO.puts("✅ Seeded Green Dragon Sushi menu (3 categories, 11 items)")

# ─── Green Dragon Modifier Groups ────────────────────────────────────────────

{:ok, spice_level} =
  Menu.create_modifier_group(%{
    restaurant_id: green_dragon.id,
    name: "Spice Level",
    min_selections: 0,
    max_selections: 1
  })

["No Spice", "Mild", "Medium", "Hot", "Extra Hot"]
|> Enum.with_index(10)
|> Enum.each(fn {name, pos} ->
  {:ok, _} =
    Menu.create_modifier(%{
      modifier_group_id: spice_level.id,
      name: name,
      price_adjustment: 0,
      position: pos * 10
    })
end)

IO.puts("✅ Seeded Green Dragon modifier groups (Spice Level)")

# ─── Demo Orders (associated with Sal's Pizza) ────────────────────────────

demo_orders = [
  %{
    customer_name: "Marcus Chen",
    phone: "(415) 555-0101",
    items: ["Margherita Pizza (Large)", "Garlic Bread", "Tiramisu", "San Pellegrino"],
    status: "new",
    delivery_address: "742 Market St, San Francisco, CA 94103",
    lat: 37.7897,
    lng: -122.4001,
    restaurant_id: sals.id
  },
  %{
    customer_name: "Priya Patel",
    phone: "(415) 555-0102",
    items: ["Pepperoni Pizza (Medium)", "Caesar Salad", "Diet Coke x2"],
    status: "preparing",
    delivery_address: "1600 Fillmore St, San Francisco, CA 94115",
    lat: 37.7843,
    lng: -122.4329,
    restaurant_id: sals.id
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
    lng: -122.4034,
    restaurant_id: sals.id
  },
  %{
    customer_name: "Sofia Rosario",
    phone: "(415) 555-0104",
    items: ["Veggie Supreme Pizza (Small)", "Greek Salad"],
    status: "delivered",
    delivery_address: "2200 Judah St, San Francisco, CA 94122",
    lat: 37.7612,
    lng: -122.4871,
    restaurant_id: sals.id
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
    lng: -122.4376,
    restaurant_id: sals.id
  },
  %{
    customer_name: "Amara Johnson",
    phone: "(415) 555-0106",
    items: ["Hawaiian Pizza (Large)", "Mozzarella Sticks", "Sprite"],
    status: "new",
    delivery_address: "1400 Valencia St, San Francisco, CA 94110",
    lat: 37.7635,
    lng: -122.4198,
    restaurant_id: sals.id
  },
  %{
    customer_name: "Devon Kim",
    phone: "(415) 555-0107",
    items: ["Four Cheese Pizza (Medium)", "Caprese Salad", "Sparkling Water"],
    status: "out_for_delivery",
    delivery_address: "450 Hayes St, San Francisco, CA 94102",
    lat: 37.7762,
    lng: -122.4232,
    restaurant_id: sals.id
  },
  %{
    customer_name: "Isabella Torres",
    phone: "(415) 555-0108",
    items: ["Spicy Arrabbiata Pizza", "Cannoli (2pc)"],
    status: "delivered",
    delivery_address: "3200 16th St, San Francisco, CA 94103",
    lat: 37.7651,
    lng: -122.4294,
    restaurant_id: sals.id
  }
]

Enum.each(demo_orders, fn attrs ->
  {:ok, _order} = Orders.create_order(attrs)
end)

IO.puts("✅ Seeded #{length(demo_orders)} demo orders for #{sals.name}")
