defmodule RestaurantDash.Repo.Migrations.AddCloverFieldsToRestaurants do
  use Ecto.Migration

  def change do
    alter table(:restaurants) do
      add :clover_merchant_id, :string
      add :clover_access_token, :string
      add :clover_connected_at, :utc_datetime
    end
  end
end
