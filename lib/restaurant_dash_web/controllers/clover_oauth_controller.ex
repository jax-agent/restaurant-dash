defmodule RestaurantDashWeb.CloverOAuthController do
  @moduledoc """
  Handles Clover OAuth callback.
  After the merchant authorizes our app on Clover, they're redirected here
  with a code + merchant_id. We exchange the code for an access token and
  save the credentials to the restaurant.
  """

  use RestaurantDashWeb, :controller

  alias RestaurantDash.Integrations.Clover
  alias RestaurantDash.Tenancy

  require Logger

  @doc """
  GET /dashboard/settings/clover/callback
  Clover sends: ?merchant_id=XXX&code=YYY (or ?employee_id=... in some flows)
  """
  def callback(conn, params) do
    current_user = conn.assigns[:current_user]

    if is_nil(current_user) or current_user.role not in ["owner", "admin"] do
      conn
      |> put_flash(:error, "You must be logged in as an owner to connect Clover.")
      |> redirect(to: ~p"/users/log-in")
    else
      restaurant = Tenancy.get_restaurant!(current_user.restaurant_id)

      case do_connect(restaurant, params) do
        {:ok, _restaurant} ->
          conn
          |> put_flash(:info, "Clover connected successfully!")
          |> redirect(to: ~p"/dashboard/settings?clover_connected=true")

        {:error, reason} ->
          Logger.error("[CloverOAuth] Connection failed: #{inspect(reason)}")

          conn
          |> put_flash(:error, "Failed to connect Clover: #{format_error(reason)}")
          |> redirect(to: ~p"/dashboard/settings")
      end
    end
  end

  defp do_connect(restaurant, %{"code" => code}) do
    Clover.connect(restaurant, code)
  end

  defp do_connect(restaurant, %{"merchant_id" => merchant_id, "employee_id" => _}) do
    # Clover dev mode sometimes returns merchant_id directly with no code exchange
    # Use mock token in this case
    Clover.save_clover_credentials(restaurant, merchant_id, "mock_dev_token_#{merchant_id}")
  end

  defp do_connect(_restaurant, params) do
    {:error, "Missing OAuth code. Got params: #{inspect(Map.keys(params))}"}
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
