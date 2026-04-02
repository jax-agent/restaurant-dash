defmodule RestaurantDashWeb.SquareOAuthController do
  @moduledoc """
  Handles Square OAuth callback.
  After the merchant authorizes our app on Square, they're redirected here
  with a code. We exchange the code for access + refresh tokens and
  save the credentials to the restaurant.
  """

  use RestaurantDashWeb, :controller

  alias RestaurantDash.Integrations.Square
  alias RestaurantDash.Tenancy

  require Logger

  @doc """
  GET /dashboard/settings/square/callback
  Square sends: ?code=XXX (and optionally ?state=YYY)
  On error: ?error=access_denied (or similar)
  """
  def callback(conn, params) do
    current_user = conn.assigns[:current_user]

    if is_nil(current_user) or current_user.role not in ["owner", "admin"] do
      conn
      |> put_flash(:error, "You must be logged in as an owner to connect Square.")
      |> redirect(to: ~p"/users/log-in")
    else
      restaurant = Tenancy.get_restaurant!(current_user.restaurant_id)

      case do_connect(restaurant, params) do
        {:ok, _restaurant} ->
          conn
          |> put_flash(:info, "Square connected successfully!")
          |> redirect(to: ~p"/dashboard/settings?square_connected=true")

        {:error, reason} ->
          Logger.error("[SquareOAuth] Connection failed: #{inspect(reason)}")

          conn
          |> put_flash(:error, "Failed to connect Square: #{format_error(reason)}")
          |> redirect(to: ~p"/dashboard/settings")
      end
    end
  end

  defp do_connect(_restaurant, %{"error" => error}) do
    {:error, "Square authorization denied: #{error}"}
  end

  defp do_connect(restaurant, %{"code" => code}) do
    Square.connect(restaurant, code)
  end

  defp do_connect(_restaurant, params) do
    {:error, "Missing OAuth code. Got params: #{inspect(Map.keys(params))}"}
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
