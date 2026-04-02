defmodule RestaurantDashWeb.DriversDashboardLiveTest do
  use RestaurantDashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias RestaurantDash.{Drivers, Tenancy, Accounts}

  defp unique_email, do: "user#{System.unique_integer()}@example.com"
  defp unique_slug, do: "restaurant-#{System.unique_integer()}"

  defp create_restaurant do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{name: "Test Restaurant", slug: unique_slug()})

    restaurant
  end

  defp create_owner(restaurant) do
    {:ok, user} =
      Accounts.register_user_with_role(%{
        "email" => unique_email(),
        "password" => "securepass1234",
        "name" => "Owner",
        "role" => "owner",
        "restaurant_id" => restaurant.id
      })

    user
  end

  defp create_driver do
    {:ok, %{profile: profile}} =
      Drivers.register_driver(%{
        "email" => unique_email(),
        "password" => "securepass1234",
        "name" => "Test Driver",
        "vehicle_type" => "car"
      })

    profile
  end

  defp log_in_owner(conn, restaurant) do
    owner = create_owner(restaurant)
    log_in_user(conn, owner)
  end

  describe "Drivers Dashboard" do
    test "redirects unauthenticated users", %{conn: conn} do
      result = live(conn, ~p"/dashboard/drivers")
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = result
    end

    test "renders driver list for owner", %{conn: conn} do
      restaurant = create_restaurant()
      conn = log_in_owner(conn, restaurant)

      _driver_profile = create_driver()

      {:ok, _view, html} = live(conn, ~p"/dashboard/drivers")
      assert html =~ "Driver Management"
    end

    test "shows approve button for pending drivers", %{conn: conn} do
      restaurant = create_restaurant()
      conn = log_in_owner(conn, restaurant)
      _profile = create_driver()

      {:ok, _view, html} = live(conn, ~p"/dashboard/drivers")
      assert html =~ "Approve" or html =~ "Pending"
    end

    test "owner can approve a driver", %{conn: conn} do
      restaurant = create_restaurant()
      conn = log_in_owner(conn, restaurant)
      profile = create_driver()

      {:ok, view, _html} = live(conn, ~p"/dashboard/drivers")

      updated_html =
        view
        |> element("[phx-click='approve'][phx-value-id='#{profile.id}']")
        |> render_click()

      assert updated_html =~ "approved" or updated_html =~ "Approved"
    end

    test "owner can suspend an approved driver", %{conn: conn} do
      restaurant = create_restaurant()
      conn = log_in_owner(conn, restaurant)
      profile = create_driver()
      {:ok, _approved} = Drivers.approve_driver(profile)

      {:ok, view, _html} = live(conn, ~p"/dashboard/drivers")

      html =
        view
        |> element("[phx-click='suspend'][phx-value-id='#{profile.id}']")
        |> render_click()

      assert html =~ "suspended" or html =~ "Pending"
    end
  end
end
