defmodule RestaurantDash.Delivery do
  @moduledoc """
  Delivery context: zones, fee calculation, and delivery validation.

  Handles:
  - Delivery zone CRUD (polygon-based)
  - Point-in-polygon check (ray casting algorithm)
  - Delivery fee calculation (flat / zone / distance modes)
  - Free delivery threshold
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Delivery.DeliveryZone
  alias RestaurantDash.Tenancy.Restaurant
  alias RestaurantDash.Drivers

  # ─── Zone CRUD ─────────────────────────────────────────────────────────────

  @doc "List all active delivery zones for a restaurant."
  def list_zones(restaurant_id) do
    DeliveryZone
    |> where([z], z.restaurant_id == ^restaurant_id)
    |> order_by([z], asc: z.name)
    |> Repo.all()
  end

  @doc "List only active zones for a restaurant."
  def list_active_zones(restaurant_id) do
    DeliveryZone
    |> where([z], z.restaurant_id == ^restaurant_id and z.is_active == true)
    |> order_by([z], asc: z.name)
    |> Repo.all()
  end

  @doc "Get a delivery zone by id."
  def get_zone!(id), do: Repo.get!(DeliveryZone, id)

  @doc "Create a new delivery zone."
  def create_zone(attrs) do
    %DeliveryZone{}
    |> DeliveryZone.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Update a delivery zone."
  def update_zone(%DeliveryZone{} = zone, attrs) do
    zone
    |> DeliveryZone.changeset(attrs)
    |> Repo.update()
  end

  @doc "Delete a delivery zone."
  def delete_zone(%DeliveryZone{} = zone) do
    Repo.delete(zone)
  end

  @doc "Change for a zone (for form use)."
  def change_zone(%DeliveryZone{} = zone, attrs \\ %{}) do
    DeliveryZone.changeset(zone, attrs)
  end

  # ─── Point-in-Polygon (Ray Casting) ────────────────────────────────────────

  @doc """
  Checks whether a point {lat, lng} is inside a polygon.

  The polygon is a list of [lat, lng] points forming a closed ring.
  Uses the ray casting algorithm (even-odd rule).

  Returns true if inside, false otherwise.
  """
  def point_in_polygon?(_lat, _lng, []), do: false
  def point_in_polygon?(_lat, _lng, polygon) when length(polygon) < 3, do: false

  def point_in_polygon?(lat, lng, polygon) do
    # Cast a ray from the point to +infinity on the X axis
    # Count how many polygon edges it crosses — odd = inside, even = outside
    n = length(polygon)

    {_, inside} =
      Enum.reduce(0..(n - 1), {n - 1, false}, fn i, {j, inside} ->
        [ilat, ilng] = Enum.at(polygon, i)
        [jlat, jlng] = Enum.at(polygon, j)

        crosses? =
          ilng > lng != jlng > lng and
            lat < (jlat - ilat) * (lng - ilng) / (jlng - ilng) + ilat

        {i, if(crosses?, do: !inside, else: inside)}
      end)

    inside
  end

  # ─── Zone Lookup ───────────────────────────────────────────────────────────

  @doc """
  Find the delivery zone that contains the given point.
  Returns the first matching active zone, or nil.
  """
  def find_zone_for_point(restaurant_id, lat, lng) do
    restaurant_id
    |> list_active_zones()
    |> Enum.find(fn zone ->
      point_in_polygon?(lat, lng, zone.polygon)
    end)
  end

  # ─── Fee Calculation ───────────────────────────────────────────────────────

  @doc """
  Calculate the delivery fee for an order.

  Returns {:ok, fee_cents} or {:error, reason}

  fee_mode:
  - "flat"     — always base_delivery_fee
  - "zone"     — fee from the zone containing the delivery point
  - "distance" — base_delivery_fee + (miles * per_mile_rate)

  Free delivery: if free_delivery_threshold > 0 and subtotal >= threshold, fee = 0.
  """
  def calculate_delivery_fee(%Restaurant{} = restaurant, lat, lng, subtotal_cents) do
    # Check free delivery threshold
    threshold = restaurant.free_delivery_threshold || 0

    if threshold > 0 and subtotal_cents >= threshold do
      {:ok, 0}
    else
      do_calculate_fee(restaurant, lat, lng)
    end
  end

  defp do_calculate_fee(%Restaurant{fee_mode: "flat"} = restaurant, _lat, _lng) do
    {:ok, restaurant.base_delivery_fee || 299}
  end

  defp do_calculate_fee(%Restaurant{fee_mode: "zone"} = restaurant, lat, lng)
       when not is_nil(lat) and not is_nil(lng) do
    case find_zone_for_point(restaurant.id, lat, lng) do
      nil -> {:error, :outside_delivery_area}
      zone -> {:ok, zone.delivery_fee}
    end
  end

  defp do_calculate_fee(%Restaurant{fee_mode: "zone"}, _lat, _lng) do
    {:error, :no_coordinates}
  end

  defp do_calculate_fee(%Restaurant{fee_mode: "distance"} = restaurant, lat, lng)
       when not is_nil(lat) and not is_nil(lng) and not is_nil(restaurant.lat) and
              not is_nil(restaurant.lng) do
    distance_km = Drivers.haversine_km(restaurant.lat, restaurant.lng, lat, lng)
    distance_miles = distance_km * 0.621371

    base = restaurant.base_delivery_fee || 299
    per_mile = restaurant.per_mile_rate || 50
    fee = base + round(distance_miles * per_mile)

    {:ok, fee}
  end

  defp do_calculate_fee(%Restaurant{fee_mode: "distance"} = restaurant, _lat, _lng) do
    {:ok, restaurant.base_delivery_fee || 299}
  end

  defp do_calculate_fee(%Restaurant{} = restaurant, _lat, _lng) do
    {:ok, restaurant.base_delivery_fee || 299}
  end

  # ─── Checkout Validation ───────────────────────────────────────────────────

  @doc """
  Validates that the given lat/lng is within a delivery zone (for "zone" fee mode).
  For other modes, always returns :ok.

  Returns :ok or {:error, :outside_delivery_area}
  """
  def validate_delivery_address(%Restaurant{fee_mode: "zone"} = restaurant, lat, lng) do
    case find_zone_for_point(restaurant.id, lat, lng) do
      nil -> {:error, :outside_delivery_area}
      _zone -> :ok
    end
  end

  def validate_delivery_address(_restaurant, _lat, _lng), do: :ok
end
