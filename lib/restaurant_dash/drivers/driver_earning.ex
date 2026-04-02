defmodule RestaurantDash.Drivers.DriverEarning do
  use Ecto.Schema
  import Ecto.Changeset

  schema "driver_earnings" do
    field :base_pay, :integer, default: 0
    field :tip_amount, :integer, default: 0
    field :total_earned, :integer, default: 0
    field :period_start, :utc_datetime
    field :period_end, :utc_datetime

    belongs_to :driver_profile, RestaurantDash.Drivers.DriverProfile
    belongs_to :order, RestaurantDash.Orders.Order

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(earning, attrs) do
    earning
    |> cast(attrs, [
      :driver_profile_id,
      :order_id,
      :base_pay,
      :tip_amount,
      :total_earned,
      :period_start,
      :period_end
    ])
    |> validate_required([:driver_profile_id, :order_id])
    |> validate_number(:base_pay, greater_than_or_equal_to: 0)
    |> validate_number(:tip_amount, greater_than_or_equal_to: 0)
    |> validate_number(:total_earned, greater_than_or_equal_to: 0)
    |> unique_constraint(:order_id)
  end
end
