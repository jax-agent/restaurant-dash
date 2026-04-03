defmodule RestaurantDashWeb.LandingLiveTest do
  use RestaurantDashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias RestaurantDash.{Accounts, Tenancy}

  describe "landing page" do
    test "renders landing page for unauthenticated visitors", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Run your own"
      assert html =~ "delivery business"
      assert html =~ "Try Demo"
    end

    test "shows login and signup links", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Sign in"
      assert html =~ "Start free"
    end

    test "shows features section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Order Management"
      assert html =~ "Live Tracking"
    end

    test "shows call-to-action", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Try Demo"
    end
  end

  describe "authenticated owner redirect" do
    test "redirects owner to dashboard", %{conn: conn} do
      unique = System.unique_integer([:positive])

      {:ok, restaurant} =
        Tenancy.create_restaurant(%{name: "Test", slug: "test-landing-#{unique}"})

      {:ok, user} =
        Accounts.register_user_with_role(%{
          email: "owner#{unique}@landing.test",
          password: "hello world!",
          role: "owner",
          restaurant_id: restaurant.id
        })

      conn = log_in_user(conn, user)

      result = live(conn, ~p"/")
      # Should redirect to /dashboard
      assert match?({:error, {:live_redirect, %{to: "/dashboard"}}}, result) or
               match?({:error, {:redirect, %{to: "/dashboard"}}}, result)
    end
  end
end