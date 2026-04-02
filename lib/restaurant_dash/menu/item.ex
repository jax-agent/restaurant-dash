defmodule RestaurantDash.Menu.Item do
  use Ecto.Schema
  import Ecto.Changeset

  schema "menu_items" do
    field :name, :string
    field :description, :string
    field :price, :integer, default: 0
    field :image_url, :string
    field :position, :integer, default: 0
    field :is_active, :boolean, default: true
    field :is_available, :boolean, default: true

    belongs_to :restaurant, RestaurantDash.Tenancy.Restaurant
    belongs_to :category, RestaurantDash.Menu.Category, foreign_key: :menu_category_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :name,
      :description,
      :price,
      :image_url,
      :position,
      :is_active,
      :is_available,
      :restaurant_id,
      :menu_category_id
    ])
    |> validate_required([:name, :price, :restaurant_id])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> assoc_constraint(:restaurant)
    |> assoc_constraint(:category)
  end

  @doc """
  Format price in cents as a dollars string, e.g. 1599 -> "$15.99"
  """
  def format_price(price_cents) when is_integer(price_cents) do
    dollars = div(price_cents, 100)
    cents = rem(price_cents, 100)
    "$#{dollars}.#{String.pad_leading(Integer.to_string(cents), 2, "0")}"
  end

  def format_price(_), do: "$0.00"
end
