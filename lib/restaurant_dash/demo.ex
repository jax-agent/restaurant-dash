defmodule RestaurantDash.Demo do
  @moduledoc """
  Demo mode for OrderBase. Creates and seeds a demo environment (El Coquí Kitchen)
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
  @demo_slug "el-coqui-kitchen"

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
            name: "El Coquí Kitchen",
            slug: @demo_slug,
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
        name: "Aperitivos",
        description: "Appetizers to start your meal",
        position: 10
      })

    {:ok, mains_cat} =
      Menu.create_category(%{
        restaurant_id: restaurant.id,
        name: "Platos Principales",
        description: "Main dishes",
        position: 20
      })

    {:ok, drinks_cat} =
      Menu.create_category(%{
        restaurant_id: restaurant.id,
        name: "Bebidas",
        description: "Cold drinks and island favorites",
        position: 30
      })

    {:ok, desserts_cat} =
      Menu.create_category(%{
        restaurant_id: restaurant.id,
        name: "Postres",
        description: "Sweet endings",
        position: 40
      })

    # Aperitivos
    Enum.each(
      [
        %{
          name: "Alcapurrias",
          description: "Fried green banana fritters stuffed with seasoned beef",
          price: 699,
          position: 10
        },
        %{
          name: "Bacalaítos",
          description: "Crispy codfish fritters",
          price: 599,
          position: 20
        },
        %{
          name: "Tostones con Ajo",
          description: "Double-fried plantains with garlic dipping sauce",
          price: 549,
          position: 30
        },
        %{
          name: "Sorullitos",
          description: "Sweet corn fritters with mayo-ketchup",
          price: 499,
          position: 40
        }
      ],
      fn attrs ->
        Menu.create_item(
          Map.merge(attrs, %{restaurant_id: restaurant.id, menu_category_id: apps_cat.id})
        )
      end
    )

    # Platos Principales
    main_items = [
      %{
        name: "Mofongo de Pollo",
        description: "Garlic mashed plantains with roasted chicken",
        price: 1699,
        position: 10
      },
      %{
        name: "Pernil Asado",
        description: "Slow-roasted pork shoulder with rice and beans",
        price: 1899,
        position: 20
      },
      %{
        name: "Arroz con Gandules",
        description: "Puerto Rican rice with pigeon peas and sofrito",
        price: 1299,
        position: 30
      },
      %{
        name: "Churrasco a la Criolla",
        description: "Grilled skirt steak with chimichurri",
        price: 2299,
        position: 40
      },
      %{
        name: "Pollo Guisado",
        description: "Stewed chicken in tomato sofrito sauce",
        price: 1499,
        position: 50
      },
      %{
        name: "Pescado Frito",
        description: "Whole fried red snapper with tostones",
        price: 1999,
        position: 60
      }
    ]

    # Create Mofongo protein modifier group
    {:ok, protein_group} =
      Menu.create_modifier_group(%{
        restaurant_id: restaurant.id,
        name: "Mofongo Protein",
        min_selections: 1,
        max_selections: 1
      })

    Enum.each(
      [
        %{name: "Chicken", price_adjustment: 0, position: 10},
        %{name: "Shrimp", price_adjustment: 400, position: 20},
        %{name: "Churrasco", price_adjustment: 600, position: 30},
        %{name: "Vegetable", price_adjustment: 0, position: 40}
      ],
      fn attrs ->
        Menu.create_modifier(Map.merge(attrs, %{modifier_group_id: protein_group.id}))
      end
    )

    # Create spice level modifier group
    {:ok, spice_group} =
      Menu.create_modifier_group(%{
        restaurant_id: restaurant.id,
        name: "Spice Level",
        min_selections: 0,
        max_selections: 1
      })

    Enum.each(
      [
        %{name: "Mild", price_adjustment: 0, position: 10},
        %{name: "Medium", price_adjustment: 0, position: 20},
        %{name: "Picante", price_adjustment: 0, position: 30}
      ],
      fn attrs ->
        Menu.create_modifier(Map.merge(attrs, %{modifier_group_id: spice_group.id}))
      end
    )

    # Create rice choice modifier group
    {:ok, rice_group} =
      Menu.create_modifier_group(%{
        restaurant_id: restaurant.id,
        name: "Rice Choice",
        min_selections: 0,
        max_selections: 1
      })

    Enum.each(
      [
        %{name: "White Rice", price_adjustment: 0, position: 10},
        %{name: "Arroz con Gandules", price_adjustment: 0, position: 20},
        %{name: "Yellow Rice", price_adjustment: 100, position: 30}
      ],
      fn attrs ->
        Menu.create_modifier(Map.merge(attrs, %{modifier_group_id: rice_group.id}))
      end
    )

    # Create add sides modifier group
    {:ok, sides_group} =
      Menu.create_modifier_group(%{
        restaurant_id: restaurant.id,
        name: "Add Sides",
        min_selections: 0,
        max_selections: nil
      })

    Enum.each(
      [
        %{name: "Maduros", price_adjustment: 300, position: 10},
        %{name: "Tostones", price_adjustment: 300, position: 20},
        %{name: "Habichuelas", price_adjustment: 250, position: 30}
      ],
      fn attrs ->
        Menu.create_modifier(Map.merge(attrs, %{modifier_group_id: sides_group.id}))
      end
    )

    Enum.each(main_items, fn attrs ->
      {:ok, item} =
        Menu.create_item(
          Map.merge(attrs, %{restaurant_id: restaurant.id, menu_category_id: mains_cat.id})
        )

      # Add protein group only to Mofongo
      if item.name == "Mofongo de Pollo" do
        Menu.add_modifier_group_to_item(item, protein_group)
      end

      # Add spice and rice to all mains except Arroz con Gandules
      if item.name not in ["Arroz con Gandules"] do
        Menu.add_modifier_group_to_item(item, spice_group)
      end

      Menu.add_modifier_group_to_item(item, sides_group)
    end)

    # Bebidas
    Enum.each(
      [
        %{
          name: "Piña Colada (virgin)",
          description: "Classic Puerto Rican coconut-pineapple smoothie",
          price: 599,
          position: 10
        },
        %{
          name: "Malta India",
          description: "Traditional Puerto Rican malt beverage",
          price: 299,
          position: 20
        },
        %{
          name: "Café con Leche",
          description: "Puerto Rican style coffee with steamed milk",
          price: 399,
          position: 30
        },
        %{
          name: "Jugo de Parcha",
          description: "Fresh passion fruit juice",
          price: 449,
          position: 40
        },
        %{
          name: "Coquito",
          description: "Coconut eggnog (seasonal)",
          price: 699,
          position: 50
        }
      ],
      fn attrs ->
        Menu.create_item(
          Map.merge(attrs, %{restaurant_id: restaurant.id, menu_category_id: drinks_cat.id})
        )
      end
    )

    # Postres
    Enum.each(
      [
        %{
          name: "Tembleque",
          description: "Coconut pudding with cinnamon",
          price: 699,
          position: 10
        },
        %{
          name: "Flan de Queso",
          description: "Cream cheese flan",
          price: 799,
          position: 20
        },
        %{
          name: "Arroz con Dulce",
          description: "Sweet rice pudding with coconut milk",
          price: 599,
          position: 30
        },
        %{
          name: "Quesitos",
          description: "Cream cheese puff pastry",
          price: 399,
          position: 40
        }
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
        name: "Old San Juan (Main)",
        address: "123 Calle Fortaleza",
        city: "Old San Juan",
        state: "PR",
        zip: "00901",
        phone: "(787) 555-0200",
        lat: 18.4655,
        lng: -66.1057,
        is_active: true,
        is_primary: true
      })

    Locations.set_primary(loc1)

    Locations.create_location(%{
      restaurant_id: restaurant.id,
      name: "Santurce",
      address: "456 Ave Ponce de León",
      city: "Santurce",
      state: "PR",
      zip: "00907",
      phone: "(787) 555-0210",
      lat: 18.4488,
      lng: -66.0614,
      is_active: true,
      is_primary: false
    })

    Locations.create_location(%{
      restaurant_id: restaurant.id,
      name: "Ponce",
      address: "789 Calle Comercio",
      city: "Ponce",
      state: "PR",
      zip: "00731",
      phone: "(787) 555-0220",
      lat: 18.0115,
      lng: -66.6141,
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
        name: "Diego Morales",
        email: "diego.driver@demo.orderbase.com",
        vehicle_type: "car",
        license_plate: "HJK-123",
        status: "available",
        lat: 18.4655,
        lng: -66.1057
      },
      %{
        name: "Sofia Hernández",
        email: "sofia.driver@demo.orderbase.com",
        vehicle_type: "car",
        license_plate: "MNP-456",
        status: "on_delivery",
        lat: 18.4488,
        lng: -66.0614
      },
      %{
        name: "Andrés Cruz",
        email: "andres.driver@demo.orderbase.com",
        vehicle_type: "scooter",
        license_plate: "QRS-789",
        status: "available",
        lat: 18.4600,
        lng: -66.1100
      },
      %{
        name: "Elena Ramos",
        email: "elena.driver@demo.orderbase.com",
        vehicle_type: "bike",
        license_plate: "TUV-012",
        status: "offline",
        lat: 18.4550,
        lng: -66.0900
      }
    ]

    Enum.each(drivers, fn attrs ->
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
        customer_name: "María Santos",
        phone: "(787) 555-0101",
        items: ["Mofongo de Pollo", "Tostones con Ajo", "Piña Colada (virgin)"],
        status: "new",
        delivery_address: "742 Calle San Francisco, Old San Juan, PR 00901",
        lat: 18.4660,
        lng: -66.1075,
        total_amount: 3097,
        inserted_at: DateTime.add(now, -5, :minute)
      },
      %{
        customer_name: "José Rivera",
        phone: "(787) 555-0102",
        items: ["Pernil Asado", "Alcapurrias", "Malta India x2"],
        status: "preparing",
        delivery_address: "456 Ave Ponce de León, Santurce, PR 00907",
        lat: 18.4488,
        lng: -66.0614,
        total_amount: 3295,
        inserted_at: DateTime.add(now, -18, :minute)
      },
      %{
        customer_name: "Carmen López",
        phone: "(787) 555-0103",
        items: ["Churrasco a la Criolla", "Bacalaítos", "Café con Leche"],
        status: "out_for_delivery",
        delivery_address: "100 Calle Luna, Old San Juan, PR 00901",
        lat: 18.4640,
        lng: -66.1090,
        total_amount: 3497,
        inserted_at: DateTime.add(now, -35, :minute)
      },
      %{
        customer_name: "Luis Rodríguez",
        phone: "(787) 555-0104",
        items: ["Arroz con Gandules", "Sorullitos"],
        status: "delivered",
        delivery_address: "789 Calle Comercio, Ponce, PR 00731",
        lat: 18.0115,
        lng: -66.6141,
        total_amount: 1798,
        inserted_at: DateTime.add(now, -2, :hour)
      },
      %{
        customer_name: "Ana García",
        phone: "(787) 555-0105",
        items: ["Pescado Frito", "Tostones con Ajo", "Jugo de Parcha"],
        status: "preparing",
        delivery_address: "222 Ave Fernández Juncos, San Juan, PR 00901",
        lat: 18.4530,
        lng: -66.0800,
        total_amount: 3097,
        inserted_at: DateTime.add(now, -22, :minute)
      },
      %{
        customer_name: "Pedro Díaz",
        phone: "(787) 555-0106",
        items: ["Pollo Guisado", "Alcapurrias", "Coquito"],
        status: "new",
        delivery_address: "55 Calle Recinto Sur, Old San Juan, PR 00901",
        lat: 18.4620,
        lng: -66.1030,
        total_amount: 2897,
        inserted_at: DateTime.add(now, -2, :minute)
      },
      %{
        customer_name: "Rosa Martínez",
        phone: "(787) 555-0107",
        items: ["Mofongo de Pollo", "Tembleque", "Malta India"],
        status: "out_for_delivery",
        delivery_address: "340 Calle Canals, Santurce, PR 00907",
        lat: 18.4500,
        lng: -66.0650,
        total_amount: 3297,
        inserted_at: DateTime.add(now, -40, :minute)
      },
      %{
        customer_name: "Carlos Colón",
        phone: "(787) 555-0108",
        items: ["Pernil Asado", "Flan de Queso"],
        status: "delivered",
        delivery_address: "18 Calle Mayor, Ponce, PR 00730",
        lat: 18.0125,
        lng: -66.6120,
        total_amount: 2698,
        inserted_at: DateTime.add(now, -90, :minute)
      }
    ]

    # Historical orders for analytics (last 30 days)
    pr_customers = [
      "Isabel Torres",
      "Miguel Vega",
      "María Santos",
      "José Rivera",
      "Carmen López",
      "Luis Rodríguez",
      "Ana García",
      "Pedro Díaz",
      "Rosa Martínez",
      "Carlos Colón"
    ]

    pr_items = [
      "Mofongo de Pollo",
      "Pernil Asado",
      "Arroz con Gandules",
      "Pollo Guisado",
      "Pescado Frito",
      "Alcapurrias",
      "Malta India"
    ]

    historical =
      Enum.flat_map(1..30, fn days_ago ->
        count = Enum.random(3..8)

        Enum.map(1..count, fn i ->
          minutes_offset = Enum.random(0..1380)
          customer = Enum.at(pr_customers, rem(days_ago * i, length(pr_customers)))

          %{
            customer_name: customer,
            phone:
              "(787) 555-#{String.pad_leading(Integer.to_string(days_ago * 10 + i), 4, "0")}",
            items: [Enum.at(pr_items, rem(i, length(pr_items))), "Malta India"],
            status: "delivered",
            delivery_address: "#{Enum.random(100..999)} Calle San Francisco, San Juan, PR 00901",
            lat: 18.4655 + :rand.uniform() * 0.05,
            lng: -66.1057 + :rand.uniform() * 0.05,
            total_amount: Enum.random(1500..4500),
            inserted_at: DateTime.add(now, -(days_ago * 24 * 60 + minutes_offset), :minute)
          }
        end)
      end)

    Enum.each(orders ++ historical, fn attrs ->
      {inserted_at, attrs} = Map.pop(attrs, :inserted_at, now)

      case Orders.create_order(Map.put(attrs, :restaurant_id, restaurant.id)) do
        {:ok, order} ->
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
          code: "ISLAND20",
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
    existing_rewards =
      Repo.aggregate(from(lr in LoyaltyReward, where: lr.restaurant_id == ^restaurant.id), :count)

    if existing_rewards == 0 do
      Enum.each(
        [
          %{
            name: "Free Tostones",
            points_cost: 100,
            discount_value: 549,
            is_active: true
          },
          %{name: "$5 Off Your Order", points_cost: 250, discount_value: 500, is_active: true},
          %{
            name: "Free Mofongo de Pollo",
            points_cost: 500,
            discount_value: 1699,
            is_active: true
          }
        ],
        fn attrs ->
          Loyalty.create_reward(Map.put(attrs, :restaurant_id, restaurant.id))
        end
      )
    end

    existing_accounts =
      Repo.aggregate(
        from(la in LoyaltyAccount, where: la.restaurant_id == ^restaurant.id),
        :count
      )

    if existing_accounts < 5 do
      customers = [
        %{email: "maria.santos@example.com", points: 340},
        %{email: "jose.rivera@example.com", points: 175},
        %{email: "carmen.lopez@example.com", points: 520},
        %{email: "luis.rodriguez@example.com", points: 90},
        %{email: "ana.garcia@example.com", points: 210}
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
