alias RestaurantDash.{Menu, Orders, Repo, Tenancy}
alias RestaurantDash.Menu.{Category, Item, Modifier, ModifierGroup}
alias RestaurantDash.Orders.{Order, OrderItem}
alias RestaurantDash.Tenancy.Restaurant

# Clear existing data (order matters due to FK constraints)
Repo.delete_all(OrderItem)
Repo.delete_all(Modifier)
Repo.delete_all(ModifierGroup)
Repo.delete_all(Item)
Repo.delete_all(Category)
Repo.delete_all(Order)
Repo.delete_all(Restaurant)

# ─── Demo Restaurants ─────────────────────────────────────────────────────

{:ok, coqui} =
  Tenancy.create_restaurant(%{
    name: "El Coquí Kitchen",
    slug: "el-coqui-kitchen",
    description: "Authentic Puerto Rican cuisine — from our kitchen to your door",
    phone: "(787) 555-0200",
    address: "123 Calle Fortaleza",
    city: "Old San Juan",
    state: "PR",
    zip: "00901",
    primary_color: "#E63946",
    timezone: "America/Puerto_Rico",
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

# ─── El Coquí Kitchen Menu ─────────────────────────────────────────────────────

{:ok, aperitivos} =
  Menu.create_category(%{
    restaurant_id: coqui.id,
    name: "Aperitivos",
    description: "Appetizers to start your meal",
    position: 10
  })

{:ok, platos} =
  Menu.create_category(%{
    restaurant_id: coqui.id,
    name: "Platos Principales",
    description: "Main dishes",
    position: 20
  })

{:ok, bebidas} =
  Menu.create_category(%{
    restaurant_id: coqui.id,
    name: "Bebidas",
    description: "Cold drinks and island favorites",
    position: 30
  })

{:ok, postres} =
  Menu.create_category(%{
    restaurant_id: coqui.id,
    name: "Postres",
    description: "Sweet endings",
    position: 40
  })

# Aperitivos
{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: aperitivos.id,
    name: "Alcapurrias",
    description: "Fried green banana fritters stuffed with seasoned beef",
    price: 699,
    position: 10
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: aperitivos.id,
    name: "Bacalaítos",
    description: "Crispy codfish fritters",
    price: 599,
    position: 20
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: aperitivos.id,
    name: "Tostones con Ajo",
    description: "Double-fried plantains with garlic dipping sauce",
    price: 549,
    position: 30
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: aperitivos.id,
    name: "Sorullitos",
    description: "Sweet corn fritters with mayo-ketchup",
    price: 499,
    position: 40
  })

# Platos Principales
{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: platos.id,
    name: "Mofongo de Pollo",
    description: "Garlic mashed plantains with roasted chicken",
    price: 1699,
    position: 10
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: platos.id,
    name: "Pernil Asado",
    description: "Slow-roasted pork shoulder with rice and beans",
    price: 1899,
    position: 20
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: platos.id,
    name: "Arroz con Gandules",
    description: "Puerto Rican rice with pigeon peas and sofrito",
    price: 1299,
    position: 30
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: platos.id,
    name: "Churrasco a la Criolla",
    description: "Grilled skirt steak with chimichurri",
    price: 2299,
    position: 40
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: platos.id,
    name: "Pollo Guisado",
    description: "Stewed chicken in tomato sofrito sauce",
    price: 1499,
    position: 50
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: platos.id,
    name: "Pescado Frito",
    description: "Whole fried red snapper with tostones",
    price: 1999,
    position: 60
  })

# Bebidas
{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: bebidas.id,
    name: "Piña Colada (virgin)",
    description: "Classic Puerto Rican coconut-pineapple smoothie",
    price: 599,
    position: 10
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: bebidas.id,
    name: "Malta India",
    description: "Traditional Puerto Rican malt beverage",
    price: 299,
    position: 20
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: bebidas.id,
    name: "Café con Leche",
    description: "Puerto Rican style coffee with steamed milk",
    price: 399,
    position: 30
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: bebidas.id,
    name: "Jugo de Parcha",
    description: "Fresh passion fruit juice",
    price: 449,
    position: 40
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: bebidas.id,
    name: "Coquito",
    description: "Coconut eggnog (seasonal)",
    price: 699,
    position: 50
  })

# Postres
{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: postres.id,
    name: "Tembleque",
    description: "Coconut pudding with cinnamon",
    price: 699,
    position: 10
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: postres.id,
    name: "Flan de Queso",
    description: "Cream cheese flan",
    price: 799,
    position: 20
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: postres.id,
    name: "Arroz con Dulce",
    description: "Sweet rice pudding with coconut milk",
    price: 599,
    position: 30
  })

{:ok, _} =
  Menu.create_item(%{
    restaurant_id: coqui.id,
    menu_category_id: postres.id,
    name: "Quesitos",
    description: "Cream cheese puff pastry",
    price: 399,
    position: 40
  })

IO.puts("✅ Seeded El Coquí Kitchen menu (4 categories, 20 items)")

# ─── El Coquí Kitchen Modifier Groups ─────────────────────────────────────────

{:ok, protein_group} =
  Menu.create_modifier_group(%{
    restaurant_id: coqui.id,
    name: "Mofongo Protein",
    min_selections: 1,
    max_selections: 1
  })

[
  %{name: "Chicken", price_adjustment: 0, position: 10},
  %{name: "Shrimp", price_adjustment: 400, position: 20},
  %{name: "Churrasco", price_adjustment: 600, position: 30},
  %{name: "Vegetable", price_adjustment: 0, position: 40}
]
|> Enum.each(fn attrs ->
  {:ok, _} =
    Menu.create_modifier(%{
      modifier_group_id: protein_group.id,
      name: attrs.name,
      price_adjustment: attrs.price_adjustment,
      position: attrs.position
    })
end)

