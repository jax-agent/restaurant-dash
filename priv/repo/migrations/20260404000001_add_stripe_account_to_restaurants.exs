defmodule RestaurantDash.Repo.Migrations.AddStripeAccountToRestaurants do
  use Ecto.Migration

  def change do
    alter table(:restaurants) do
      add :stripe_account_id, :string
    end
  end
end
