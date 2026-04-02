defmodule RestaurantDashWeb.OwnerDashboardLiveTest do
  use RestaurantDashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias RestaurantDash.{Accounts, Orders, Tenancy}

  @restaurant_attrs %{
    name: "Dashboard Test Pizza",
    slug: "dashboard-test-pizza"
  }

  defp create_owner_with_restaurant(restaurant_attrs \\ @restaurant_attrs) do
    {:ok, restaurant} = Tenancy.create_restaurant(restaurant_attrs)
    unique = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.register_user_with_role(%{
        email: "owner#{unique}@test.com",
        password: "hello world!",
        role: "owner",
        restaurant_id: restaurant.id,
        name: "Test Owner"
      })

    {restaurant, user}
  end

  describe "access control" do
    test "redirects unauthenticated user to login", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard")
      assert path =~ "/users/log-in"
    end

    test "redirects customer (no restaurant) to root", %{conn: conn} do
      {:ok, customer} =
        Accounts.register_user_with_role(%{
          email: "customer#{System.unique_integer([:positive])}@test.com",
          password: "hello world!",
          role: "customer"
        })

      conn = log_in_user(conn, customer)
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard")
      assert path in ["/", "/users/log-in"]
    end

    test "allows owner with restaurant to access dashboard", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ "Owner Dashboard"
    end
  end

  describe "dashboard data" do
    test "shows the restaurant name", %{conn: conn} do
      {restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      assert html =~ restaurant.name
    end

    test "shows today's order count", %{conn: conn} do
      {restaurant, user} = create_owner_with_restaurant()

      Orders.create_order(%{
        customer_name: "Alice",
        items: ["Pizza"],
        restaurant_id: restaurant.id
      })

      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "Today" and html =~ "Orders"
    end

    test "shows total order count", %{conn: conn} do
      {restaurant, user} = create_owner_with_restaurant()

      Orders.create_order(%{
        customer_name: "Bob",
        items: ["Sushi"],
        restaurant_id: restaurant.id
      })

      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "Total Orders"
    end

    test "only shows orders from owner's restaurant", %{conn: conn} do
      {restaurant, user} =
        create_owner_with_restaurant(%{name: "Pizza R1", slug: "pizza-r1-dash-test"})

      {:ok, r2} = Tenancy.create_restaurant(%{name: "Sushi R2", slug: "sushi-r2-dash-test"})

      Orders.create_order(%{
        customer_name: "My Customer",
        items: ["Pizza"],
        restaurant_id: restaurant.id
      })

      Orders.create_order(%{
        customer_name: "Other Restaurant Customer",
        items: ["Sushi"],
        restaurant_id: r2.id
      })

      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "My Customer"
      refute html =~ "Other Restaurant Customer"
    end

    test "shows navigation links", %{conn: conn} do
      {_restaurant, user} =
        create_owner_with_restaurant(%{name: "Nav Test", slug: "nav-test-dash"})

      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "Orders"
      assert html =~ "Settings"
    end
  end

  describe "analytics cards" do
    test "shows today's revenue card", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "Today&#39;s Revenue" or html =~ "Today's Revenue"
    end

    test "shows analytics navigation links", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "analytics" or html =~ "Analytics"
    end

    test "shows active orders count", %{conn: conn} do
      {restaurant, user} = create_owner_with_restaurant()

      Orders.create_order(%{
        customer_name: "Alice Active",
        items: ["Pizza"],
        restaurant_id: restaurant.id
      })

      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "Active"
    end
  end
end
