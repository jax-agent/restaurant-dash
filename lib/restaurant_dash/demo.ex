defmodule RestaurantDash.Demo do
  @moduledoc """
  Demo mode for OrderBase. Creates and seeds a demo environment (Sal's Pizza)
  with a demo owner account (demo@orderbase.com). All operations are idempotent.
  """

  import Ecto.Query, warn: false

  alias RestaurantDash.{
    Accounts,
    Hours,
    Locations,
    Loyalty,
    Menu,
    Orders,
    Promotions,
    Repo,
    Tenancy
  }

  alias RestaurantDash.Accounts.User
  alias RestaurantDash.Drivers.DriverProfile
  alias RestaurantDash.Loyalty.{LoyaltyAccount, LoyaltyReward}
  alias RestaurantDash.Orders.Order
  alias RestaurantDash.Tenancy.Restaurant

  @demo_email "demo@orderbase.com"
  @demo_password "demo-password-orderbase-2026"
  @demo_slug "sals-pizza"

  # ─── Public API ───────────────────────────────────────────────────────────

  @doc """
  Ensures the demo environment is fully seeded and returns the demo user.
  Safe to call multiple times (fully idempotent).
  """
  def setup! do
    restaurant = ensure_restaurant()
    user = ensure_demo_user(restaurant)
    seed_restaurant(restaurant)
    user
  end

  @doc "Returns the demo user email."
  def demo_email, do: @demo_email

  @doc "Returns the demo restaurant slug."
  def demo_slug, do: @demo_slug

  # ─── Restaurant ───────────────────────────────────────────────────────────

  defp ensure_restaurant do
    case Tenancy.get_restaurant_by_slug(@demo_slug) do
      %Restaurant{} = r ->
        r

      nil ->
        {:ok, r} =
          Tenancy.create_restaurant(%{
            name: "Sal's Pizza",
            slug: @demo_slug,
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

        r
    end
  end

  # ─── Demo User ────────────────────────────────────────────────────────────

  defp ensure_demo_user(restaurant) do
    case Accounts.get_user_by_email(@demo_email) do
      %User{} = u ->
        # Ensure restaurant linkage is correct
        if u.restaurant_id != restaurant.id do
          Repo.update!(Ecto.Changeset.change(u, restaurant_id: restaurant.id, role: "owner"))
        else
          u
        end

      nil ->
        {:ok, user} =
          Accounts.register_user_with_role(%{
            email: @demo_email,
            password: @demo_password,
            name: "Demo Owner",
            role: "owner",
            restaurant_id: restaurant.id
          })

        # Auto-confirm the demo user
        user
        |> User.confirm_changeset()
        |> Repo.update!()
    end
  end

  # ─── Full Seed ────────────────────────────────────────────────────────────

  defp seed_restaurant(restaurant) do
    seed_menu(restaurant)
    seed_locations(restaurant)
    seed_hours(restaurant)
    seed_drivers(restaurant)
    seed_orders(restaurant)
    seed_promo_codes(restaurant)
    seed_loyalty(restaurant)
    :ok
  end

  # ─── Menu ─────────────────────────────────────────────────────────────────

  defp seed_menu(restaurant) do
    existing = Menu.list_categories(restaurant.id)
    if Enum.empty?(existing), do: do_seed_menu(restaurant)
  end

  defp do_seed_menu(restaurant) do
    {:ok, apps_cat} =
      Menu.create_category(%{
        restaurant_id: restaurant.id,
        name: "Appetizers",
        description: "Start your meal right",
        position: 10
      })

    {:ok, pizza_cat} =
      Menu.create_category(%{
        restaurant_id: restaurant.id,
        name: "Pizzas",
        description: "Hand-tossed New York-style",
        position: 20
      })

    {:ok, drinks_cat} =
      Menu.create_category(%{
        restaurant_id: restaurant.id,
        name: "Drinks",
        description: "Cold beverages",
        position: 30
      })

    {:ok, desserts_cat} =
      Menu.create_category(%{
        restaurant_id: restaurant.id,
        name: "Desserts",
        description: "Sweet endings",
        position: 40
      })

    # Appetizers
    Enum.each(
      [
        %{
          name: "Garlic Bread",
          description: "Toasted bread with garlic butter",
          price: 599,
          position: 10
        },
        %{
          name: "Mozzarella Sticks",
          description: "Fried mozzarella with marinara sauce",
          price: 899,
          position: 20
        },
        %{
          name: "Buffalo Wings",
          description: "Crispy wings with your choice of sauce (6 or 12 pc)",
          price: 1299,
          position: 30
        },
        %{
          name: "Caprese Salad",
          description: "Fresh tomato, mozzarella, basil",
          price: 999,
          position: 40
        },
        %{
          name: "Caesar Salad",
          description: "Classic Caesar with croutons",
          price: 899,
          position: 50
        },
        %{
          name: "Breadsticks",
          description: "Soft breadsticks with marinara",
          price: 699,
          position: 60
        }
      ],
      fn attrs ->
        Menu.create_item(
          Map.merge(attrs, %{restaurant_id: restaurant.id, menu_category_id: apps_cat.id})
        )
      end
    )

    # Pizzas — with size modifier group
    pizza_items = [
      %{
        name: "Margherita",
        description: "San Marzano tomato, fresh mozzarella, basil",
        price: 1499,
        position: 10
      },
      %{
        name: "Pepperoni",
        description: "Classic pepperoni with extra cheese",
        price: 1699,
        position: 20
      },
      %{
        name: "BBQ Chicken",
        description: "Smoky BBQ sauce, grilled chicken, red onion",
        price: 1799,
        position: 30
      },
      %{
        name: "Veggie Supreme",
        description: "Roasted peppers, mushrooms, olives, onions",
        price: 1599,
        position: 40
      },
      %{
        name: "Meat Lovers",
        description: "Pepperoni, sausage, bacon, ham",
        price: 1999,
        position: 50
      },
      %{
        name: "Hawaiian",
        description: "Ham, pineapple, jalapeños",
        price: 1699,
        position: 60
      },
      %{
        name: "Four Cheese",
        description: "Mozzarella, ricotta, gorgonzola, parmesan",
        price: 1799,
        position: 70
      },
      %{
        name: "Spicy Arrabbiata",
        description: "Spicy tomato sauce, chilis, sausage",
        price: 1799,
        position: 80
      }
    ]

    # Create size modifier group for pizzas
    {:ok, size_group} =
      Menu.create_modifier_group(%{
        restaurant_id: restaurant.id,
        name: "Size",
        min_selections: 1,
        max_selections: 1
      })

    Enum.each(
      [
        %{name: "Small (10\")", price_delta: -300, position: 10},
        %{name: "Medium (12\")", price_delta: 0, position: 20},
        %{name: "Large (14\")", price_delta: 300, position: 30},
        %{name: "XL (16\")", price_delta: 600, position: 40}
      ],
      fn attrs ->
        Menu.create_modifier(Map.merge(attrs, %{modifier_group_id: size_group.id}))
      end
    )

    Enum.each(pizza_items, fn attrs ->
      {:ok, item} =
        Menu.create_item(
          Map.merge(attrs, %{restaurant_id: restaurant.id, menu_category_id: pizza_cat.id})
        )

      Menu.add_modifier_group_to_item(item, size_group)
    end)

    # Drinks
    Enum.each(
      [
        %{name: "Coke", description: "Classic Coca-Cola", price: 299, position: 10},
        %{name: "Diet Coke", description: "Zero sugar", price: 299, position: 20},
        %{name: "Sprite", description: "Lemon-lime fizz", price: 299, position: 30},
        %{name: "Root Beer", description: "Classic root beer", price: 299, position: 40},
        %{name: "Lemonade", description: "Fresh-squeezed lemonade", price: 349, position: 50},
        %{
          name: "San Pellegrino",
          description: "Italian sparkling water",
          price: 349,
          position: 60
        },
        %{name: "Sparkling Water", description: "Sparkling water", price: 249, position: 70},
        %{name: "Iced Tea", description: "Freshly brewed", price: 249, position: 80}
      ],
      fn attrs ->
        Menu.create_item(
          Map.merge(attrs, %{restaurant_id: restaurant.id, menu_category_id: drinks_cat.id})
        )
      end
    )

    # Desserts
    Enum.each(
      [
        %{name: "Tiramisu", description: "Classic Italian tiramisu", price: 799, position: 10},
        %{name: "Cannoli", description: "Sicilian cannoli (2pc)", price: 699, position: 20},
        %{
          name: "Chocolate Lava Cake",
          description: "Warm chocolate cake with ice cream",
          price: 899,
          position: 30
        },
        %{name: "Gelato", description: "Italian gelato (3 scoops)", price: 599, position: 40}
      ],
      fn attrs ->
        Menu.create_item(
          Map.merge(attrs, %{restaurant_id: restaurant.id, menu_category_id: desserts_cat.id})
        )
      end
    )
  end

  # ─── Locations ────────────────────────────────────────────────────────────

  defp seed_locations(restaurant) do
    existing = Locations.list_locations(restaurant.id)
    if Enum.empty?(existing), do: do_seed_locations(restaurant)
  end

  defp do_seed_locations(restaurant) do
    {:ok, loc1} =
      Locations.create_location(%{
        restaurant_id: restaurant.id,
        name: "North Beach (Main)",
        address: "500 Columbus Ave",
        city: "San Francisco",
        state: "CA",
        zip: "94133",
        phone: "(415) 555-0200",
        lat: 37.8002,
        lng: -122.4090,
        is_active: true,
        is_primary: true
      })

    Locations.set_primary(loc1)

    Locations.create_location(%{
      restaurant_id: restaurant.id,
      name: "Mission District",
      address: "2400 Mission St",
      city: "San Francisco",
      state: "CA",
      zip: "94110",
      phone: "(415) 555-0210",
      lat: 37.7570,
      lng: -122.4194,
      is_active: true,
      is_primary: false
    })
  end

  # ─── Operating Hours ──────────────────────────────────────────────────────

  defp seed_hours(restaurant) do
    existing = Hours.list_hours(restaurant.id)
    if Enum.empty?(existing), do: do_seed_hours(restaurant)
  end

  defp do_seed_hours(restaurant) do
    # 0 = Sunday, 1 = Monday, ..., 6 = Saturday
    Enum.each(0..6, fn day ->
      Hours.upsert_hours(%{
        restaurant_id: restaurant.id,
        day_of_week: day,
        open_time: ~T[10:00:00],
        close_time: ~T[22:00:00],
        is_closed: false
      })
    end)
  end

  # ─── Drivers ──────────────────────────────────────────────────────────────

  defp seed_drivers(restaurant) do
    # Check if any driver users exist for this restaurant
    existing =
      Repo.all(
        from u in User,
          where: u.restaurant_id == ^restaurant.id and u.role == "driver",
          limit: 1
      )

    if Enum.empty?(existing), do: do_seed_drivers(restaurant)
  end

  defp do_seed_drivers(restaurant) do
    drivers = [
      %{
        name: "Marco Rivera",
        email: "marco.driver@demo.orderbase.com",
        vehicle_type: "car",
        license_plate: "7ABC123",
        status: "available",
        lat: 37.7983,
        lng: -122.4065
      },
      %{
        name: "Jasmine Park",
        email: "jasmine.driver@demo.orderbase.com",
        vehicle_type: "car",
        license_plate: "5DEF456",
        status: "on_delivery",
        lat: 37.7751,
        lng: -122.4193
      },
      %{
        name: "Darius Cohen",
        email: "darius.driver@demo.orderbase.com",
        vehicle_type: "scooter",
        license_plate: "3GHI789",
        status: "available",
        lat: 37.7855,
        lng: -122.4310
      },
      %{
        name: "Amara Osei",
        email: "amara.driver@demo.orderbase.com",
        vehicle_type: "bike",
        license_plate: "1JKL012",
        status: "offline",
        lat: 37.7740,
        lng: -122.4380
      }
    ]

    Enum.each(drivers, fn attrs ->
      # Create user account for this driver
      user =
        case Accounts.get_user_by_email(attrs.email) do
          %User{} = u ->
            u

          nil ->
            {:ok, u} =
              Accounts.register_user_with_role(%{
                email: attrs.email,
                password: "driver-demo-password-2026",
                name: attrs.name,
                role: "driver",
                restaurant_id: restaurant.id
              })

            u
        end

      # Create driver profile if not exists
      case Repo.get_by(DriverProfile, user_id: user.id) do
        %DriverProfile{} ->
          :ok

        nil ->
          {:ok, profile} =
            %DriverProfile{}
            |> DriverProfile.changeset(%{
              user_id: user.id,
              vehicle_type: attrs.vehicle_type,
              license_plate: attrs.license_plate,
              current_lat: attrs.lat,
              current_lng: attrs.lng,
              is_approved: true,
              status: attrs.status,
              is_available: attrs.status == "available"
            })
            |> Repo.insert()

          _ = profile
      end
    end)
  end

  # ─── Orders ───────────────────────────────────────────────────────────────

  defp seed_orders(restaurant) do
    existing_count =
      Repo.aggregate(from(o in Order, where: o.restaurant_id == ^restaurant.id), :count)

    if existing_count < 10, do: do_seed_orders(restaurant)
  end

  defp do_seed_orders(restaurant) do
    now = DateTime.utc_now()

    orders = [
      %{
        customer_name: "Marcus Chen",
        phone: "(415) 555-0101",
        items: ["Margherita (Large)", "Garlic Bread", "Tiramisu", "San Pellegrino"],
        status: "new",
        delivery_address: "742 Market St, San Francisco, CA 94103",
        lat: 37.7897,
        lng: -122.4001,
        total_amount: 3897,
        inserted_at: DateTime.add(now, -5, :minute)
      },
      %{
        customer_name: "Priya Patel",
        phone: "(415) 555-0102",
        items: ["Pepperoni (Medium)", "Caesar Salad", "Diet Coke x2"],
        status: "preparing",
        delivery_address: "1600 Fillmore St, San Francisco, CA 94115",
        lat: 37.7843,
        lng: -122.4329,
        total_amount: 2997,
        inserted_at: DateTime.add(now, -18, :minute)
      },
      %{
        customer_name: "Jordan Williams",
        phone: "(415) 555-0103",
        items: ["BBQ Chicken (Large)", "Buffalo Wings", "Lemonade"],
        status: "out_for_delivery",
        delivery_address: "555 California St, San Francisco, CA 94104",
        lat: 37.7929,
        lng: -122.4034,
        total_amount: 4197,
        inserted_at: DateTime.add(now, -35, :minute)
      },
      %{
        customer_name: "Sofia Rosario",
        phone: "(415) 555-0104",
        items: ["Veggie Supreme (Small)", "Caesar Salad"],
        status: "delivered",
        delivery_address: "2200 Judah St, San Francisco, CA 94122",
        lat: 37.7612,
        lng: -122.4871,
        total_amount: 2298,
        inserted_at: DateTime.add(now, -2, :hour)
      },
      %{
        customer_name: "Tyler Nguyen",
        phone: "(415) 555-0105",
        items: ["Meat Lovers (XL)", "Breadsticks", "Root Beer x3"],
        status: "preparing",
        delivery_address: "88 Divisadero St, San Francisco, CA 94117",
        lat: 37.7732,
        lng: -122.4376,
        total_amount: 3296,
        inserted_at: DateTime.add(now, -22, :minute)
      },
      %{
        customer_name: "Amara Johnson",
        phone: "(415) 555-0106",
        items: ["Hawaiian (Large)", "Mozzarella Sticks", "Sprite"],
        status: "new",
        delivery_address: "1400 Valencia St, San Francisco, CA 94110",
        lat: 37.7635,
        lng: -122.4198,
        total_amount: 2898,
        inserted_at: DateTime.add(now, -2, :minute)
      },
      %{
        customer_name: "Devon Kim",
        phone: "(415) 555-0107",
        items: ["Four Cheese (Medium)", "Caprese Salad", "Sparkling Water"],
        status: "out_for_delivery",
        delivery_address: "450 Hayes St, San Francisco, CA 94102",
        lat: 37.7762,
        lng: -122.4232,
        total_amount: 3047,
        inserted_at: DateTime.add(now, -40, :minute)
      },
      %{
        customer_name: "Isabella Torres",
        phone: "(415) 555-0108",
        items: ["Spicy Arrabbiata (Large)", "Cannoli x2"],
        status: "delivered",
        delivery_address: "3200 16th St, San Francisco, CA 94103",
        lat: 37.7651,
        lng: -122.4294,
        total_amount: 3197,
        inserted_at: DateTime.add(now, -90, :minute)
      }
    ]

    # Add historical orders for analytics (last 30 days)
    historical =
      Enum.flat_map(1..30, fn days_ago ->
        count = Enum.random(3..8)

        Enum.map(1..count, fn i ->
          minutes_offset = Enum.random(0..1380)

          %{
            customer_name: "Customer #{days_ago}-#{i}",
            phone:
              "(415) 555-#{String.pad_leading(Integer.to_string(days_ago * 10 + i), 4, "0")}",
            items: ["Margherita (Medium)", "Coke"],
            status: "delivered",
            delivery_address: "#{Enum.random(100..999)} Main St, San Francisco, CA 94103",
            lat: 37.77 + :rand.uniform() * 0.05,
            lng: -122.41 + :rand.uniform() * 0.05,
            total_amount: Enum.random(1500..4500),
            inserted_at: DateTime.add(now, -(days_ago * 24 * 60 + minutes_offset), :minute)
          }
        end)
      end)

    Enum.each(orders ++ historical, fn attrs ->
      {inserted_at, attrs} = Map.pop(attrs, :inserted_at, now)

      case Orders.create_order(Map.put(attrs, :restaurant_id, restaurant.id)) do
        {:ok, order} ->
          # Backdate the order for analytics
          Repo.update_all(
            from(o in Order, where: o.id == ^order.id),
            set: [inserted_at: inserted_at]
          )

        _ ->
          :ok
      end
    end)
  end

  # ─── Promo Codes ──────────────────────────────────────────────────────────

  defp seed_promo_codes(restaurant) do
    existing = Promotions.list_promo_codes(restaurant.id)

    codes_to_create =
      [
        %{
          code: "WELCOME10",
          discount_type: "percentage",
          discount_value: 10,
          max_uses: 100,
          is_active: true
        },
        %{
          code: "FREESHIP",
          discount_type: "fixed",
          discount_value: 500,
          max_uses: 50,
          is_active: true
        },
        %{
          code: "PIZZA20",
          discount_type: "percentage",
          discount_value: 20,
          max_uses: 200,
          is_active: false
        }
      ]
      |> Enum.reject(fn c ->
        Enum.any?(existing, &(&1.code == c.code))
      end)

    Enum.each(codes_to_create, fn attrs ->
      Promotions.create_promo_code(Map.put(attrs, :restaurant_id, restaurant.id))
    end)
  end

  # ─── Loyalty ──────────────────────────────────────────────────────────────

  defp seed_loyalty(restaurant) do
    existing_accounts =
      Repo.aggregate(
        from(la in LoyaltyAccount, where: la.restaurant_id == ^restaurant.id),
        :count
      )

    existing_rewards =
      Repo.aggregate(from(lr in LoyaltyReward, where: lr.restaurant_id == ^restaurant.id), :count)

    if existing_rewards == 0 do
      Enum.each(
        [
          %{name: "Free Garlic Bread", points_cost: 100, discount_value: 599, is_active: true},
          %{name: "$5 Off Your Order", points_cost: 250, discount_value: 500, is_active: true},
          %{name: "Free Large Pizza", points_cost: 500, discount_value: 1799, is_active: true}
        ],
        fn attrs ->
          Loyalty.create_reward(Map.put(attrs, :restaurant_id, restaurant.id))
        end
      )
    end

    if existing_accounts < 5 do
      customers = [
        %{email: "marcus.chen@example.com", points: 340},
        %{email: "priya.patel@example.com", points: 175},
        %{email: "sofia.rosario@example.com", points: 520},
        %{email: "tyler.nguyen@example.com", points: 90},
        %{email: "amara.johnson@example.com", points: 210}
      ]

      Enum.each(customers, fn %{email: email, points: points} ->
        {:ok, account} = Loyalty.get_or_create_account(restaurant.id, email)

        if account.points_balance < points do
          Loyalty.award_points(restaurant.id, email, points - account.points_balance)
        end
      end)
    end
  end
end
