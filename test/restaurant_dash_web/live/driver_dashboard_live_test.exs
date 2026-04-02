defmodule RestaurantDashWeb.DriverDashboardLiveTest do
  use RestaurantDashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias RestaurantDash.{Drivers, Orders, Tenancy}

  defp unique_email, do: "user#{System.unique_integer()}@example.com"
  defp unique_slug, do: "rest-#{System.unique_integer()}"

  defp create_restaurant do
    {:ok, r} = Tenancy.create_restaurant(%{name: "TestRest", slug: unique_slug()})
    r
  end

  defp create_driver_user do
    {:ok, %{user: user, profile: profile}} =
      Drivers.register_driver(%{
        "email" => unique_email(),
        "password" => "securepass1234",
        "name" => "Test Driver",
        "vehicle_type" => "car",
        "phone" => "555-0199"
      })

    {user, profile}
  end

  describe "Driver Dashboard" do
    test "redirects unauthenticated users", %{conn: conn} do
      result = live(conn, ~p"/driver/dashboard")
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = result
    end

    test "non-driver user gets unauthorized redirect", %{conn: conn} do
      # Create a regular customer and try to access driver dashboard
      {:ok, customer} =
        RestaurantDash.Accounts.register_user_with_role(%{
          "email" => unique_email(),
          "password" => "securepass1234",
          "name" => "Customer",
          "role" => "customer"
        })

      conn = log_in_user(conn, customer)

      result = live(conn, ~p"/driver/dashboard")
      assert {:error, {:redirect, %{to: "/"}}} = result
    end

    test "approved driver sees dashboard", %{conn: conn} do
      {user, profile} = create_driver_user()
      {:ok, _approved} = Drivers.approve_driver(profile)

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/driver/dashboard")
      assert html =~ "Driver Dashboard"
      assert html =~ "Available" or html =~ "Offline"
    end

    test "unapproved driver sees pending notice", %{conn: conn} do
      {user, _profile} = create_driver_user()

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/driver/dashboard")
      assert html =~ "Pending Approval" or html =~ "pending"
    end

    test "approved driver can toggle availability", %{conn: conn} do
      {user, profile} = create_driver_user()
      {:ok, _approved} = Drivers.approve_driver(profile)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      html = render_click(view, "toggle_availability")
      assert html =~ "Available" or html =~ "Status"
    end

    test "shows waiting message when available and no delivery", %{conn: conn} do
      {user, profile} = create_driver_user()
      {:ok, approved} = Drivers.approve_driver(profile)
      {:ok, _available} = Drivers.set_status(approved, "available")

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/driver/dashboard")
      assert html =~ "Waiting" or html =~ "waiting"
    end

    test "shows active delivery when driver is on_delivery", %{conn: conn} do
      restaurant = create_restaurant()
      {user, profile} = create_driver_user()
      {:ok, approved} = Drivers.approve_driver(profile)
      {:ok, _} = Drivers.set_status(approved, "available")

      # Create an order and assign driver
      {:ok, order} =
        Orders.create_order(%{
          customer_name: "Customer One",
          delivery_address: "123 Main St",
          restaurant_id: restaurant.id,
          items: ["Burger"],
          status: "ready"
        })

      {:ok, _assigned} = Orders.assign_driver(order, user.id)

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/driver/dashboard")
      assert html =~ "Customer One" or html =~ "Current Delivery"
    end

    test "driver can mark order as picked up", %{conn: conn} do
      restaurant = create_restaurant()
      {user, profile} = create_driver_user()
      {:ok, approved} = Drivers.approve_driver(profile)
      {:ok, _} = Drivers.set_status(approved, "available")

      {:ok, order} =
        Orders.create_order(%{
          customer_name: "Pickup Customer",
          delivery_address: "456 Oak Ave",
          restaurant_id: restaurant.id,
          items: ["Pizza"],
          status: "ready"
        })

      {:ok, _assigned} = Orders.assign_driver(order, user.id)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      html = render_click(view, "mark_picked_up")
      assert html =~ "picked" or html =~ "Picked" or html =~ "Deliver"
    end

    test "shows earnings stats", %{conn: conn} do
      {user, profile} = create_driver_user()
      {:ok, approved} = Drivers.approve_driver(profile)
      {:ok, _} = Drivers.set_status(approved, "available")

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/driver/dashboard")
      assert html =~ "Deliveries today" or html =~ "Tips"
    end
  end
end
