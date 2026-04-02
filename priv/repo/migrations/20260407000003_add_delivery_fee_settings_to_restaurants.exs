defmodule RestaurantDash.Repo.Migrations.AddDeliveryFeeSettingsToRestaurants do
  use Ecto.Migration

  def change do
    alter table(:restaurants) do
      # "zone" | "distance" | "flat"
      add :fee_mode, :string, default: "flat"
      # flat fee in cents (used for "flat" and as base for "distance")
      add :base_delivery_fee, :integer, default: 299
      # cents per mile (used for "distance" mode)
      add :per_mile_rate, :integer, default: 50
      # cents: orders above this get free delivery (0 = disabled)
      add :free_delivery_threshold, :integer, default: 0
      # base pay per delivery for drivers in cents
      add :driver_base_pay, :integer, default: 500
      # driver pay per mile in cents
      add :driver_per_mile_pay, :integer, default: 50
    end
  end
end
