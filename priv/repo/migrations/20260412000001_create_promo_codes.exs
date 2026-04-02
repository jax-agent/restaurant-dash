defmodule RestaurantDash.Repo.Migrations.CreatePromoCodes do
  use Ecto.Migration

  def change do
    create table(:promo_codes) do
      add :restaurant_id, references(:restaurants, on_delete: :delete_all), null: false
      add :code, :string, null: false
      add :discount_type, :string, null: false
      add :discount_value, :integer, null: false
      add :min_order, :integer
      add :max_uses, :integer
      add :current_uses, :integer, default: 0, null: false
      add :expires_at, :utc_datetime
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:promo_codes, [:restaurant_id, :code])
    create index(:promo_codes, [:restaurant_id])
  end
end
