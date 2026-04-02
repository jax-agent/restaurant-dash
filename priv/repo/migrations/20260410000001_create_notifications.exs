defmodule RestaurantDash.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add :restaurant_id, references(:restaurants, on_delete: :delete_all), null: false
      add :order_id, references(:orders, on_delete: :nilify_all), null: true
      add :recipient_type, :string, null: false
      add :recipient_contact, :string, null: false
      add :channel, :string, null: false
      add :template, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "pending"
      add :sent_at, :utc_datetime
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create index(:notifications, [:restaurant_id])
    create index(:notifications, [:order_id])
    create index(:notifications, [:status])
    create index(:notifications, [:channel])
    create index(:notifications, [:inserted_at])
  end
end
