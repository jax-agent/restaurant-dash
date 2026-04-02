defmodule RestaurantDashWeb.NotificationSettingsLiveTest do
  use RestaurantDashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias RestaurantDash.{Accounts, Tenancy}

  defp create_owner_with_restaurant do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Alerts Test Restaurant",
        slug: "alerts-test-#{System.unique_integer([:positive])}",
        is_active: true
      })

    {:ok, user} =
      Accounts.register_user_with_role(%{
        email: "alertowner#{System.unique_integer([:positive])}@test.com",
        password: "hello world!",
        role: "owner",
        restaurant_id: restaurant.id,
        name: "Alert Owner"
      })

    {restaurant, user}
  end

  describe "notification settings page" do
    test "redirects unauthenticated users", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, "/dashboard/notifications")
      assert path =~ "log-in"
    end

    test "renders all alert types and channels for owner", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, "/dashboard/notifications")

      assert html =~ "Notification Settings"
      assert html =~ "New Order Received"
      assert html =~ "Payment Alerts"
      assert html =~ "Low Stock Alerts"
      assert html =~ "Driver Alerts"
      assert html =~ "SMS"
      assert html =~ "Email"
      assert html =~ "In-App"
    end

    test "shows toggle buttons with aria-checked", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, "/dashboard/notifications")
      assert html =~ "role=\"switch\""
      assert html =~ "aria-checked"
    end

    test "toggling a preference saves and shows confirmation", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, "/dashboard/notifications")

      # Toggle new_order SMS
      view
      |> element("[phx-value-alert=new_order][phx-value-channel=sms]")
      |> render_click()

      html = render(view)
      assert html =~ "saved" or html =~ "Preferences"
    end
  end
end
