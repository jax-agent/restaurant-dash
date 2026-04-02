defmodule RestaurantDashWeb.Plugs.RequireRoleTest do
  use RestaurantDashWeb.ConnCase, async: true

  alias RestaurantDashWeb.Plugs.RequireRole
  alias RestaurantDash.Accounts
  alias RestaurantDash.Tenancy

  @restaurant_attrs %{name: "Test Restaurant", slug: "test-role-plug"}

  defp create_user(role, restaurant_id \\ nil) do
    unique = System.unique_integer([:positive])

    attrs = %{
      email: "user#{unique}@example.com",
      password: "hello world!",
      role: role,
      restaurant_id: restaurant_id
    }

    {:ok, user} = Accounts.register_user_with_role(attrs)
    user
  end

  describe "require_role plug" do
    test "allows user with matching role", %{conn: conn} do
      user = create_user("owner")
      conn = conn |> assign(:current_user, user) |> RequireRole.call([:owner])
      refute conn.halted
    end

    test "allows when role is in list", %{conn: conn} do
      user = create_user("staff")
      conn = conn |> assign(:current_user, user) |> RequireRole.call([:owner, :staff])
      refute conn.halted
    end

    test "denies user with wrong role", %{conn: conn} do
      user = create_user("customer")

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> fetch_flash()
        |> assign(:current_user, user)
        |> RequireRole.call([:owner])

      assert conn.halted
      assert conn.status == 302
    end

    test "redirects unauthenticated user to login", %{conn: conn} do
      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> fetch_flash()
        |> assign(:current_user, nil)
        |> RequireRole.call([:owner])

      assert conn.halted
      assert conn.status == 302
    end

    test "require_owner/2 convenience plug", %{conn: conn} do
      {:ok, restaurant} = Tenancy.create_restaurant(@restaurant_attrs)
      user = create_user("owner", restaurant.id)
      conn = conn |> assign(:current_user, user) |> RequireRole.require_owner([])
      refute conn.halted
    end

    test "require_staff/2 allows owner too", %{conn: conn} do
      {:ok, restaurant} =
        Tenancy.create_restaurant(%{@restaurant_attrs | slug: "test-role-plug-2"})

      user = create_user("owner", restaurant.id)
      conn = conn |> assign(:current_user, user) |> RequireRole.require_staff([])
      refute conn.halted
    end
  end
end
