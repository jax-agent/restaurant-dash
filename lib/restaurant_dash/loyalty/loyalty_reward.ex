defmodule RestaurantDash.Loyalty.LoyaltyReward do
  use Ecto.Schema
  import Ecto.Changeset

  schema "loyalty_rewards" do
    field :name, :string
    field :points_cost, :integer
    field :discount_value, :integer
    field :is_active, :boolean, default: true

    belongs_to :restaurant, RestaurantDash.Tenancy.Restaurant

    timestamps(type: :utc_datetime)
  end

  def changeset(reward, attrs) do
    reward
    |> cast(attrs, [:restaurant_id, :name, :points_cost, :discount_value, :is_active])
    |> validate_required([:restaurant_id, :name, :points_cost, :discount_value])
    |> validate_number(:points_cost, greater_than: 0)
    |> validate_number(:discount_value, greater_than: 0)
  end
end
