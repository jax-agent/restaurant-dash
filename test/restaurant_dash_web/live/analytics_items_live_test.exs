defmodule RestaurantDashWeb.AnalyticsItemsLiveTest do
  use RestaurantDashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RestaurantDash.{Accounts, Tenancy}

  defp create_owner do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Items Test #{System.unique_integer()}",
        slug: "items-test-#{System.unique_integer()}"
      })

    {:ok, user} =
      Accounts.register_user_with_role(%{
        email: "owner-items#{System.unique_integer()}@test.com",
        password: "hello world!",
        role: "owner",
        restaurant_id: restaurant.id,
        name: "Test Owner"
      })

    {restaurant, user}
  end

  describe "access control" do
    test "redirects unauthenticated user", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/analytics/items")
      assert path =~ "/users/log-in"
    end

    test "allows owner to access", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/items")
      assert html =~ "Popular Items" or html =~ "Top 10"
    end
  end

  describe "content" do
    test "shows top items section", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/items")
      assert html =~ "Top 10 Items"
    end

    test "shows revenue by category section", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/items")
      assert html =~ "Category"
    end

    test "shows least popular section", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/items")
      assert html =~ "Least Popular"
    end

    test "can switch date range", %{conn: conn} do
      {_restaurant, user} = create_owner()
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/dashboard/analytics/items")

      html =
        lv |> element("[phx-click='set_range'][phx-value-range='this_week']") |> render_click()

      assert html =~ "Top 10 Items"
    end
  end
end
