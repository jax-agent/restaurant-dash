defmodule RestaurantDash.Menu.Modifier do
  use Ecto.Schema
  import Ecto.Changeset

  schema "modifiers" do
    field :name, :string
    field :price_adjustment, :integer, default: 0
    field :position, :integer, default: 0
    field :is_active, :boolean, default: true

    belongs_to :modifier_group, RestaurantDash.Menu.ModifierGroup

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(modifier, attrs) do
    modifier
    |> cast(attrs, [:name, :price_adjustment, :position, :is_active, :modifier_group_id])
    |> validate_required([:name, :modifier_group_id])
    |> validate_length(:name, min: 1, max: 100)
    |> assoc_constraint(:modifier_group)
  end

  @doc """
  Format price adjustment as a string, e.g. 150 -> "+$1.50", 0 -> "Free", -100 -> "-$1.00"
  """
  def format_price_adjustment(0), do: "Free"

  def format_price_adjustment(cents) when cents > 0 do
    dollars = div(cents, 100)
    c = rem(cents, 100)
    "+$#{dollars}.#{String.pad_leading(Integer.to_string(c), 2, "0")}"
  end

  def format_price_adjustment(cents) when cents < 0 do
    abs_cents = abs(cents)
    dollars = div(abs_cents, 100)
    c = rem(abs_cents, 100)
    "-$#{dollars}.#{String.pad_leading(Integer.to_string(c), 2, "0")}"
  end
end
