defmodule RestaurantDash.Hours do
  @moduledoc """
  Context for restaurant operating hours and holiday closures.
  All time comparisons happen in the restaurant's configured timezone.
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Hours.{OperatingHour, Closure}

  # ─── Operating Hours CRUD ────────────────────────────────────────────────────

  def list_hours(restaurant_id) do
    OperatingHour
    |> where([h], h.restaurant_id == ^restaurant_id)
    |> order_by([h], asc: h.day_of_week)
    |> Repo.all()
  end

  def get_hours_for_day(restaurant_id, day_of_week) do
    OperatingHour
    |> where([h], h.restaurant_id == ^restaurant_id and h.day_of_week == ^day_of_week)
    |> Repo.one()
  end

  def upsert_hours(attrs) do
    case get_hours_for_day(
           attrs[:restaurant_id] || attrs["restaurant_id"],
           attrs[:day_of_week] || attrs["day_of_week"]
         ) do
      nil ->
        %OperatingHour{}
        |> OperatingHour.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> OperatingHour.changeset(attrs)
        |> Repo.update()
    end
  end

  def delete_hours(%OperatingHour{} = hour), do: Repo.delete(hour)

  # ─── Closures CRUD ────────────────────────────────────────────────────────────

  def list_closures(restaurant_id) do
    Closure
    |> where([c], c.restaurant_id == ^restaurant_id)
    |> order_by([c], asc: c.date)
    |> Repo.all()
  end

  def list_upcoming_closures(restaurant_id) do
    today = Date.utc_today()

    Closure
    |> where([c], c.restaurant_id == ^restaurant_id and c.date >= ^today)
    |> order_by([c], asc: c.date)
    |> Repo.all()
  end

  def create_closure(attrs) do
    %Closure{}
    |> Closure.changeset(attrs)
    |> Repo.insert()
  end

  def delete_closure(%Closure{} = closure), do: Repo.delete(closure)

  # ─── Open/Closed detection ────────────────────────────────────────────────────

  @doc """
  Is the restaurant open right now?
  Checks timezone-adjusted current time against operating hours and closures.
  Returns {:open} | {:closed, reason}
  """
  def is_open?(restaurant_id, timezone \\ "America/Chicago") do
    now_utc = DateTime.utc_now()
    now_local = DateTime.shift_zone!(now_utc, timezone)
    today = DateTime.to_date(now_local)
    current_time = DateTime.to_time(now_local)
    day_of_week = Date.day_of_week(today, :sunday) - 1

    cond do
      has_closure?(restaurant_id, today) ->
        {:closed, "Closed today"}

      true ->
        case get_hours_for_day(restaurant_id, day_of_week) do
          nil ->
            {:closed, "No hours set"}

          %OperatingHour{is_closed: true} ->
            {:closed, "Closed today"}

          %OperatingHour{open_time: open, close_time: close} ->
            if Time.compare(current_time, open) != :lt and
                 Time.compare(current_time, close) == :lt do
              {:open}
            else
              if Time.compare(current_time, close) != :lt do
                {:closed, "Closed for today"}
              else
                {:closed, "Opens at #{format_time(open)}"}
              end
            end
        end
    end
  end

  @doc "Returns the next open time string if the restaurant is closed."
  def next_open_time(restaurant_id, timezone \\ "America/Chicago") do
    now_utc = DateTime.utc_now()
    now_local = DateTime.shift_zone!(now_utc, timezone)
    today = DateTime.to_date(now_local)
    day_of_week = Date.day_of_week(today, :sunday) - 1

    case get_hours_for_day(restaurant_id, day_of_week) do
      %OperatingHour{is_closed: false, open_time: open} ->
        format_time(open)

      _ ->
        # Look through next 7 days
        Enum.find_value(1..7, "Unknown", fn offset ->
          future_day = Date.add(today, offset)
          future_dow = Date.day_of_week(future_day, :sunday) - 1

          case get_hours_for_day(restaurant_id, future_dow) do
            %OperatingHour{is_closed: false, open_time: open} ->
              day_name = day_name(future_dow)
              "#{day_name} at #{format_time(open)}"

            _ ->
              nil
          end
        end)
    end
  end

  # ─── Private ─────────────────────────────────────────────────────────────────

  defp has_closure?(restaurant_id, date) do
    Repo.exists?(
      from c in Closure,
        where: c.restaurant_id == ^restaurant_id and c.date == ^date
    )
  end

  defp format_time(%Time{hour: h, minute: m}) do
    period = if h < 12, do: "AM", else: "PM"
    display_hour = rem(h, 12) |> then(fn x -> if x == 0, do: 12, else: x end)
    "#{display_hour}:#{String.pad_leading(Integer.to_string(m), 2, "0")} #{period}"
  end

  defp day_name(0), do: "Sunday"
  defp day_name(1), do: "Monday"
  defp day_name(2), do: "Tuesday"
  defp day_name(3), do: "Wednesday"
  defp day_name(4), do: "Thursday"
  defp day_name(5), do: "Friday"
  defp day_name(6), do: "Saturday"
  defp day_name(_), do: "Unknown"
end
