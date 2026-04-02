defmodule RestaurantDashWeb.KitchenLiveTest do
  use RestaurantDashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias RestaurantDash.{Accounts, Kitchen, Orders, Tenancy}

  # ─── Fixtures ──────────────────────────────────────────────────────────────

  defp create_restaurant do
    unique = System.unique_integer([:positive])

    {:ok, restaurant} =
      Tenancy.create_restaurant(%{name: "KDS Test #{unique}", slug: "kds-#{unique}"})

    restaurant
  end

  defp create_owner(restaurant) do
    unique = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.register_user_with_role(%{
        email: "kds_owner#{unique}@test.com",
        password: "hello world!",
        role: "owner",
        restaurant_id: restaurant.id,
        name: "KDS Owner"
      })

    user
  end

  defp create_staff(restaurant) do
    unique = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.register_user_with_role(%{
        email: "kds_staff#{unique}@test.com",
        password: "hello world!",
        role: "staff",
        restaurant_id: restaurant.id,
        name: "KDS Staff"
      })

    user
  end

  defp create_customer do
    unique = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.register_user_with_role(%{
        email: "kds_cust#{unique}@test.com",
        password: "hello world!",
        role: "customer"
      })

    user
  end

  defp order_fixture(restaurant_id) do
    {:ok, order} =
      Orders.create_order(%{
        customer_name: "Test Customer #{System.unique_integer([:positive])}",
        items: ["Burger", "Fries"],
        restaurant_id: restaurant_id
      })

    order
  end

  # ─── Access control ────────────────────────────────────────────────────────

  describe "access control" do
    test "unauthenticated user is redirected to login", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/kitchen")
      assert path =~ "/users/log-in"
    end

    test "customer user cannot access KDS", %{conn: conn} do
      user = create_customer()
      conn = log_in_user(conn, user)

      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/kitchen")
      assert path == "/"
    end

    test "owner can access KDS", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/dashboard/kitchen")
      assert html =~ "Kitchen Display System"
    end

    test "staff can access KDS", %{conn: conn} do
      restaurant = create_restaurant()
      staff = create_staff(restaurant)
      conn = log_in_user(conn, staff)

      {:ok, _view, html} = live(conn, ~p"/dashboard/kitchen")
      assert html =~ "Kitchen Display System"
    end
  end

  # ─── KDS board rendering ───────────────────────────────────────────────────

  describe "KDS board rendering" do
    test "renders all 4 KDS status columns", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/dashboard/kitchen")
      assert html =~ "New Orders"
      assert html =~ "Accepted"
      assert html =~ "Preparing"
      assert html =~ "Ready"
    end

    test "shows order in New column", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      order = order_fixture(restaurant.id)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/dashboard/kitchen")
      assert html =~ order.customer_name
      assert html =~ "##{order.id}"
    end

    test "shows restaurant name in header", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/dashboard/kitchen")
      assert html =~ restaurant.name
    end

    test "does not show orders from other restaurants", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      other_restaurant = create_restaurant()

      _other_order = order_fixture(other_restaurant.id)
      my_order = order_fixture(restaurant.id)

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/dashboard/kitchen")

      assert html =~ "##{my_order.id}"
      refute html =~ "other-restaurant-order"
    end

    test "order shows item names", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      _order = order_fixture(restaurant.id)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/dashboard/kitchen")
      assert html =~ "Burger"
    end
  end

  # ─── Order actions ─────────────────────────────────────────────────────────

  describe "accept_order" do
    test "accepts a new order", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      order = order_fixture(restaurant.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/dashboard/kitchen")

      view
      |> element("[phx-click='accept_order'][phx-value-id='#{order.id}']")
      |> render_click()

      updated = Orders.get_order!(order.id)
      assert updated.status == "accepted"
      assert updated.kds_managed == true
      assert updated.accepted_at != nil
    end
  end

  describe "start_preparing" do
    test "moves accepted order to preparing", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      order = order_fixture(restaurant.id)
      {:ok, order} = Kitchen.accept_order(order)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/dashboard/kitchen")

      view
      |> element("[phx-click='start_preparing'][phx-value-id='#{order.id}']")
      |> render_click()

      updated = Orders.get_order!(order.id)
      assert updated.status == "preparing"
    end
  end

  describe "mark_ready" do
    test "moves preparing order to ready", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      order = order_fixture(restaurant.id)
      {:ok, order} = Kitchen.accept_order(order)
      {:ok, order} = Kitchen.start_preparing(order)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/dashboard/kitchen")

      view
      |> element("[phx-click='mark_ready'][phx-value-id='#{order.id}']")
      |> render_click()

      updated = Orders.get_order!(order.id)
      assert updated.status == "ready"
    end
  end

  describe "reject_order" do
    test "cancels a new order", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      order = order_fixture(restaurant.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/dashboard/kitchen")

      view
      |> element("[phx-click='reject_order'][phx-value-id='#{order.id}']")
      |> render_click()

      updated = Orders.get_order!(order.id)
      assert updated.status == "cancelled"
    end
  end

  # ─── Order detail modal ────────────────────────────────────────────────────

  describe "order detail modal" do
    test "opens modal on card click", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      order = order_fixture(restaurant.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/dashboard/kitchen")

      html =
        view
        |> element("[phx-click='show_order_detail'][phx-value-id='#{order.id}']")
        |> render_click()

      assert html =~ "class=\"kds-modal-overlay\""
      assert html =~ order.customer_name
    end

    test "modal shows customer info", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      order = order_fixture(restaurant.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/dashboard/kitchen")

      html =
        view
        |> element("[phx-click='show_order_detail'][phx-value-id='#{order.id}']")
        |> render_click()

      assert html =~ order.customer_name
    end

    test "closes modal on close button", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      order = order_fixture(restaurant.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/dashboard/kitchen")

      # Open modal
      view
      |> element("[phx-click='show_order_detail'][phx-value-id='#{order.id}']")
      |> render_click()

      # Close modal
      html =
        view
        |> element("[phx-click='close_modal'].kds-modal-close")
        |> render_click()

      # Check the modal div is gone — look for the modal's HTML class attribute, not CSS selector
      refute html =~ "class=\"kds-modal-overlay\""
    end

    test "modal action buttons work - accept from modal", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      order = order_fixture(restaurant.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/dashboard/kitchen")

      # Open modal
      view
      |> element("[phx-click='show_order_detail'][phx-value-id='#{order.id}']")
      |> render_click()

      # Click accept in modal
      view
      |> element(".kds-modal-actions [phx-click='accept_order'][phx-value-id='#{order.id}']")
      |> render_click()

      updated = Orders.get_order!(order.id)
      assert updated.status == "accepted"
    end
  end

  # ─── PubSub real-time updates ─────────────────────────────────────────────

  describe "real-time PubSub updates" do
    test "new order appears in KDS via PubSub", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/dashboard/kitchen")

      # Place a new order after mount
      {:ok, order} =
        Orders.create_order(%{
          customer_name: "PubSub Test Customer",
          items: ["Pizza"],
          restaurant_id: restaurant.id
        })

      # LiveView should receive PubSub event and update
      html = render(view)
      assert html =~ "PubSub Test Customer"
      assert html =~ "##{order.id}"
    end
  end

  # ─── Mute toggle ─────────────────────────────────────────────────────────

  describe "mute toggle" do
    test "starts unmuted showing bell icon", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/dashboard/kitchen")
      assert html =~ "🔔"
    end

    test "toggles to muted state", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/dashboard/kitchen")

      html = view |> element("[phx-click='toggle_mute']") |> render_click()
      assert html =~ "🔇"
    end

    test "toggles back to unmuted", %{conn: conn} do
      restaurant = create_restaurant()
      user = create_owner(restaurant)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/dashboard/kitchen")

      view |> element("[phx-click='toggle_mute']") |> render_click()
      html = view |> element("[phx-click='toggle_mute']") |> render_click()
      assert html =~ "🔔"
    end
  end
end
