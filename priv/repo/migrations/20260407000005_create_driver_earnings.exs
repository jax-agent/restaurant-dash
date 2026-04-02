defmodule RestaurantDash.Repo.Migrations.CreateDriverEarnings do
  use Ecto.Migration

  def change do
    create table(:driver_earnings) do
      add :driver_profile_id, references(:driver_profiles, on_delete: :restrict), null: false
      add :order_id, references(:orders, on_delete: :restrict), null: false
      add :base_pay, :integer, null: false, default: 0
      add :tip_amount, :integer, null: false, default: 0
      add :total_earned, :integer, null: false, default: 0
      add :period_start, :utc_datetime
      add :period_end, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:driver_earnings, [:driver_profile_id])
    create unique_index(:driver_earnings, [:order_id])
  end
end
