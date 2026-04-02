defmodule RestaurantDash.Repo.Migrations.CreateMenuItemModifierGroups do
  use Ecto.Migration

  def change do
    create table(:menu_item_modifier_groups) do
      add :menu_item_id, references(:menu_items, on_delete: :delete_all), null: false
      add :modifier_group_id, references(:modifier_groups, on_delete: :delete_all), null: false
    end

    create unique_index(:menu_item_modifier_groups, [:menu_item_id, :modifier_group_id])
    create index(:menu_item_modifier_groups, [:menu_item_id])
    create index(:menu_item_modifier_groups, [:modifier_group_id])
  end
end
