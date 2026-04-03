defmodule RestaurantDashWeb.Plugs.ResolveRestaurant do
  @moduledoc """
  Plug that extracts the restaurant from the request subdomain.

  When a request comes in for `el-coqui-kitchen.restaurantdash.com`, this plug
  extracts `el-coqui-kitchen`, looks up the restaurant by slug, and assigns it
  as `current_restaurant` on the conn.

  In development/test, it checks for a `restaurant_slug` query param as
  a fallback (e.g., `/?restaurant_slug=el-coqui-kitchen`).
  """

  import Plug.Conn
  alias RestaurantDash.Tenancy

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    case extract_slug(conn) do
      nil ->
        assign(conn, :current_restaurant, nil)

      slug ->
        restaurant = Tenancy.get_restaurant_by_slug(slug)
        assign(conn, :current_restaurant, restaurant)
    end
  end

  # Extract slug from subdomain (e.g., "el-coqui-kitchen" from "el-coqui-kitchen.restaurantdash.com")
  # Falls back to ?restaurant_slug= query param in dev/test
  defp extract_slug(conn) do
    host = conn.host

    cond do
      # Check for known multi-part base domains
      subdomain_slug = extract_from_host(host) ->
        subdomain_slug

      # Dev/test fallback: ?restaurant_slug=el-coqui-kitchen
      slug = conn.query_params["restaurant_slug"] ->
        slug

      true ->
        nil
    end
  end

  defp extract_from_host(host) do
    # Split host into parts: "el-coqui-kitchen.restaurantdash.com" → ["el-coqui-kitchen", "restaurantdash", "com"]
    parts = String.split(host, ".")

    # Only treat as subdomain if there are at least 3 parts (subdomain.domain.tld)
    if length(parts) >= 3 do
      hd(parts)
    else
      nil
    end
  end
end
