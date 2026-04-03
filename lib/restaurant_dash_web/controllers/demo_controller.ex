defmodule RestaurantDashWeb.DemoController do
  @moduledoc """
  Handles the /demo route. Sets up demo environment and logs the visitor in as
  the demo owner, then redirects to the dashboard.
  """
  use RestaurantDashWeb, :controller

  alias RestaurantDash.{Accounts, Demo}

  @doc """
  GET /demo

  Idempotently seeds Sal's Pizza demo data, creates/finds demo@orderbase.com,
  creates a session token, and redirects to /dashboard.
  """
  def index(conn, _params) do
    # 1. Ensure demo data exists and get the demo user
    demo_user = Demo.setup!()

    # 2. Generate a session token for the demo user
    token = Accounts.generate_user_session_token(demo_user)

    # 3. Write session (reuse the same mechanism as normal login)
    conn
    |> renew_session_safe()
    |> put_session(:user_token, token)
    |> put_session(:demo_mode, true)
    |> put_flash(:info, "🎯 Welcome to OrderBase demo! Explore freely — this is a sandbox.")
    |> redirect(to: ~p"/dashboard")
  end

  # Safely renew the session without clearing demo_mode
  defp renew_session_safe(conn) do
    Phoenix.Controller.delete_csrf_token()

    conn
    |> Plug.Conn.configure_session(renew: true)
    |> Plug.Conn.clear_session()
  end
end