{:ok, spice_group} =
  Menu.create_modifier_group(%{
    restaurant_id: coqui.id,
    name: "Spice Level",
    min_selections: 0,
    max_selections: 1
  })

["Mild", "Medium", "Picante"]
|> Enum.with_index(1)
|> Enum.each(fn {name, pos} ->
  {:ok, _} =
    Menu.create_modifier(%{
      modifier_group_id: spice_group.id,
      name: name,
      price_adjustment: 0,
      position: pos * 10
    })
end)

{:ok, rice_group} =
  Menu.create_modifier_group(%{
    restaurant_id: coqui.id,
    name: "Rice Choice",
    min_selections: 0,
    max_selections: 1
  })

[
  %{name: "White Rice", price_adjustment: 0, position: 10},
  %{name: "Arroz con Gandules", price_adjustment: 0, position: 20},
  %{name: "Yellow Rice", price_adjustment: 100, position: 30}
]
|> Enum.each(fn attrs ->
  {:ok, _} =
    Menu.create_modifier(%{
      modifier_group_id: rice_group.id,
      name: attrs.name,
      price_adjustment: attrs.price_adjustment,
      position: attrs.position
    })
end)

{:ok, sides_group} =
  Menu.create_modifier_group(%{
    restaurant_id: coqui.id,
    name: "Add Sides",
    min_selections: 0,
    max_selections: nil
  })

[
  %{name: "Maduros", price_adjustment: 300, position: 10},
  %{name: "Tostones", price_adjustment: 300, position: 20},
  %{name: "Habichuelas", price_adjustment: 250, position: 30}
]
|> Enum.each(fn attrs ->
  {:ok, _} =
    Menu.create_modifier(%{
      modifier_group_id: sides_group.id,
      name: attrs.name,
      price_adjustment: attrs.price_adjustment,
      position: attrs.position
    })
end)

IO.puts(
  "✅ Seeded El Coquí Kitchen modifier groups (Mofongo Protein, Spice Level, Rice Choice, Add Sides)"
)

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

# ─── Demo Orders (associated with El Coquí Kitchen) ────────────────────────────

demo_orders = [
  %{
    customer_name: "María Santos",
    phone: "(787) 555-0101",
    items: ["Mofongo de Pollo", "Tostones con Ajo", "Piña Colada (virgin)"],
    status: "new",
    delivery_address: "742 Calle San Francisco, Old San Juan, PR 00901",
    lat: 18.4660,
    lng: -66.1075,
    restaurant_id: coqui.id
  },
  %{
    customer_name: "José Rivera",
    phone: "(787) 555-0102",
    items: ["Pernil Asado", "Alcapurrias", "Malta India x2"],
    status: "preparing",
    delivery_address: "456 Ave Ponce de León, Santurce, PR 00907",
    lat: 18.4488,
    lng: -66.0614,
    restaurant_id: coqui.id
  },
  %{
    customer_name: "Carmen López",
    phone: "(787) 555-0103",
    items: ["Churrasco a la Criolla", "Bacalaítos", "Café con Leche"],
    status: "out_for_delivery",
    delivery_address: "100 Calle Luna, Old San Juan, PR 00901",
    lat: 18.4640,
    lng: -66.1090,
    restaurant_id: coqui.id
  },
  %{
    customer_name: "Luis Rodríguez",
    phone: "(787) 555-0104",
    items: ["Arroz con Gandules", "Sorullitos"],
    status: "delivered",
    delivery_address: "789 Calle Comercio, Ponce, PR 00731",
    lat: 18.0115,
    lng: -66.6141,
    restaurant_id: coqui.id
  },
  %{
    customer_name: "Ana García",
    phone: "(787) 555-0105",
    items: ["Pescado Frito", "Tostones con Ajo", "Jugo de Parcha"],
    status: "preparing",
    delivery_address: "222 Ave Fernández Juncos, San Juan, PR 00901",
    lat: 18.4530,
    lng: -66.0800,
    restaurant_id: coqui.id
  },
  %{
    customer_name: "Pedro Díaz",
    phone: "(787) 555-0106",
    items: ["Pollo Guisado", "Alcapurrias", "Coquito"],
    status: "new",
    delivery_address: "55 Calle Recinto Sur, Old San Juan, PR 00901",
    lat: 18.4620,
    lng: -66.1030,
    restaurant_id: coqui.id
  },
  %{
    customer_name: "Rosa Martínez",
    phone: "(787) 555-0107",
    items: ["Mofongo de Pollo", "Tembleque", "Malta India"],
    status: "out_for_delivery",
    delivery_address: "340 Calle Canals, Santurce, PR 00907",
    lat: 18.4500,
    lng: -66.0650,
    restaurant_id: coqui.id
  },
  %{
    customer_name: "Carlos Colón",
    phone: "(787) 555-0108",
    items: ["Pernil Asado", "Flan de Queso"],
    status: "delivered",
    delivery_address: "18 Calle Mayor, Ponce, PR 00730",
    lat: 18.0125,
    lng: -66.6120,
    restaurant_id: coqui.id
  }
]

Enum.each(demo_orders, fn attrs ->
  {:ok, _order} = Orders.create_order(attrs)
end)

IO.puts("✅ Seeded #{length(demo_orders)} demo orders for #{coqui.name}")
