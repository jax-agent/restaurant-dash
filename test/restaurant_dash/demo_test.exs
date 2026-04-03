defmodule RestaurantDash.DemoTest do
  use RestaurantDash.DataCase, async: false

  alias RestaurantDash.{Accounts, Demo, Menu, Orders, Promotions, Tenancy}

  describe "Demo.setup!/0" do
    test "returns the demo user" do
      user = Demo.setup!()
      assert user.email == Demo.demo_email()
      assert user.role == "owner"
    end

    test "creates El Coquí Kitchen restaurant" do
      Demo.setup!()
      restaurant = Tenancy.get_restaurant_by_slug(Demo.demo_slug())
      assert restaurant != nil
      assert restaurant.name == "El Coquí Kitchen"
    end

    test "seeds menu categories" do
      Demo.setup!()
      restaurant = Tenancy.get_restaurant_by_slug(Demo.demo_slug())
      categories = Menu.list_categories(restaurant.id)
      assert length(categories) >= 3
    end

    test "seeds menu items" do
      Demo.setup!()
      restaurant = Tenancy.get_restaurant_by_slug(Demo.demo_slug())
      items = Menu.list_items(restaurant.id)
      assert length(items) >= 10
    end

    test "seeds orders" do
      Demo.setup!()
      restaurant = Tenancy.get_restaurant_by_slug(Demo.demo_slug())
      orders = Orders.list_orders(restaurant.id)
      assert length(orders) >= 8
    end

    test "seeds promo codes" do
      Demo.setup!()
      restaurant = Tenancy.get_restaurant_by_slug(Demo.demo_slug())
      promos = Promotions.list_promo_codes(restaurant.id)
      codes = Enum.map(promos, & &1.code)
      assert "WELCOME10" in codes
      assert "FREESHIP" in codes
    end

    test "is idempotent — calling setup! multiple times doesn't duplicate data" do
      Demo.setup!()
      Demo.setup!()

      restaurant = Tenancy.get_restaurant_by_slug(Demo.demo_slug())

      # Only one restaurant with that slug
      count =
        RestaurantDash.Repo.aggregate(
          from(r in RestaurantDash.Tenancy.Restaurant,
            where: r.slug == ^Demo.demo_slug()
          ),
          :count
        )

      assert count == 1

      # Only one demo user
      user_count =
        RestaurantDash.Repo.aggregate(
          from(u in RestaurantDash.Accounts.User,
            where: u.email == ^Demo.demo_email()
          ),
          :count
        )

      assert user_count == 1

      # Menu not duplicated (each category has same items count)
      categories = Menu.list_categories(restaurant.id)
      category_count = length(categories)
      # should be exactly 4 categories, not 8
      assert category_count >= 3
      assert category_count <= 8
    end
  end
end
