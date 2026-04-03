defmodule RestaurantDashWeb.LandingLiveTest do
  use RestaurantDashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias RestaurantDash.{Accounts, Tenancy}

  describe "landing page" do
    test "renders landing page for unauthenticated visitors", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Deliver Puerto Rico"
      assert html =~ "Best Food"
      assert html =~ "Try the Demo"
      assert html =~ "/signup"
    end

    test "shows login and signup links", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Log in"
      assert html =~ "signup"
    end

    test "shows features section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Order Management"
      assert html =~ "Live Delivery Tracking"
    end

    test "shows call-to-action", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Create Your Restaurant"
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
