defmodule RestaurantDash.TenancyTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Tenancy
  alias RestaurantDash.Tenancy.Restaurant

  @valid_attrs %{
    name: "Sal's Pizza",
    slug: "sals-pizza",
    description: "Best pizza in town",
    phone: "(415) 555-1234",
    address: "100 Main St",
    city: "San Francisco",
    state: "CA",
    zip: "94105",
    primary_color: "#E63946",
    timezone: "America/Los_Angeles"
  }

  describe "restaurants CRUD" do
    test "list_restaurants/0 returns all restaurants" do
      assert {:ok, _} = Tenancy.create_restaurant(@valid_attrs)
      restaurants = Tenancy.list_restaurants()
      assert length(restaurants) >= 1
    end

    test "get_restaurant!/1 returns the restaurant" do
      {:ok, restaurant} = Tenancy.create_restaurant(@valid_attrs)
      assert Tenancy.get_restaurant!(restaurant.id).id == restaurant.id
    end

    test "get_restaurant/1 returns nil for missing id" do
      assert Tenancy.get_restaurant(999_999) == nil
    end

    test "get_restaurant_by_slug/1 finds by slug" do
      {:ok, restaurant} = Tenancy.create_restaurant(@valid_attrs)
      assert Tenancy.get_restaurant_by_slug("sals-pizza").id == restaurant.id
    end

    test "get_restaurant_by_slug/1 returns nil for unknown slug" do
      assert Tenancy.get_restaurant_by_slug("does-not-exist") == nil
    end

    test "create_restaurant/1 with valid data creates a restaurant" do
      assert {:ok, %Restaurant{} = r} = Tenancy.create_restaurant(@valid_attrs)
      assert r.name == "Sal's Pizza"
      assert r.slug == "sals-pizza"
    end

    test "create_restaurant/1 requires name" do
      attrs = Map.delete(@valid_attrs, :name)
      assert {:error, changeset} = Tenancy.create_restaurant(attrs)
      assert "can't be blank" in errors_on(changeset).name
    end

    test "create_restaurant/1 requires slug" do
      attrs = Map.delete(@valid_attrs, :slug)
      assert {:error, changeset} = Tenancy.create_restaurant(attrs)
      assert "can't be blank" in errors_on(changeset).slug
    end

    test "create_restaurant/1 enforces unique slug" do
      {:ok, _} = Tenancy.create_restaurant(@valid_attrs)
      assert {:error, changeset} = Tenancy.create_restaurant(@valid_attrs)
      assert "has already been taken" in errors_on(changeset).slug
    end

    test "create_restaurant/1 validates slug format" do
      attrs = Map.put(@valid_attrs, :slug, "Invalid Slug!")
      assert {:error, changeset} = Tenancy.create_restaurant(attrs)
      assert "must be lowercase letters, numbers, and hyphens only" in errors_on(changeset).slug
    end

    test "create_restaurant/1 validates primary_color format" do
      attrs = Map.put(@valid_attrs, :primary_color, "red")
      assert {:error, changeset} = Tenancy.create_restaurant(attrs)
      assert "must be a valid hex color like #RRGGBB" in errors_on(changeset).primary_color
    end

    test "update_restaurant/2 with valid data updates the restaurant" do
      {:ok, restaurant} = Tenancy.create_restaurant(@valid_attrs)
      assert {:ok, updated} = Tenancy.update_restaurant(restaurant, %{name: "Sal's Pizzeria"})
      assert updated.name == "Sal's Pizzeria"
    end

    test "delete_restaurant/1 deletes the restaurant" do
      {:ok, restaurant} = Tenancy.create_restaurant(@valid_attrs)
      assert {:ok, _} = Tenancy.delete_restaurant(restaurant)
      assert Tenancy.get_restaurant(restaurant.id) == nil
    end

    test "change_restaurant/1 returns a changeset" do
      {:ok, restaurant} = Tenancy.create_restaurant(@valid_attrs)
      assert %Ecto.Changeset{} = Tenancy.change_restaurant(restaurant)
    end
  end

  describe "slugify/1" do
    test "converts name to lowercase slug" do
      assert Tenancy.slugify("Sal's Pizza") == "sals-pizza"
    end

    test "handles spaces" do
      assert Tenancy.slugify("Green Dragon Sushi") == "green-dragon-sushi"
    end

    test "removes special characters" do
      assert Tenancy.slugify("Joe's BBQ & Grill!") == "joes-bbq-grill"
    end

    test "collapses multiple hyphens" do
      assert Tenancy.slugify("A  B") == "a-b"
    end
  end

  describe "scoped order queries" do
    alias RestaurantDash.Orders

    test "orders are scoped by restaurant_id" do
      {:ok, r1} = Tenancy.create_restaurant(@valid_attrs)

      {:ok, r2} =
        Tenancy.create_restaurant(%{@valid_attrs | name: "Green Dragon", slug: "green-dragon"})

      {:ok, _} =
        Orders.create_order(%{
          customer_name: "Alice",
          items: ["Sushi"],
          restaurant_id: r1.id
        })

      {:ok, _} =
        Orders.create_order(%{
          customer_name: "Bob",
          items: ["Pizza"],
          restaurant_id: r2.id
        })

      r1_orders = Orders.list_orders(r1.id)
      r2_orders = Orders.list_orders(r2.id)

      assert length(r1_orders) == 1
      assert hd(r1_orders).customer_name == "Alice"
      assert length(r2_orders) == 1
      assert hd(r2_orders).customer_name == "Bob"
    end

    test "list_orders/0 without restaurant_id returns all orders" do
      {:ok, r1} = Tenancy.create_restaurant(@valid_attrs)

      {:ok, _} =
        Orders.create_order(%{customer_name: "Alice", items: ["Sushi"], restaurant_id: r1.id})

      {:ok, _} =
        Orders.create_order(%{customer_name: "Bob", items: ["Pizza"], restaurant_id: r1.id})

      assert length(Orders.list_orders()) >= 2
    end

    test "count_by_status scopes by restaurant" do
      {:ok, r1} = Tenancy.create_restaurant(@valid_attrs)

      {:ok, _} =
        Orders.create_order(%{
          customer_name: "A",
          items: ["X"],
          status: "new",
          restaurant_id: r1.id
        })

      {:ok, _} =
        Orders.create_order(%{
          customer_name: "B",
          items: ["Y"],
          status: "new",
          restaurant_id: r1.id
        })

      counts = Orders.count_by_status(r1.id)
      assert counts["new"] == 2
    end
  end
end
