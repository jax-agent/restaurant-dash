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

    # Phase 3: Customer ordering fields
    field :customer_email, :string
    field :customer_phone, :string
    field :subtotal, :integer, default: 0
    field :tax_amount, :integer, default: 0
    field :delivery_fee, :integer, default: 0
    field :tip_amount, :integer, default: 0
    field :total_amount, :integer, default: 0

    # Phase 4: Payment fields
    field :payment_status, :string, default: "pending"
    field :payment_intent_id, :string

    belongs_to :restaurant, RestaurantDash.Tenancy.Restaurant
    has_many :order_items, RestaurantDash.Orders.OrderItem

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
      :restaurant_id,
      :customer_email,
      :customer_phone,
      :subtotal,
      :tax_amount,
      :delivery_fee,
      :tip_amount,
      :total_amount
    ])
    |> maybe_populate_items_from_text()
    |> validate_required([:customer_name])
    |> validate_items_present()
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_format(:customer_email, ~r/^[^\s]+@[^\s]+$/, message: "is not a valid email")
  end

  @doc "Changeset for creating an order from a cart (no legacy items array required)."
  def cart_order_changeset(order, attrs) do
    order
    |> cast(attrs, [
      :customer_name,
      :customer_email,
      :customer_phone,
      :delivery_address,
      :status,
      :restaurant_id,
      :subtotal,
      :tax_amount,
      :delivery_fee,
      :tip_amount,
      :total_amount,
      :payment_status,
      :payment_intent_id
    ])
    |> validate_required([
      :customer_name,
      :customer_email,
      :customer_phone,
      :delivery_address,
      :restaurant_id
    ])
    |> validate_format(:customer_email, ~r/^[^\s]+@[^\s]+$/, message: "is not a valid email")
    |> validate_inclusion(:status, @valid_statuses)
    |> put_change(:items, [])
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

  defp validate_items_present(changeset) do
    # Only validate items present if NOT using cart_order_changeset path
    # (cart orders have items via order_items association)
    items = get_field(changeset, :items, [])

    if is_list(items) and length(items) > 0 do
      changeset
    else
      # Don't error if we have a restaurant_id AND explicit empty (cart flow sets [])
      case get_change(changeset, :items) do
        [] -> changeset
        _ -> add_error(changeset, :items, "can't be blank")
      end
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
end
