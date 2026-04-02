defmodule RestaurantDashWeb.AnalyticsCustomersLiveTest do
  use RestaurantDashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RestaurantDash.{Accounts, Tenancy}

  defp create_owner do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Customer Analytics #{System.unique_integer()}",
        slug: "cust-analytics-#{System.unique_integer()}"
      })

    {:ok, user} =
      Accounts.register_user_with_role(%{
        email: "owner-cust#{System.unique_integer()}@test.com",
        password: "hello world!",
        role: "owner",
        restaurant_id: restaurant.id,
        name: "Test Owner"
      })

    {restaurant, user}
  end

  describe "access control" do
    test "redirects unauthenticated user", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/analytics/customers")
      assert path =~ "/users/log-in"
    end

    test "allows owner to access", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/customers")
      assert html =~ "Customer Insights"
    end
  end

  describe "content" do
    test "shows unique customers metric", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/customers")
      assert html =~ "Unique Customers"
    end

    test "shows repeat rate", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/customers")
      assert html =~ "Repeat Rate"
    end

    test "shows top customers table", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/customers")
      assert html =~ "Top Customers"
    end

    test "shows avg lifetime value", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/customers")
      assert html =~ "Lifetime Value"
    end

    test "can switch date range", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/dashboard/analytics/customers")

      html =
        lv |> element("[phx-click='set_range'][phx-value-range='this_month']") |> render_click()

      assert html =~ "Unique Customers"
    end
  end
end
