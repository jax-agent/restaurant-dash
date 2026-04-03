defmodule RestaurantDashWeb.DemoControllerTest do
  use RestaurantDashWeb.ConnCase, async: false

  import Ecto.Query

  alias RestaurantDash.{Accounts, Demo, Tenancy}

  describe "GET /demo" do
    test "redirects to dashboard after setting up demo environment", %{conn: conn} do
      conn = get(conn, ~p"/demo")

      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "creates demo user and session token", %{conn: conn} do
      conn = get(conn, ~p"/demo")

      # A session token should be set
      token = get_session(conn, :user_token)
      assert token != nil

      # The token should resolve to the demo user
      {user, _} = Accounts.get_user_by_session_token(token)
      assert user.email == Demo.demo_email()
      assert user.role == "owner"
    end

    test "sets demo_mode flag in session", %{conn: conn} do
      conn = get(conn, ~p"/demo")
      assert get_session(conn, :demo_mode) == true
    end

    test "creates Sal's Pizza restaurant idempotently", %{conn: conn} do
      # First visit
      get(conn, ~p"/demo")
      # Second visit
      get(conn, ~p"/demo")

      restaurants =
        Tenancy.list_active_restaurants()
        |> Enum.filter(&(&1.slug == Demo.demo_slug()))

      assert length(restaurants) == 1
    end

    test "is idempotent — multiple visits don't duplicate demo user", %{conn: conn} do
      get(conn, ~p"/demo")
      get(conn, ~p"/demo")
      get(conn, ~p"/demo")

      demo_email = Demo.demo_email()

      users_count =
        RestaurantDash.Repo.aggregate(
          from(u in RestaurantDash.Accounts.User, where: u.email == ^demo_email),
          :count
        )

      assert users_count == 1
    end
  end
end
