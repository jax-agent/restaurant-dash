defmodule RestaurantDashWeb.DashboardLiveTest do
  use RestaurantDashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias RestaurantDash.{Accounts, Orders, Tenancy}

  # Set up a restaurant + owner for the kanban tests
  defp create_owner_setup do
    unique = System.unique_integer([:positive])

    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Sal's Pizza",
        slug: "sals-pizza-kanban-#{unique}",
        primary_color: "#E63946"
      })

    {:ok, user} =
      Accounts.register_user_with_role(%{
        email: "owner#{unique}@sals.test",
        password: "hello world!",
        role: "owner",
        restaurant_id: restaurant.id
      })

    {restaurant, user}
  end

  describe "dashboard mount" do
    test "renders the dashboard with restaurant name", %{conn: conn} do
      {_restaurant, user} = create_owner_setup()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard/orders")
      assert html =~ "Sal&#39;s Pizza" or html =~ "Sal's Pizza"
    end

    test "renders kanban columns", %{conn: conn} do
      {_restaurant, user} = create_owner_setup()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/orders")

      assert html =~ "New"
      assert html =~ "Preparing"
      assert html =~ "Out for Delivery"
      assert html =~ "Delivered"
    end

    test "renders the New Order button", %{conn: conn} do
      {_restaurant, user} = create_owner_setup()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/orders")
      assert html =~ "New Order"
    end

    test "renders the delivery map container", %{conn: conn} do
      {_restaurant, user} = create_owner_setup()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/orders")
      assert html =~ "delivery-map"
    end
  end

  describe "orders displayed" do
    test "shows an order in the correct column", %{conn: conn} do
      {restaurant, user} = create_owner_setup()
      conn = log_in_user(conn, user)

      {:ok, _order} =
        Orders.create_order(%{
          customer_name: "TestCustomer",
          items: ["Burger"],
          status: "new",
          restaurant_id: restaurant.id
        })

      {:ok, _lv, html} = live(conn, ~p"/dashboard/orders")
      assert html =~ "TestCustomer"
    end

    test "shows item count on order card", %{conn: conn} do
      {restaurant, user} = create_owner_setup()
      conn = log_in_user(conn, user)

      {:ok, _order} =
        Orders.create_order(%{
          customer_name: "ItemTestCustomer",
          items: ["Pizza", "Soda", "Garlic Bread"],
          status: "new",
          restaurant_id: restaurant.id
        })

      {:ok, _lv, html} = live(conn, ~p"/dashboard/orders")
      assert html =~ "ItemTestCustomer"
      assert html =~ "3 items"
    end
  end

  describe "new order link" do
    test "has a New Order link on the dashboard", %{conn: conn} do
      {_restaurant, user} = create_owner_setup()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/orders")
      assert html =~ "New Order"
      assert html =~ "/orders/new"
    end

    test "creates an order via form submission at /orders/new", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/orders/new")

      # Fill and submit the form — on success it redirects to "/"
      result =
        lv
        |> form("form",
          order: %{
            customer_name: "FormTest User",
            phone: "(415) 555-9999",
            delivery_address: "999 Test St, San Francisco, CA",
            items_text: "Test Pizza\nTest Soda"
          }
        )
        |> render_submit()

      # On success, result is a redirect tuple or HTML
      assert match?({:error, {:live_redirect, %{to: "/"}}}, result) or
               (is_binary(result) and (result =~ "FormTest User" or result =~ "Order created"))
    end

    test "shows validation errors for missing required fields at /orders/new", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/orders/new")

      html =
        lv
        |> form("form", order: %{customer_name: "", items_text: ""})
        |> render_change()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end
  end

  describe "white-label config" do
    test "shows restaurant name from branding config", %{conn: conn} do
      {_restaurant, user} = create_owner_setup()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard/orders")
      assert html =~ "Sal" and html =~ "Pizza"
    end
  end

  describe "sidebar counts" do
    test "renders status counts in sidebar", %{conn: conn} do
      {restaurant, user} = create_owner_setup()
      conn = log_in_user(conn, user)

      Orders.create_order(%{
        customer_name: "A1",
        items: ["x"],
        status: "new",
        restaurant_id: restaurant.id
      })

      Orders.create_order(%{
        customer_name: "A2",
        items: ["x"],
        status: "new",
        restaurant_id: restaurant.id
      })

      {:ok, _lv, html} = live(conn, ~p"/dashboard/orders")
      # The sidebar should show some counts
      assert html =~ "sidebar-count"
    end
  end
end
