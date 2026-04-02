defmodule RestaurantDash.Repo.Migrations.AddKdsFields do
  use Ecto.Migration

  def change do
    # Add prep_time_minutes to menu_items (how long this item takes to prepare)
    alter table(:menu_items) do
      add :prep_time_minutes, :integer, default: 5
    end

    # Add KDS fields to orders
    alter table(:orders) do
      # Track when each KDS stage was entered
      add :accepted_at, :utc_datetime
      add :preparing_at, :utc_datetime
      add :ready_at, :utc_datetime

      # Estimated prep time in minutes (calculated when order is placed)
      add :estimated_prep_minutes, :integer

      # Whether this order is being manually managed by KDS staff
      # When true, the Oban lifecycle worker will not auto-transition statuses
      add :kds_managed, :boolean, default: false, null: false
    end
  end
end
