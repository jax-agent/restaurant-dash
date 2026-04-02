defmodule RestaurantDash.Repo.Migrations.CreateMenuCategories do
  use Ecto.Migration

  def change do
    create table(:menu_categories) do
      add :restaurant_id, references(:restaurants, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :position, :integer, default: 0, null: false
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:menu_categories, [:restaurant_id])
    create index(:menu_categories, [:restaurant_id, :position])
  end
end
