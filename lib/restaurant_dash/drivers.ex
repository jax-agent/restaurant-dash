defmodule RestaurantDash.Drivers do
  @moduledoc """
  The Drivers context.

  Manages driver profiles, availability, assignment, and dispatch.
  Driver profiles are separate from users (one-to-one) to keep driver-specific
  data isolated from the core auth system.
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Accounts
  alias RestaurantDash.Drivers.DriverProfile

  @pubsub RestaurantDash.PubSub

  # ─── PubSub ────────────────────────────────────────────────────────────────

  def subscribe_drivers(restaurant_id) do
    Phoenix.PubSub.subscribe(@pubsub, "drivers:#{restaurant_id}")
  end

  def subscribe_driver(driver_id) do
    Phoenix.PubSub.subscribe(@pubsub, "driver:#{driver_id}")
  end

  def broadcast_driver_update(driver_profile, restaurant_id) do
    event = {:driver_updated, driver_profile}
    Phoenix.PubSub.broadcast(@pubsub, "drivers:#{restaurant_id}", event)
    Phoenix.PubSub.broadcast(@pubsub, "driver:#{driver_profile.user_id}", event)
  end

  # ─── Registration ──────────────────────────────────────────────────────────

  @doc """
  Registers a new driver: creates a user with role "driver" and a driver_profile.
  Returns {:ok, %{user: user, profile: profile}} or {:error, :user | :profile, changeset}.
  """
  def register_driver(attrs) do
    Repo.transaction(fn ->
      user_attrs = Map.merge(attrs, %{"role" => "driver"})

      with {:ok, user} <- Accounts.register_user_with_role(user_attrs),
           {:ok, profile} <- create_profile(user, attrs) do
        %{user: user, profile: profile}
      else
        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp create_profile(user, attrs) do
    %DriverProfile{}
    |> DriverProfile.changeset(
      Map.merge(attrs, %{
        "user_id" => user.id,
        "is_approved" => false,
        "status" => "offline"
      })
    )
    |> Repo.insert()
  end

  # ─── Profile CRUD ──────────────────────────────────────────────────────────

  @doc "Get a driver profile by user_id."
  def get_profile_by_user_id(user_id) do
    DriverProfile
    |> where([dp], dp.user_id == ^user_id)
    |> Repo.one()
  end

  @doc "Get a driver profile by user_id, raising if not found."
  def get_profile_by_user_id!(user_id) do
    DriverProfile
    |> where([dp], dp.user_id == ^user_id)
    |> Repo.one!()
  end

  @doc "Get a driver profile by id."
  def get_profile!(id), do: Repo.get!(DriverProfile, id)

  @doc "Get a driver profile with user preloaded."
  def get_profile_with_user!(id) do
    DriverProfile
    |> where([dp], dp.id == ^id)
    |> Repo.one!()
    |> Repo.preload(:user)
  end

  @doc "List all driver profiles (for owner dashboard)."
  def list_profiles do
    DriverProfile
    |> order_by([dp], asc: dp.inserted_at)
    |> Repo.all()
    |> Repo.preload(:user)
  end

  @doc "List approved, available drivers for dispatch."
  def list_available_drivers do
    DriverProfile
    |> where([dp], dp.is_approved == true and dp.status == "available")
    |> Repo.all()
    |> Repo.preload(:user)
  end

  @doc "Update a driver's profile."
  def update_profile(%DriverProfile{} = profile, attrs) do
    profile
    |> DriverProfile.changeset(attrs)
    |> Repo.update()
  end

  # ─── Approval ──────────────────────────────────────────────────────────────

  @doc "Approve a driver (owner action)."
  def approve_driver(%DriverProfile{} = profile) do
    profile
    |> DriverProfile.approval_changeset(true)
    |> Repo.update()
  end

  @doc "Suspend/revoke a driver's approval (owner action)."
  def suspend_driver(%DriverProfile{} = profile) do
    profile
    |> DriverProfile.approval_changeset(false)
    |> Repo.update()
    |> tap_status_broadcast(profile)
  end

  # ─── Availability & Status ─────────────────────────────────────────────────

  @doc """
  Toggle driver availability. Only approved drivers can go available.
  Returns {:ok, profile} or {:error, reason}.
  """
  def set_status(%DriverProfile{is_approved: false}, "available") do
    {:error, "Driver must be approved before going available"}
  end

  def set_status(%DriverProfile{} = profile, status)
      when status in ["offline", "available", "on_delivery"] do
    profile
    |> DriverProfile.status_changeset(status)
    |> Repo.update()
  end

  def set_status(_, status), do: {:error, "Invalid status: #{status}"}

  @doc "Update driver's current GPS location."
  def update_location(%DriverProfile{} = profile, lat, lng) do
    profile
    |> DriverProfile.location_changeset(lat, lng)
    |> Repo.update()
  end

  # ─── Distance / Dispatch Helpers ───────────────────────────────────────────

  @doc """
  Find the nearest available driver to a given lat/lng.
  Uses the Haversine formula for distance calculation.
  Returns nil if no available drivers.
  """
  def find_nearest_driver(lat, lng) when is_float(lat) and is_float(lng) do
    list_available_drivers()
    |> Enum.filter(&(&1.current_lat != nil and &1.current_lng != nil))
    |> Enum.min_by(&haversine_km(&1.current_lat, &1.current_lng, lat, lng), fn -> nil end)
  end

  def find_nearest_driver(_, _), do: nil

  @doc """
  Calculate distance in km between two lat/lng points using the Haversine formula.
  """
  def haversine_km(lat1, lng1, lat2, lng2) do
    r = 6371.0
    dlat = deg_to_rad(lat2 - lat1)
    dlng = deg_to_rad(lng2 - lng1)

    a =
      :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(deg_to_rad(lat1)) * :math.cos(deg_to_rad(lat2)) *
          :math.sin(dlng / 2) * :math.sin(dlng / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    r * c
  end

  defp deg_to_rad(deg), do: deg * :math.pi() / 180.0

  # ─── Private ───────────────────────────────────────────────────────────────

  defp tap_status_broadcast({:ok, _profile} = result, _old_profile) do
    result
  end

  defp tap_status_broadcast(result, _), do: result
end
