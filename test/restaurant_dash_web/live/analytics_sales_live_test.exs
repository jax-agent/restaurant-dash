defmodule RestaurantDashWeb.AnalyticsSalesLiveTest do
  use RestaurantDashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias RestaurantDash.{Accounts, Orders, Tenancy}

  defp create_owner_with_restaurant do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Sales Test Pizza #{System.unique_integer()}",
        slug: "sales-test-#{System.unique_integer()}"
      })

    {:ok, user} =
      Accounts.register_user_with_role(%{
        email: "owner-sales#{System.unique_integer()}@test.com",
        password: "hello world!",
        role: "owner",
        restaurant_id: restaurant.id,
        name: "Test Owner"
      })

    {restaurant, user}
  end

  describe "access control" do
    test "redirects unauthenticated user", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/analytics/sales")
      assert path =~ "/users/log-in"
    end

    test "redirects non-owner users", %{conn: conn} do
      {:ok, customer} =
        Accounts.register_user_with_role(%{
          email: "cust#{System.unique_integer()}@test.com",
          password: "hello world!",
          role: "customer"
        })

      conn = log_in_user(conn, customer)
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/analytics/sales")
      assert path in ["/", "/users/log-in"]
    end

    test "allows owner to access sales report", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/sales")
      assert html =~ "Sales"
    end
  end

  describe "date range filtering" do
    test "shows today preset by default", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/sales")
      assert html =~ "today" or html =~ "Today"
    end

    test "can switch to this week", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/analytics/sales")

      html = lv |> element("[phx-click='set_range'][phx-value-range='this_week']") |> render_click()
      assert html =~ "Revenue" or html =~ "Orders"
    end

    test "can switch to this month", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/analytics/sales")

      html =
        lv |> element("[phx-click='set_range'][phx-value-range='this_month']") |> render_click()

      assert html =~ "Revenue" or html =~ "Orders"
    end

    test "can switch to last 30 days", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/analytics/sales")

      html =
        lv |> element("[phx-click='set_range'][phx-value-range='last_30_days']") |> render_click()

      assert html =~ "Revenue" or html =~ "Orders"
    end
  end

  describe "metrics display" do
    test "shows total revenue", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/sales")
      assert html =~ "Revenue"
    end

    test "shows order count", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/sales")
      assert html =~ "Order"
    end

    test "shows tips collected", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/sales")
      assert html =~ "Tips"
    end
  end

  describe "CSV export" do
    test "export link is present on page", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard/analytics/sales")
      assert html =~ "Export" or html =~ "CSV"
    end

    test "CSV download endpoint returns CSV content", %{conn: conn} do
      {restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      # Create some orders
      Orders.create_order(%{
        customer_name: "CSV Test Customer",
        items: ["Burger"],
        restaurant_id: restaurant.id
      })

      conn = get(conn, ~p"/dashboard/analytics/sales/export")
      assert response_content_type(conn, :csv) =~ "text/csv" or
               get_resp_header(conn, "content-type") |> List.first() =~ "text/csv" or
               get_resp_header(conn, "content-disposition") |> List.first() =~ "attachment"
    end
  end
end
