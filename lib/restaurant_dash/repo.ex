defmodule RestaurantDash.Repo do
  use Ecto.Repo,
    otp_app: :restaurant_dash,
    adapter: Ecto.Adapters.Postgres
end
