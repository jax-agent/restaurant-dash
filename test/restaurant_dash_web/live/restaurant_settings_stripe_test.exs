defmodule RestaurantDashWeb.RestaurantSettingsStripeTest do
  use RestaurantDashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias RestaurantDash.{Tenancy, Repo, Payments}

  setup do
    # Create a restaurant + owner user
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Stripe Test Pizza",
        slug: "stripe-test-pizza"
      })

    {:ok, user} =
      RestaurantDash.Accounts.register_user(%{
        email: "owner_stripe@example.com",
        password: "password12345678"
      })

    # Set role and restaurant
    user =
      user
      |> Ecto.Changeset.change(%{role: "owner", restaurant_id: restaurant.id})
      |> Repo.update!()

    %{restaurant: restaurant, user: user}
  end

  describe "Stripe Connect section" do
    test "shows 'Connect Stripe Account' button when not connected", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/settings")

      assert html =~ "Connect Stripe Account"
      assert html =~ "Payment Processing"
    end

    test "shows demo mode badge when mock mode active", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/settings")

      # In test env, mock mode is active
      assert Payments.mock_mode?()
      assert html =~ "Demo Mode"
    end

    test "connect-stripe event triggers onboarding redirect", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/dashboard/settings")

      # Click connect - in mock mode should redirect externally (to mock URL)
      assert {:error, {:redirect, %{to: url}}} =
               lv |> element("button", "Connect Stripe Account") |> render_click()

      # Mock mode redirect goes to the return URL with mock params
      assert String.contains?(url, "stripe_mock=true") or
               String.contains?(url, "stripe_connected=true") or
               String.starts_with?(url, "http")
    end

    test "shows connected state when stripe_account_id present", %{
      conn: conn,
      user: user,
      restaurant: restaurant
    } do
      {:ok, _} = Payments.save_stripe_account_id(restaurant, "acct_mock_test123")

      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/settings")

      assert html =~ "Stripe Connected"
      assert html =~ "acct_mock_test123"
    end
  end
end
