defmodule RestaurantDash.Delivery.DeliveryZone do
  use Ecto.Schema
  import Ecto.Changeset

  schema "delivery_zones" do
    field :name, :string
    # polygon stored as JSON array of [lat, lng] pairs
    field :polygon, {:array, {:array, :float}}, default: []
    field :delivery_fee, :integer, default: 0
    field :min_order, :integer, default: 0
    field :is_active, :boolean, default: true

    belongs_to :restaurant, RestaurantDash.Tenancy.Restaurant

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(zone, attrs) do
    zone
    |> cast(attrs, [:name, :polygon, :delivery_fee, :min_order, :is_active, :restaurant_id])
    |> validate_required([:name, :restaurant_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_number(:delivery_fee, greater_than_or_equal_to: 0)
    |> validate_number(:min_order, greater_than_or_equal_to: 0)
  end
end
