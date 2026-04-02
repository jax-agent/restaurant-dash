defmodule RestaurantDashWeb.Plugs.RequireRole do
  @moduledoc """
  Plug to enforce role-based authorization.

  Usage in router pipelines:
      plug RestaurantDashWeb.Plugs.RequireRole, :owner
      plug RestaurantDashWeb.Plugs.RequireRole, [:owner, :staff]

  Or use the helper functions:
      import RestaurantDashWeb.Plugs.RequireRole
      plug :require_owner
      plug :require_staff
  """

  import Plug.Conn
  import Phoenix.Controller

  @doc "Require the current user to have the given role(s)."
  def init(roles) when is_atom(roles), do: [roles]
  def init(roles) when is_list(roles), do: roles

  def call(conn, allowed_roles) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        conn
        |> put_flash(:error, "You must be logged in to access this page.")
        |> redirect(to: "/users/log_in")
        |> halt()

      user.role in Enum.map(allowed_roles, &to_string/1) ->
        conn

      true ->
        conn
        |> put_flash(:error, "You don't have permission to access this page.")
        |> redirect(to: "/")
        |> halt()
    end
  end

  # ─── Convenience plugs ────────────────────────────────────────────────────

  @doc "Plug: require owner role."
  def require_owner(conn, _opts), do: call(conn, [:owner])

  @doc "Plug: require owner or staff role."
  def require_staff(conn, _opts), do: call(conn, [:owner, :staff])

  @doc "Plug: require driver role."
  def require_driver(conn, _opts), do: call(conn, [:driver])

  @doc "Plug: require any authenticated user."
  def require_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in to access this page.")
      |> redirect(to: "/users/log_in")
      |> halt()
    end
  end
end
