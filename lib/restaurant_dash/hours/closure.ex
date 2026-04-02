defmodule RestaurantDash.Hours.Closure do
  use Ecto.Schema
  import Ecto.Changeset

  schema "closures" do
    field :date, :date
    field :reason, :string

    belongs_to :restaurant, RestaurantDash.Tenancy.Restaurant

    timestamps(type: :utc_datetime)
  end

  def changeset(closure, attrs) do
    closure
    |> cast(attrs, [:restaurant_id, :date, :reason])
    |> validate_required([:restaurant_id, :date])
    |> unique_constraint(:date, name: :closures_restaurant_id_date_index)
  end
end
