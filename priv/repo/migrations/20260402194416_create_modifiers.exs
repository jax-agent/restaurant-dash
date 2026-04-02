defmodule RestaurantDash.Repo.Migrations.CreateModifiers do
  use Ecto.Migration

  def change do
    create table(:modifiers) do
      add :modifier_group_id, references(:modifier_groups, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :price_adjustment, :integer, default: 0, null: false
      add :position, :integer, default: 0, null: false
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:modifiers, [:modifier_group_id])
  end
end
