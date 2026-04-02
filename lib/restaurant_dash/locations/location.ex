defmodule RestaurantDash.Locations.Location do
  use Ecto.Schema
  import Ecto.Changeset

  schema "locations" do
    field :name, :string
    field :address, :string
    field :city, :string
    field :state, :string
    field :zip, :string
    field :phone, :string
    field :lat, :float
    field :lng, :float
    field :is_active, :boolean, default: true
    field :is_primary, :boolean, default: false

    belongs_to :restaurant, RestaurantDash.Tenancy.Restaurant

    timestamps(type: :utc_datetime)
  end

  def changeset(location, attrs) do
    location
    |> cast(attrs, [
      :restaurant_id,
      :name,
      :address,
      :city,
      :state,
      :zip,
      :phone,
      :lat,
      :lng,
      :is_active,
      :is_primary
    ])
    |> validate_required([:restaurant_id, :name, :address])
    |> validate_length(:name, min: 1, max: 100)
  end
end
