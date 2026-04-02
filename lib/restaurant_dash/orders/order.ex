defmodule RestaurantDash.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_statuses ~w(new preparing out_for_delivery delivered)

  schema "orders" do
    field :customer_name, :string
    field :phone, :string
    field :items, {:array, :string}, default: []
    field :items_text, :string, virtual: true
    field :status, :string, default: "new"
    field :delivery_address, :string
    field :lat, :float
    field :lng, :float

    belongs_to :restaurant, RestaurantDash.Tenancy.Restaurant

    timestamps(type: :utc_datetime)
  end

  def valid_statuses, do: @valid_statuses

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :customer_name,
      :phone,
      :items,
      :items_text,
      :status,
      :delivery_address,
      :lat,
      :lng,
      :restaurant_id
    ])
    |> maybe_populate_items_from_text()
    |> validate_required([:customer_name])
    |> validate_items_present()
    |> validate_inclusion(:status, @valid_statuses)
  end

  defp validate_items_present(changeset) do
    items = get_field(changeset, :items, [])

    if is_list(items) and length(items) > 0 do
      changeset
    else
      add_error(changeset, :items, "can't be blank")
    end
  end

  defp maybe_populate_items_from_text(changeset) do
    case get_change(changeset, :items_text) do
      nil ->
        changeset

      text ->
        items =
          text
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        put_change(changeset, :items, items)
    end
  end

  def status_changeset(order, status) do
    order
    |> cast(%{status: status}, [:status])
    |> validate_inclusion(:status, @valid_statuses)
  end

  def position_changeset(order, lat, lng) do
    order
    |> cast(%{lat: lat, lng: lng}, [:lat, :lng])
  end
end
