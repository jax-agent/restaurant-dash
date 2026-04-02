defmodule RestaurantDash.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  # Full lifecycle: new → accepted → preparing → ready → assigned → picked_up → out_for_delivery → delivered
  # cancelled: terminal rejection state (can come from any active state)
  @valid_statuses ~w(new accepted preparing ready assigned picked_up out_for_delivery delivered cancelled)

  # Statuses that are shown on the KDS board (not terminal)
  @kds_statuses ~w(new accepted preparing ready)

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

    # Phase 5: KDS fields
    field :accepted_at, :utc_datetime
    field :preparing_at, :utc_datetime
    field :ready_at, :utc_datetime
    field :estimated_prep_minutes, :integer
    field :kds_managed, :boolean, default: false

    # Phase 6: Driver/delivery fields
    field :assigned_at, :utc_datetime
    field :picked_up_at, :utc_datetime
    field :delivered_at, :utc_datetime

    belongs_to :restaurant, RestaurantDash.Tenancy.Restaurant
    belongs_to :driver, RestaurantDash.Accounts.User
    has_many :order_items, RestaurantDash.Orders.OrderItem

    timestamps(type: :utc_datetime)
  end

  def valid_statuses, do: @valid_statuses
  def kds_statuses, do: @kds_statuses

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
      :payment_intent_id,
      :estimated_prep_minutes
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

  @doc "Changeset for KDS status transitions — sets status + timestamp + kds_managed flag."
  def kds_transition_changeset(order, status) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    timestamp_field = timestamp_for_status(status)

    attrs =
      %{status: status, kds_managed: true}
      |> then(fn a ->
        if timestamp_field, do: Map.put(a, timestamp_field, now), else: a
      end)

    order
    |> cast(attrs, [
      :status,
      :kds_managed,
      :accepted_at,
      :preparing_at,
      :ready_at,
      :assigned_at,
      :picked_up_at,
      :delivered_at
    ])
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc "Changeset for driver assignment."
  def assign_driver_changeset(order, driver_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    order
    |> cast(%{driver_id: driver_id, status: "assigned", assigned_at: now}, [
      :driver_id,
      :status,
      :assigned_at
    ])
    |> validate_required([:driver_id])
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc "Changeset for driver delivery status updates (picked_up, delivered)."
  def delivery_transition_changeset(order, status) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    timestamp_field = timestamp_for_status(status)

    attrs =
      %{status: status}
      |> then(fn a ->
        if timestamp_field, do: Map.put(a, timestamp_field, now), else: a
      end)

    order
    |> cast(attrs, [:status, :picked_up_at, :delivered_at])
    |> validate_inclusion(:status, @valid_statuses)
  end

  def position_changeset(order, lat, lng) do
    order
    |> cast(%{lat: lat, lng: lng}, [:lat, :lng])
  end

  def prep_time_changeset(order, minutes) do
    order
    |> cast(%{estimated_prep_minutes: minutes}, [:estimated_prep_minutes])
    |> validate_number(:estimated_prep_minutes, greater_than: 0)
  end

  defp timestamp_for_status("accepted"), do: :accepted_at
  defp timestamp_for_status("preparing"), do: :preparing_at
  defp timestamp_for_status("ready"), do: :ready_at
  defp timestamp_for_status("assigned"), do: :assigned_at
  defp timestamp_for_status("picked_up"), do: :picked_up_at
  defp timestamp_for_status("delivered"), do: :delivered_at
  defp timestamp_for_status(_), do: nil

  defp validate_items_present(changeset) do
    items = get_field(changeset, :items, [])

    if is_list(items) and length(items) > 0 do
      changeset
    else
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
