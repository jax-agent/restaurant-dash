defmodule RestaurantDash.Repo.Migrations.CreateMenuItems do
  use Ecto.Migration

  def change do
    create table(:menu_items) do
      add :restaurant_id, references(:restaurants, on_delete: :delete_all), null: false
      add :menu_category_id, references(:menu_categories, on_delete: :nilify_all)
      add :name, :string, null: false
      add :description, :text
      add :price, :integer, null: false, default: 0
      add :image_url, :string
      add :position, :integer, default: 0, null: false
      add :is_active, :boolean, default: true, null: false
      add :is_available, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:menu_items, [:restaurant_id])
    create index(:menu_items, [:menu_category_id])
    create index(:menu_items, [:restaurant_id, :position])
  end
end
