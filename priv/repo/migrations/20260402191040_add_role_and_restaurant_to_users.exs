defmodule RestaurantDash.Repo.Migrations.AddRoleAndRestaurantToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "customer"
      add :name, :string
      add :restaurant_id, references(:restaurants, on_delete: :nilify_all)
    end

    create index(:users, [:restaurant_id])
    create index(:users, [:role])
  end
end
