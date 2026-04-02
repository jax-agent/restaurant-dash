defmodule RestaurantDash.Menu.ModifierGroup do
  use Ecto.Schema
  import Ecto.Changeset

  schema "modifier_groups" do
    field :name, :string
    field :min_selections, :integer, default: 0
    field :max_selections, :integer

    belongs_to :restaurant, RestaurantDash.Tenancy.Restaurant
    has_many :modifiers, RestaurantDash.Menu.Modifier

    many_to_many :items, RestaurantDash.Menu.Item,
      join_through: "menu_item_modifier_groups",
      join_keys: [modifier_group_id: :id, menu_item_id: :id]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :min_selections, :max_selections, :restaurant_id])
    |> validate_required([:name, :restaurant_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_number(:min_selections, greater_than_or_equal_to: 0)
    |> validate_max_selections()
    |> assoc_constraint(:restaurant)
  end

  defp validate_max_selections(changeset) do
    min = get_field(changeset, :min_selections) || 0
    max = get_field(changeset, :max_selections)

    if max && max < min do
      add_error(changeset, :max_selections, "must be greater than or equal to min_selections")
    else
      changeset
    end
  end

  @doc """
  Returns true if this group allows multiple selections.
  """
  def multi_select?(%__MODULE__{max_selections: max}) when is_nil(max), do: true
  def multi_select?(%__MODULE__{max_selections: max}), do: max > 1

  @doc """
  Returns true if this group is optional (min_selections == 0).
  """
  def optional?(%__MODULE__{min_selections: min}), do: min == 0
end
