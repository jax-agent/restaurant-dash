defmodule RestaurantDash.Repo.Migrations.CreateModifierGroups do
  use Ecto.Migration

  def change do
    create table(:modifier_groups) do
      add :restaurant_id, references(:restaurants, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :min_selections, :integer, default: 0, null: false
      add :max_selections, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:modifier_groups, [:restaurant_id])
  end
end
