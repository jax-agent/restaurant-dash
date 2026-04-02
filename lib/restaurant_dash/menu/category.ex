defmodule RestaurantDash.Menu.Category do
  use Ecto.Schema
  import Ecto.Changeset

  schema "menu_categories" do
    field :name, :string
    field :description, :string
    field :position, :integer, default: 0
    field :is_active, :boolean, default: true

    belongs_to :restaurant, RestaurantDash.Tenancy.Restaurant
    has_many :items, RestaurantDash.Menu.Item, foreign_key: :menu_category_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description, :position, :is_active, :restaurant_id])
    |> validate_required([:name, :restaurant_id])
    |> validate_length(:name, min: 1, max: 100)
    |> assoc_constraint(:restaurant)
  end
end
