defmodule RestaurantDash.Branding do
  @moduledoc """
  Runtime white-label branding configuration.
  """

  def restaurant_name do
    get(:restaurant_name, "El Coquí Kitchen")
  end

  def primary_color do
    get(:primary_color, "#E63946")
  end

  def logo_url do
    get(:logo_url, "/images/logo.png")
  end

  defp get(key, default) do
    Application.get_env(:restaurant_dash, :branding, [])
    |> Keyword.get(key, default)
  end
end
