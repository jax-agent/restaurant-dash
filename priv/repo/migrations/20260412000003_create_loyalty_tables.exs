defmodule RestaurantDash.Repo.Migrations.CreateLoyaltyTables do
  use Ecto.Migration

  def change do
    create table(:loyalty_accounts) do
      add :restaurant_id, references(:restaurants, on_delete: :delete_all), null: false
      add :customer_email, :string, null: false
      add :points_balance, :integer, default: 0, null: false
      add :total_points_earned, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:loyalty_accounts, [:restaurant_id, :customer_email])
    create index(:loyalty_accounts, [:restaurant_id])

    create table(:loyalty_rewards) do
      add :restaurant_id, references(:restaurants, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :points_cost, :integer, null: false
      add :discount_value, :integer, null: false
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:loyalty_rewards, [:restaurant_id])

    # Add points_rate to restaurants (points per dollar, default 1)
    alter table(:restaurants) do
      add :loyalty_points_rate, :integer, default: 1
    end
  end
end
