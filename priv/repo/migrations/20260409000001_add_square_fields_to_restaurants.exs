defmodule RestaurantDash.Repo.Migrations.AddSquareFieldsToRestaurants do
  use Ecto.Migration

  def change do
    alter table(:restaurants) do
      add :square_merchant_id, :string
      add :square_access_token, :string
      add :square_refresh_token, :string
      add :square_location_id, :string
      add :square_connected_at, :utc_datetime
    end
  end
end
