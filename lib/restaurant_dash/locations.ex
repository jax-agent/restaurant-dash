defmodule RestaurantDash.Locations do
  @moduledoc """
  Context for restaurant locations (multi-location support).
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Locations.Location

  # ─── CRUD ────────────────────────────────────────────────────────────────────

  def list_locations(restaurant_id) do
    Location
    |> where([l], l.restaurant_id == ^restaurant_id)
    |> order_by([l], asc: l.inserted_at)
    |> Repo.all()
  end

  def list_active_locations(restaurant_id) do
    Location
    |> where([l], l.restaurant_id == ^restaurant_id and l.is_active == true)
    |> order_by([l], desc: l.is_primary, asc: l.name)
    |> Repo.all()
  end

  def get_location!(id), do: Repo.get!(Location, id)

  def get_location(id), do: Repo.get(Location, id)

  def get_primary_location(restaurant_id) do
    Location
    |> where(
      [l],
      l.restaurant_id == ^restaurant_id and l.is_primary == true and l.is_active == true
    )
    |> Repo.one()
  end

  def create_location(attrs) do
    result =
      %Location{}
      |> Location.changeset(attrs)
      |> Repo.insert()

    # If this is the first location, make it primary
    case result do
      {:ok, location} ->
        if list_locations(location.restaurant_id) |> length() == 1 do
          set_primary(location)
        else
          {:ok, location}
        end

      err ->
        err
    end
  end

  def update_location(%Location{} = location, attrs) do
    location
    |> Location.changeset(attrs)
    |> Repo.update()
  end

  def deactivate_location(%Location{} = location) do
    location
    |> Ecto.Changeset.change(%{is_active: false, is_primary: false})
    |> Repo.update()
  end

  def delete_location(%Location{} = location) do
    Repo.delete(location)
  end

  @doc """
  Sets a location as primary, clears is_primary on all others for this restaurant.
  """
  def set_primary(%Location{} = location) do
    Repo.transaction(fn ->
      # Clear existing primary
      Location
      |> where([l], l.restaurant_id == ^location.restaurant_id)
      |> Repo.update_all(set: [is_primary: false])

      # Set new primary
      {:ok, updated} =
        location
        |> Ecto.Changeset.change(%{is_primary: true})
        |> Repo.update()

      updated
    end)
  end

  # ─── Nearest location ─────────────────────────────────────────────────────────

  @doc """
  Find the nearest active location to the given lat/lng.
  Uses Haversine approximation.
  Returns the nearest Location or nil if no locations with coordinates.
  """
  def find_nearest(restaurant_id, lat, lng) do
    locations =
      restaurant_id
      |> list_active_locations()
      |> Enum.filter(&(not is_nil(&1.lat) and not is_nil(&1.lng)))

    case locations do
      [] ->
        nil

      locs ->
        Enum.min_by(locs, &haversine_distance({lat, lng}, {&1.lat, &1.lng}))
    end
  end

  @doc """
  Calculates Haversine distance in km between two {lat, lng} pairs.
  """
  def haversine_distance({lat1, lng1}, {lat2, lng2}) do
    r = 6371.0
    dlat = :math.pi() / 180 * (lat2 - lat1)
    dlng = :math.pi() / 180 * (lng2 - lng1)

    a =
      :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(:math.pi() / 180 * lat1) *
          :math.cos(:math.pi() / 180 * lat2) *
          :math.sin(dlng / 2) * :math.sin(dlng / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    r * c
  end
end
