defmodule RestaurantDashWeb.RestaurantSettingsLiveTest do
  use RestaurantDashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias RestaurantDash.{Accounts, Tenancy}

  @restaurant_attrs %{
    name: "Settings Test Pizza",
    slug: "settings-test-pizza",
    description: "Original description",
    phone: "(415) 555-0100",
    city: "San Francisco",
    state: "CA"
  }

  defp create_owner_with_restaurant(restaurant_attrs \\ @restaurant_attrs) do
    {:ok, restaurant} = Tenancy.create_restaurant(restaurant_attrs)
    unique = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.register_user_with_role(%{
        email: "owner#{unique}@settings.test",
        password: "hello world!",
        role: "owner",
        restaurant_id: restaurant.id
      })

    {restaurant, user}
  end

  describe "access control" do
    test "redirects unauthenticated user to login", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/settings")
      assert path =~ "/users/log-in"
    end

    test "redirects non-owner staff to home", %{conn: conn} do
      {_restaurant, owner} =
        create_owner_with_restaurant(%{name: "Staff Test", slug: "staff-test-settings"})

      # Create a staff user without restaurant
      {:ok, customer} =
        Accounts.register_user_with_role(%{
          email: "customer#{System.unique_integer([:positive])}@settings.test",
          password: "hello world!",
          role: "customer"
        })

      conn = log_in_user(conn, customer)
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/settings")
      assert path in ["/", "/users/log-in"]

      # Suppress unused warning
      _ = owner
    end

    test "allows owner to access settings", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard/settings")
      assert html =~ "Restaurant Settings"
    end
  end

  describe "settings form" do
    test "renders the settings form with current values", %{conn: conn} do
      {restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard/settings")

      assert html =~ restaurant.name
      assert html =~ "Restaurant Details"
    end

    test "updates restaurant settings successfully", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/settings")

      html =
        lv
        |> form("#settings-form",
          restaurant: %{
            name: "Updated Pizza Name",
            description: "New description",
            phone: "(415) 555-9999"
          }
        )
        |> render_submit()

      assert html =~ "Settings saved" or html =~ "Updated Pizza Name"

      # Verify the restaurant was actually updated
      updated_user = Accounts.get_user_by_email(user.email)
      restaurant = Tenancy.get_restaurant(updated_user.restaurant_id)
      assert restaurant.name == "Updated Pizza Name"
    end

    test "shows validation errors for invalid data", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/settings")

      html =
        lv
        |> form("#settings-form", restaurant: %{name: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end

    test "live preview updates as user types", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/settings")

      html =
        lv
        |> form("#settings-form",
          restaurant: %{name: "Live Preview Test", primary_color: "#123456"}
        )
        |> render_change()

      assert html =~ "Live Preview Test"
    end

    test "shows restaurant branding preview", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard/settings")
      assert html =~ "Live Preview"
    end
  end
end
