defmodule RestaurantDashWeb.AnalyticsDeliveryLiveTest do
  use RestaurantDashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RestaurantDash.{Accounts, Tenancy}

  defp create_owner do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Delivery Test #{System.unique_integer()}",
        slug: "delivery-test-#{System.unique_integer()}"
      })

    {:ok, user} =
      Accounts.register_user_with_role(%{
        email: "owner-deliv#{System.unique_integer()}@test.com",
        password: "hello world!",
        role: "owner",
        restaurant_id: restaurant.id,
        name: "Test Owner"
      })

    {restaurant, user}
  end

  describe "access control" do
    test "redirects unauthenticated user", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/analytics/delivery")
      assert path =~ "/users/log-in"
    end

    test "allows owner to access", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/delivery")
      assert html =~ "Delivery Metrics"
    end
  end

  describe "content" do
    test "shows avg delivery time", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/delivery")
      assert html =~ "Avg Delivery Time"
    end

    test "shows cancellation rate", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/delivery")
      assert html =~ "Cancellation Rate"
    end

    test "shows driver performance table", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/delivery")
      assert html =~ "Driver Performance"
    end

    test "shows peak delivery hours", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/delivery")
      assert html =~ "Peak Delivery Hours"
    end

    test "can switch date range", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/dashboard/analytics/delivery")

      html =
        lv |> element("[phx-click='set_range'][phx-value-range='this_month']") |> render_click()

      assert html =~ "Avg Delivery Time"
    end
  end
end
