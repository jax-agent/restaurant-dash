defmodule RestaurantDash.Drivers.DriverProfile do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_vehicle_types ~w(car bike scooter)
  # offline: not working today
  # available: online and ready to take deliveries
  # on_delivery: currently delivering an order
  @valid_statuses ~w(offline available on_delivery)

  def valid_vehicle_types, do: @valid_vehicle_types
  def valid_statuses, do: @valid_statuses

  schema "driver_profiles" do
    field :vehicle_type, :string, default: "car"
    field :license_plate, :string
    field :phone, :string
    field :is_available, :boolean, default: false
    field :is_approved, :boolean, default: false
    field :status, :string, default: "offline"
    field :current_lat, :float
    field :current_lng, :float
    field :last_location_at, :utc_datetime

    belongs_to :user, RestaurantDash.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating a driver profile."
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :user_id,
      :vehicle_type,
      :license_plate,
      :phone,
      :is_available,
      :is_approved,
      :status,
      :current_lat,
      :current_lng
    ])
    |> validate_required([:user_id, :vehicle_type])
    |> validate_inclusion(:vehicle_type, @valid_vehicle_types,
      message: "must be one of: #{Enum.join(@valid_vehicle_types, ", ")}"
    )
    |> validate_inclusion(:status, @valid_statuses,
      message: "must be one of: #{Enum.join(@valid_statuses, ", ")}"
    )
    |> unique_constraint(:user_id)
  end

  @doc "Changeset for updating availability status."
  def status_changeset(profile, status) do
    is_available = status == "available"

    profile
    |> cast(%{status: status, is_available: is_available}, [:status, :is_available])
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc "Changeset for updating location."
  def location_changeset(profile, lat, lng) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    profile
    |> cast(%{current_lat: lat, current_lng: lng, last_location_at: now}, [
      :current_lat,
      :current_lng,
      :last_location_at
    ])
  end

  @doc "Changeset for approval/suspension."
  def approval_changeset(profile, approved?) do
    profile
    |> cast(%{is_approved: approved?}, [:is_approved])
  end
end
