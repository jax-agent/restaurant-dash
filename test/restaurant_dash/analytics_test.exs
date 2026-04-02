defmodule RestaurantDash.AnalyticsTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Analytics
  alias RestaurantDash.Repo
  alias RestaurantDash.Tenancy.Restaurant
  alias RestaurantDash.Orders.{Order, OrderItem}
  alias RestaurantDash.Menu.{Category, Item}

  # ── Fixtures ────────────────────────────────────────────────────────────────

  defp restaurant_fixture(attrs \\ %{}) do
    {:ok, restaurant} =
      %Restaurant{}
      |> Restaurant.changeset(
        Map.merge(
          %{
            name: "Test Restaurant #{System.unique_integer()}",
            slug: "test-#{System.unique_integer()}",
            primary_color: "#ff0000"
          },
          attrs
        )
      )
      |> Repo.insert()

    restaurant
  end

  defp category_fixture(restaurant_id, attrs \\ %{}) do
    {:ok, cat} =
      %Category{}
      |> Category.changeset(
        Map.merge(%{name: "Cat #{System.unique_integer()}", restaurant_id: restaurant_id}, attrs)
      )
      |> Repo.insert()

    cat
  end

  defp menu_item_fixture(restaurant_id, category_id, attrs \\ %{}) do
    {:ok, item} =
      %Item{}
      |> Item.changeset(
        Map.merge(
          %{
            name: "Item #{System.unique_integer()}",
            price: 1000,
            restaurant_id: restaurant_id,
            menu_category_id: category_id
          },
          attrs
        )
      )
      |> Repo.insert()

    item
  end

  defp order_fixture(restaurant_id, attrs \\ %{}) do
    now = Map.get(attrs, :inserted_at, DateTime.utc_now() |> DateTime.truncate(:second))

    {:ok, order} =
      %Order{}
      |> Order.cart_order_changeset(
        Map.merge(
          %{
            customer_name: "Customer #{System.unique_integer()}",
            customer_email: "customer#{System.unique_integer()}@test.com",
            customer_phone: "+15551234567",
            delivery_address: "123 Test St",
            restaurant_id: restaurant_id,
            subtotal: 1000,
            tax_amount: 80,
            delivery_fee: 200,
            tip_amount: 150,
            total_amount: 1430,
            status: "delivered"
          },
          attrs
        )
      )
      |> Repo.insert()

    # Update inserted_at directly if custom date is needed
    if Map.has_key?(attrs, :inserted_at) do
      order
      |> Ecto.Changeset.change(inserted_at: now)
      |> Repo.update!()
    else
      order
    end
  end

  defp order_item_fixture(order_id, menu_item_id, attrs \\ %{}) do
    {:ok, item} =
      %OrderItem{}
      |> OrderItem.changeset(
        Map.merge(
          %{
            name: "Test Item",
            quantity: 1,
            unit_price: 1000,
            line_total: 1000,
            order_id: order_id,
            menu_item_id: menu_item_id
          },
          attrs
        )
      )
      |> Repo.insert()

    item
  end

  # ── Helper ──────────────────────────────────────────────────────────────────

  defp days_ago(n) do
    DateTime.utc_now()
    |> DateTime.add(-n * 86_400, :second)
    |> DateTime.truncate(:second)
  end

  defp date_range(start_days_ago, end_days_ago \\ 0) do
    start_date = DateTime.utc_now() |> DateTime.add(-start_days_ago * 86_400, :second)
    end_date = DateTime.utc_now() |> DateTime.add(-end_days_ago * 86_400, :second)
    {start_date, end_date}
  end

  # ── revenue_summary/3 ──────────────────────────────────────────────────────

  describe "revenue_summary/3" do
    test "returns zeroes for empty dataset" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      result = Analytics.revenue_summary(restaurant.id, start_dt, end_dt)

      assert result.total_revenue == 0
      assert result.order_count == 0
      assert result.avg_order_value == 0
      assert result.total_tips == 0
    end

    test "calculates revenue for delivered orders" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      order_fixture(restaurant.id, %{total_amount: 1500, tip_amount: 200, status: "delivered"})
      order_fixture(restaurant.id, %{total_amount: 2000, tip_amount: 300, status: "delivered"})

      result = Analytics.revenue_summary(restaurant.id, start_dt, end_dt)

      assert result.total_revenue == 3500
      assert result.order_count == 2
      assert result.avg_order_value == 1750
      assert result.total_tips == 500
    end

    test "excludes cancelled orders from revenue" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      order_fixture(restaurant.id, %{total_amount: 1500, tip_amount: 200, status: "delivered"})
      order_fixture(restaurant.id, %{total_amount: 2000, tip_amount: 300, status: "cancelled"})

      result = Analytics.revenue_summary(restaurant.id, start_dt, end_dt)

      assert result.total_revenue == 1500
      assert result.order_count == 1
    end

    test "respects date range filter" do
      restaurant = restaurant_fixture()
      yesterday_start = days_ago(1)
      today_end = DateTime.utc_now()

      # old order (outside range)
      order_fixture(restaurant.id, %{
        total_amount: 5000,
        tip_amount: 500,
        status: "delivered",
        inserted_at: days_ago(10)
      })

      # recent order (inside range)
      order_fixture(restaurant.id, %{total_amount: 1500, tip_amount: 200, status: "delivered"})

      result = Analytics.revenue_summary(restaurant.id, yesterday_start, today_end)

      assert result.total_revenue == 1500
      assert result.order_count == 1
    end

    test "scopes by restaurant_id" do
      restaurant1 = restaurant_fixture()
      restaurant2 = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      order_fixture(restaurant1.id, %{total_amount: 1500, status: "delivered"})
      order_fixture(restaurant2.id, %{total_amount: 9999, status: "delivered"})

      result = Analytics.revenue_summary(restaurant1.id, start_dt, end_dt)

      assert result.total_revenue == 1500
      assert result.order_count == 1
    end

    test "includes all non-cancelled, non-new statuses" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      for status <- ~w(delivered out_for_delivery preparing accepted ready picked_up) do
        order_fixture(restaurant.id, %{total_amount: 1000, tip_amount: 100, status: status})
      end

      result = Analytics.revenue_summary(restaurant.id, start_dt, end_dt)
      assert result.order_count == 6
    end
  end

  # ── orders_by_status/3 ─────────────────────────────────────────────────────

  describe "orders_by_status/3" do
    test "returns empty map for no orders" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      result = Analytics.orders_by_status(restaurant.id, start_dt, end_dt)
      assert result == %{}
    end

    test "groups orders by status" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      order_fixture(restaurant.id, %{status: "delivered"})
      order_fixture(restaurant.id, %{status: "delivered"})
      order_fixture(restaurant.id, %{status: "cancelled"})

      result = Analytics.orders_by_status(restaurant.id, start_dt, end_dt)

      assert result["delivered"] == 2
      assert result["cancelled"] == 1
    end

    test "scopes by restaurant and date range" do
      restaurant1 = restaurant_fixture()
      restaurant2 = restaurant_fixture()
      {start_dt, end_dt} = date_range(7)

      order_fixture(restaurant1.id, %{status: "delivered"})
      order_fixture(restaurant2.id, %{status: "delivered"})

      result = Analytics.orders_by_status(restaurant1.id, start_dt, end_dt)
      assert result["delivered"] == 1
      assert Map.get(result, "cancelled") == nil
    end
  end

  # ── orders_by_hour/3 ───────────────────────────────────────────────────────

  describe "orders_by_hour/3" do
    test "returns empty list for no orders" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      result = Analytics.orders_by_hour(restaurant.id, start_dt, end_dt)
      assert result == []
    end

    test "returns order counts by hour" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      order_fixture(restaurant.id, %{status: "delivered"})
      order_fixture(restaurant.id, %{status: "delivered"})

      result = Analytics.orders_by_hour(restaurant.id, start_dt, end_dt)

      assert is_list(result)
      assert length(result) > 0

      # Each entry should have hour and count
      Enum.each(result, fn entry ->
        assert Map.has_key?(entry, :hour)
        assert Map.has_key?(entry, :count)
        assert entry.hour >= 0 and entry.hour <= 23
        assert entry.count > 0
      end)

      total = Enum.reduce(result, 0, &(&1.count + &2))
      assert total == 2
    end

    test "scopes by restaurant" do
      restaurant1 = restaurant_fixture()
      restaurant2 = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      order_fixture(restaurant1.id)
      order_fixture(restaurant2.id)
      order_fixture(restaurant2.id)

      result = Analytics.orders_by_hour(restaurant1.id, start_dt, end_dt)
      total = Enum.reduce(result, 0, &(&1.count + &2))
      assert total == 1
    end
  end

  # ── orders_by_day/3 ────────────────────────────────────────────────────────

  describe "orders_by_day/3" do
    test "returns empty list for no orders" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      result = Analytics.orders_by_day(restaurant.id, start_dt, end_dt)
      assert result == []
    end

    test "groups orders by date" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      order_fixture(restaurant.id, %{status: "delivered"})
      order_fixture(restaurant.id, %{status: "delivered"})

      result = Analytics.orders_by_day(restaurant.id, start_dt, end_dt)

      assert is_list(result)
      assert length(result) >= 1

      Enum.each(result, fn entry ->
        assert Map.has_key?(entry, :date)
        assert Map.has_key?(entry, :count)
        assert entry.count > 0
      end)

      total = Enum.reduce(result, 0, &(&1.count + &2))
      assert total == 2
    end

    test "respects date range" do
      restaurant = restaurant_fixture()
      recent_start = days_ago(2)
      recent_end = DateTime.utc_now()

      # old order (outside range)
      order_fixture(restaurant.id, %{inserted_at: days_ago(10), status: "delivered"})
      # recent order (inside range)
      order_fixture(restaurant.id, %{status: "delivered"})

      result = Analytics.orders_by_day(restaurant.id, recent_start, recent_end)
      total = Enum.reduce(result, 0, &(&1.count + &2))
      assert total == 1
    end
  end

  # ── top_items/3 ────────────────────────────────────────────────────────────

  describe "top_items/3" do
    test "returns empty list when no orders" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      result = Analytics.top_items(restaurant.id, start_dt, end_dt)
      assert result == []
    end

    test "ranks items by order count" do
      restaurant = restaurant_fixture()
      cat = category_fixture(restaurant.id)
      item1 = menu_item_fixture(restaurant.id, cat.id, %{name: "Pizza"})
      item2 = menu_item_fixture(restaurant.id, cat.id, %{name: "Pasta"})
      {start_dt, end_dt} = date_range(30)

      order1 = order_fixture(restaurant.id)
      order2 = order_fixture(restaurant.id)
      order3 = order_fixture(restaurant.id)

      order_item_fixture(order1.id, item1.id, %{name: "Pizza", quantity: 2, line_total: 2000})
      order_item_fixture(order2.id, item1.id, %{name: "Pizza", quantity: 1, line_total: 1000})
      order_item_fixture(order3.id, item2.id, %{name: "Pasta", quantity: 1, line_total: 1000})

      result = Analytics.top_items(restaurant.id, start_dt, end_dt)

      assert length(result) >= 2
      [first | _] = result
      assert first.menu_item_id == item1.id
      assert first.total_quantity >= 3
    end

    test "scopes by restaurant" do
      restaurant1 = restaurant_fixture()
      restaurant2 = restaurant_fixture()
      cat1 = category_fixture(restaurant1.id)
      cat2 = category_fixture(restaurant2.id)
      item1 = menu_item_fixture(restaurant1.id, cat1.id)
      item2 = menu_item_fixture(restaurant2.id, cat2.id)
      {start_dt, end_dt} = date_range(30)

      order1 = order_fixture(restaurant1.id)
      order2 = order_fixture(restaurant2.id)
      order_item_fixture(order1.id, item1.id, %{name: "Item1"})
      order_item_fixture(order2.id, item2.id, %{name: "Item2"})

      result = Analytics.top_items(restaurant1.id, start_dt, end_dt)
      assert Enum.all?(result, fn r -> r.menu_item_id == item1.id end)
    end
  end

  # ── revenue_by_category/3 ─────────────────────────────────────────────────

  describe "revenue_by_category/3" do
    test "returns empty list when no data" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      result = Analytics.revenue_by_category(restaurant.id, start_dt, end_dt)
      assert result == []
    end

    test "groups revenue by menu category" do
      restaurant = restaurant_fixture()
      cat1 = category_fixture(restaurant.id, %{name: "Pizza"})
      cat2 = category_fixture(restaurant.id, %{name: "Drinks"})
      item1 = menu_item_fixture(restaurant.id, cat1.id)
      item2 = menu_item_fixture(restaurant.id, cat2.id)
      {start_dt, end_dt} = date_range(30)

      order1 = order_fixture(restaurant.id)
      order2 = order_fixture(restaurant.id)
      order_item_fixture(order1.id, item1.id, %{name: "P", line_total: 1500})
      order_item_fixture(order2.id, item2.id, %{name: "D", line_total: 500})

      result = Analytics.revenue_by_category(restaurant.id, start_dt, end_dt)

      assert length(result) == 2
      pizza_cat = Enum.find(result, &(&1.category_name == "Pizza"))
      assert pizza_cat.total_revenue == 1500
    end
  end

  # ── customer_summary/3 ────────────────────────────────────────────────────

  describe "customer_summary/3" do
    test "returns zeroes for empty dataset" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      result = Analytics.customer_summary(restaurant.id, start_dt, end_dt)

      assert result.unique_customers == 0
      assert result.repeat_customers == 0
      assert result.repeat_rate == 0.0
    end

    test "counts unique customers by email" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      order_fixture(restaurant.id, %{customer_email: "alice@test.com"})
      order_fixture(restaurant.id, %{customer_email: "alice@test.com"})
      order_fixture(restaurant.id, %{customer_email: "bob@test.com"})

      result = Analytics.customer_summary(restaurant.id, start_dt, end_dt)

      assert result.unique_customers == 2
      assert result.repeat_customers == 1
      assert result.repeat_rate > 0
    end

    test "scopes by restaurant" do
      restaurant1 = restaurant_fixture()
      restaurant2 = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      order_fixture(restaurant1.id, %{customer_email: "alice@test.com"})
      order_fixture(restaurant2.id, %{customer_email: "bob@test.com"})
      order_fixture(restaurant2.id, %{customer_email: "carol@test.com"})

      result = Analytics.customer_summary(restaurant1.id, start_dt, end_dt)
      assert result.unique_customers == 1
    end
  end

  # ── top_customers/3 ───────────────────────────────────────────────────────

  describe "top_customers/3" do
    test "returns empty list for no orders" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      result = Analytics.top_customers(restaurant.id, start_dt, end_dt)
      assert result == []
    end

    test "ranks customers by total spend" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      order_fixture(restaurant.id, %{
        customer_email: "big@test.com",
        customer_name: "Big Spender",
        total_amount: 5000
      })

      order_fixture(restaurant.id, %{
        customer_email: "big@test.com",
        customer_name: "Big Spender",
        total_amount: 3000
      })

      order_fixture(restaurant.id, %{
        customer_email: "small@test.com",
        customer_name: "Small Spender",
        total_amount: 1000
      })

      result = Analytics.top_customers(restaurant.id, start_dt, end_dt)

      assert length(result) == 2
      [top | _] = result
      assert top.customer_email == "big@test.com"
      assert top.total_spend == 8000
      assert top.order_count == 2
    end
  end

  # ── delivery_metrics/3 ────────────────────────────────────────────────────

  describe "delivery_metrics/3" do
    test "returns nils for no delivered orders" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      result = Analytics.delivery_metrics(restaurant.id, start_dt, end_dt)

      assert result.avg_delivery_minutes == nil
      assert result.avg_prep_minutes == nil
      assert result.delivered_count == 0
    end

    test "calculates average delivery time" do
      restaurant = restaurant_fixture()
      {start_dt, end_dt} = date_range(30)

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      placed_at = DateTime.add(now, -60 * 30, :second)
      accepted = DateTime.add(now, -60 * 25, :second)
      delivered = DateTime.add(now, -60 * 5, :second)

      {:ok, order} =
        %Order{}
        |> Order.cart_order_changeset(%{
          customer_name: "Test",
          customer_email: "t@test.com",
          customer_phone: "+15551234567",
          delivery_address: "123 St",
          restaurant_id: restaurant.id,
          subtotal: 1000,
          tax_amount: 80,
          delivery_fee: 200,
          tip_amount: 0,
          total_amount: 1280,
          status: "delivered"
        })
        |> Repo.insert()

      order
      |> Ecto.Changeset.change(
        inserted_at: placed_at,
        accepted_at: accepted,
        delivered_at: delivered
      )
      |> Repo.update!()

      result = Analytics.delivery_metrics(restaurant.id, start_dt, end_dt)

      assert result.delivered_count == 1
      assert result.avg_delivery_minutes != nil
      assert result.avg_delivery_minutes > 0
    end
  end
end
