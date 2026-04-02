defmodule RestaurantDash.Repo.Migrations.CreateRestaurants do
  use Ecto.Migration

  def change do
    create table(:restaurants) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :phone, :string
      add :address, :string
      add :city, :string
      add :state, :string
      add :zip, :string
      add :primary_color, :string, default: "#E63946"
      add :logo_url, :string
      add :timezone, :string, default: "America/Chicago"
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:restaurants, [:slug])
    create index(:restaurants, [:is_active])
  end
end
