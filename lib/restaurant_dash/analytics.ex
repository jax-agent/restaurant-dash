defmodule RestaurantDash.Analytics do
  @moduledoc """
  Analytics context for RestaurantDash.
  All queries are scoped by restaurant_id and date range.
  Money values are in cents.
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Orders.{Order, OrderItem}
  alias RestaurantDash.Menu.{Category, Item}

  # Statuses that count as "completed/revenue-generating"
  @revenue_statuses ~w(accepted preparing ready assigned picked_up out_for_delivery delivered)

  # ── Revenue Summary ────────────────────────────────────────────────────────

  @doc """
  Returns a revenue summary for the given restaurant and date range.

  Returns:
    - total_revenue: sum of total_amount for non-cancelled orders (cents)
    - order_count: number of qualifying orders
    - avg_order_value: average order value in cents (0 if no orders)
    - total_tips: sum of tip_amount (cents)
  """
  def revenue_summary(restaurant_id, start_dt, end_dt) do
    result =
      Order
      |> where([o], o.restaurant_id == ^restaurant_id)
      |> where([o], o.inserted_at >= ^start_dt and o.inserted_at <= ^end_dt)
      |> where([o], o.status in ^@revenue_statuses)
      |> select([o], %{
        total_revenue: coalesce(sum(o.total_amount), 0),
        order_count: count(o.id),
        total_tips: coalesce(sum(o.tip_amount), 0)
      })
      |> Repo.one()

    avg =
      if result.order_count > 0,
        do: div(result.total_revenue, result.order_count),
        else: 0

    Map.put(result, :avg_order_value, avg)
  end

  # ── Orders by Status ───────────────────────────────────────────────────────

  @doc """
  Returns a map of status => count for orders in the given date range.
  """
  def orders_by_status(restaurant_id, start_dt, end_dt) do
    Order
    |> where([o], o.restaurant_id == ^restaurant_id)
    |> where([o], o.inserted_at >= ^start_dt and o.inserted_at <= ^end_dt)
    |> group_by([o], o.status)
    |> select([o], {o.status, count(o.id)})
    |> Repo.all()
    |> Map.new()
  end

  # ── Orders by Hour ─────────────────────────────────────────────────────────

  @doc """
  Returns a list of %{hour: 0..23, count: integer} maps for orders in range.
  Sorted by hour ascending.
  """
  def orders_by_hour(restaurant_id, start_dt, end_dt) do
    Order
    |> where([o], o.restaurant_id == ^restaurant_id)
    |> where([o], o.inserted_at >= ^start_dt and o.inserted_at <= ^end_dt)
    |> group_by([o], fragment("EXTRACT(HOUR FROM ?)", o.inserted_at))
    |> order_by([o], asc: fragment("EXTRACT(HOUR FROM ?)", o.inserted_at))
    |> select([o], %{
      hour: type(fragment("EXTRACT(HOUR FROM ?)", o.inserted_at), :integer),
      count: count(o.id)
    })
    |> Repo.all()
  end

  # ── Orders by Day ──────────────────────────────────────────────────────────

  @doc """
  Returns a list of %{date: ~D[], count: integer} maps sorted ascending by date.
  """
  def orders_by_day(restaurant_id, start_dt, end_dt) do
    Order
    |> where([o], o.restaurant_id == ^restaurant_id)
    |> where([o], o.inserted_at >= ^start_dt and o.inserted_at <= ^end_dt)
    |> group_by([o], fragment("DATE(?)", o.inserted_at))
    |> order_by([o], asc: fragment("DATE(?)", o.inserted_at))
    |> select([o], %{
      date: fragment("DATE(?)", o.inserted_at),
      count: count(o.id)
    })
    |> Repo.all()
  end

  # ── Top Items ──────────────────────────────────────────────────────────────

  @doc """
  Returns top N (default 10) menu items by total quantity ordered in range.
  Each entry: %{menu_item_id, name, total_quantity, total_revenue, order_count}
  """
  def top_items(restaurant_id, start_dt, end_dt, limit \\ 10) do
    OrderItem
    |> join(:inner, [oi], o in Order, on: oi.order_id == o.id)
    |> where([oi, o], o.restaurant_id == ^restaurant_id)
    |> where([oi, o], o.inserted_at >= ^start_dt and o.inserted_at <= ^end_dt)
    |> where([oi], not is_nil(oi.menu_item_id))
    |> group_by([oi, o], [oi.menu_item_id, oi.name])
    |> order_by([oi, o], desc: sum(oi.quantity))
    |> limit(^limit)
    |> select([oi, o], %{
      menu_item_id: oi.menu_item_id,
      name: oi.name,
      total_quantity: coalesce(sum(oi.quantity), 0),
      total_revenue: coalesce(sum(oi.line_total), 0),
      order_count: count(oi.id)
    })
    |> Repo.all()
  end

  @doc """
  Returns items with the lowest order counts — candidates for removal.
  Each entry: %{menu_item_id, name, total_quantity, total_revenue}
  """
  def least_popular_items(restaurant_id, start_dt, end_dt, limit \\ 10) do
    OrderItem
    |> join(:inner, [oi], o in Order, on: oi.order_id == o.id)
    |> where([oi, o], o.restaurant_id == ^restaurant_id)
    |> where([oi, o], o.inserted_at >= ^start_dt and o.inserted_at <= ^end_dt)
    |> where([oi], not is_nil(oi.menu_item_id))
    |> group_by([oi, o], [oi.menu_item_id, oi.name])
    |> order_by([oi, o], asc: sum(oi.quantity))
    |> limit(^limit)
    |> select([oi, o], %{
      menu_item_id: oi.menu_item_id,
      name: oi.name,
      total_quantity: coalesce(sum(oi.quantity), 0),
      total_revenue: coalesce(sum(oi.line_total), 0)
    })
    |> Repo.all()
  end

  # ── Revenue by Category ────────────────────────────────────────────────────

  @doc """
  Returns revenue grouped by menu category.
  Each entry: %{category_id, category_name, total_revenue, item_count}
  """
  def revenue_by_category(restaurant_id, start_dt, end_dt) do
    OrderItem
    |> join(:inner, [oi], o in Order, on: oi.order_id == o.id)
    |> join(:inner, [oi, o], mi in Item, on: oi.menu_item_id == mi.id)
    |> join(:inner, [oi, o, mi], cat in Category, on: mi.menu_category_id == cat.id)
    |> where([oi, o, mi, cat], o.restaurant_id == ^restaurant_id)
    |> where([oi, o, mi, cat], o.inserted_at >= ^start_dt and o.inserted_at <= ^end_dt)
    |> group_by([oi, o, mi, cat], [cat.id, cat.name])
    |> order_by([oi, o, mi, cat], desc: sum(oi.line_total))
    |> select([oi, o, mi, cat], %{
      category_id: cat.id,
      category_name: cat.name,
      total_revenue: coalesce(sum(oi.line_total), 0),
      item_count: count(oi.id)
    })
    |> Repo.all()
  end

  # ── Customer Summary ───────────────────────────────────────────────────────

  @doc """
  Returns customer aggregation metrics:
  - unique_customers: distinct emails
  - repeat_customers: customers with > 1 order
  - repeat_rate: fraction of customers that are repeats (0.0 to 1.0)
  - avg_lifetime_value: average total spend per customer (cents)
  """
  def customer_summary(restaurant_id, start_dt, end_dt) do
    # Get per-customer order counts and spend
    per_customer =
      Order
      |> where([o], o.restaurant_id == ^restaurant_id)
      |> where([o], o.inserted_at >= ^start_dt and o.inserted_at <= ^end_dt)
      |> where([o], not is_nil(o.customer_email))
      |> group_by([o], o.customer_email)
      |> select([o], %{
        email: o.customer_email,
        order_count: count(o.id),
        total_spend: coalesce(sum(o.total_amount), 0)
      })
      |> Repo.all()

    unique = length(per_customer)
    repeats = Enum.count(per_customer, &(&1.order_count > 1))

    repeat_rate =
      if unique > 0, do: Float.round(repeats / unique * 100, 1), else: 0.0

    total_spend = Enum.reduce(per_customer, 0, &(&1.total_spend + &2))

    avg_lifetime_value =
      if unique > 0, do: div(total_spend, unique), else: 0

    %{
      unique_customers: unique,
      repeat_customers: repeats,
      repeat_rate: repeat_rate,
      avg_lifetime_value: avg_lifetime_value
    }
  end

  # ── Top Customers ──────────────────────────────────────────────────────────

  @doc """
  Returns top N customers by total spend.
  Each entry: %{customer_email, customer_name, order_count, total_spend}
  """
  def top_customers(restaurant_id, start_dt, end_dt, limit \\ 10) do
    Order
    |> where([o], o.restaurant_id == ^restaurant_id)
    |> where([o], o.inserted_at >= ^start_dt and o.inserted_at <= ^end_dt)
    |> where([o], not is_nil(o.customer_email))
    |> group_by([o], [o.customer_email, o.customer_name])
    |> order_by([o], desc: sum(o.total_amount))
    |> limit(^limit)
    |> select([o], %{
      customer_email: o.customer_email,
      customer_name: o.customer_name,
      order_count: count(o.id),
      total_spend: coalesce(sum(o.total_amount), 0)
    })
    |> Repo.all()
  end

  # ── Delivery Metrics ───────────────────────────────────────────────────────

  @doc """
  Returns delivery performance metrics:
  - avg_delivery_minutes: avg time from order placed to delivered
  - avg_prep_minutes: avg time from accepted to ready
  - delivered_count: number of delivered orders
  - cancelled_count: number of cancelled orders
  - cancellation_rate: as a percentage (0.0..100.0)
  """
  def delivery_metrics(restaurant_id, start_dt, end_dt) do
    # Core counts
    counts =
      Order
      |> where([o], o.restaurant_id == ^restaurant_id)
      |> where([o], o.inserted_at >= ^start_dt and o.inserted_at <= ^end_dt)
      |> select([o], %{
        total: count(o.id),
        delivered:
          sum(fragment("CASE WHEN ? = 'delivered' THEN 1 ELSE 0 END", o.status)),
        cancelled:
          sum(fragment("CASE WHEN ? = 'cancelled' THEN 1 ELSE 0 END", o.status))
      })
      |> Repo.one()

    # Average delivery time (placed → delivered)
    avg_delivery =
      Order
      |> where([o], o.restaurant_id == ^restaurant_id)
      |> where([o], o.inserted_at >= ^start_dt and o.inserted_at <= ^end_dt)
      |> where([o], o.status == "delivered" and not is_nil(o.delivered_at))
      |> select(
        [o],
        avg(
          fragment(
            "EXTRACT(EPOCH FROM (? - ?)) / 60",
            o.delivered_at,
            o.inserted_at
          )
        )
      )
      |> Repo.one()

    # Average prep time (accepted → ready)
    avg_prep =
      Order
      |> where([o], o.restaurant_id == ^restaurant_id)
      |> where([o], o.inserted_at >= ^start_dt and o.inserted_at <= ^end_dt)
      |> where([o], not is_nil(o.accepted_at) and not is_nil(o.ready_at))
      |> select(
        [o],
        avg(
          fragment(
            "EXTRACT(EPOCH FROM (? - ?)) / 60",
            o.ready_at,
            o.accepted_at
          )
        )
      )
      |> Repo.one()

    delivered = counts.delivered || 0
    cancelled = counts.cancelled || 0
    total = counts.total || 0
    cancellation_rate = if total > 0, do: Float.round(cancelled / total * 100, 1), else: 0.0

    avg_delivery_rounded = avg_delivery && Float.round(to_float(avg_delivery), 1)
    avg_prep_rounded = avg_prep && Float.round(to_float(avg_prep), 1)

    %{
      avg_delivery_minutes: avg_delivery_rounded,
      avg_prep_minutes: avg_prep_rounded,
      delivered_count: delivered,
      cancelled_count: cancelled,
      cancellation_rate: cancellation_rate
    }
  end

  @doc """
  Returns delivery performance per driver.
  Each entry: %{driver_id, driver_name, delivery_count, avg_delivery_minutes}
  """
  def delivery_by_driver(restaurant_id, start_dt, end_dt) do
    Order
    |> join(:left, [o], u in RestaurantDash.Accounts.User, on: o.driver_id == u.id)
    |> where([o, u], o.restaurant_id == ^restaurant_id)
    |> where([o, u], o.inserted_at >= ^start_dt and o.inserted_at <= ^end_dt)
    |> where([o, u], o.status == "delivered" and not is_nil(o.driver_id))
    |> group_by([o, u], [o.driver_id, u.name, u.email])
    |> order_by([o, u], desc: count(o.id))
    |> select([o, u], %{
      driver_id: o.driver_id,
      driver_name: coalesce(u.name, u.email),
      delivery_count: count(o.id),
      avg_delivery_minutes:
        avg(
          fragment(
            "EXTRACT(EPOCH FROM (? - ?)) / 60",
            o.delivered_at,
            o.inserted_at
          )
        )
    })
    |> Repo.all()
    |> Enum.map(fn r ->
      Map.update(r, :avg_delivery_minutes, nil, fn v ->
        v && Float.round(to_float(v), 1)
      end)
    end)
  end

  # ── Dashboard Quick Stats ──────────────────────────────────────────────────

  @doc """
  Returns today's stats compared to yesterday for the dashboard.
  """
  def dashboard_overview(restaurant_id) do
    now = DateTime.utc_now()
    today_start = %{now | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    yesterday_start = DateTime.add(today_start, -86_400, :second)
    yesterday_end = DateTime.add(today_start, -1, :second)

    today = revenue_summary(restaurant_id, today_start, now)
    yesterday = revenue_summary(restaurant_id, yesterday_start, yesterday_end)

    active_count =
      Order
      |> where([o], o.restaurant_id == ^restaurant_id)
      |> where([o], o.status in ~w(new accepted preparing ready assigned picked_up out_for_delivery))
      |> select([o], count(o.id))
      |> Repo.one()

    avg_delivery =
      delivery_metrics(restaurant_id, today_start, now).avg_delivery_minutes

    %{
      today_revenue: today.total_revenue,
      today_orders: today.order_count,
      today_avg_order: today.avg_order_value,
      yesterday_revenue: yesterday.total_revenue,
      yesterday_orders: yesterday.order_count,
      revenue_change: percent_change(yesterday.total_revenue, today.total_revenue),
      orders_change: percent_change(yesterday.order_count, today.order_count),
      active_orders: active_count,
      avg_delivery_minutes: avg_delivery
    }
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  @doc "Format cents to a dollar string, e.g. 1599 => \"15.99\""
  def format_money(nil), do: "$0.00"
  def format_money(0), do: "$0.00"

  def format_money(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    pennies = rem(cents, 100)
    "$#{dollars}.#{String.pad_leading(Integer.to_string(pennies), 2, "0")}"
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(f) when is_float(f), do: f
  defp to_float(i) when is_integer(i), do: i / 1.0

  @doc "Returns percentage change from old to new value (rounded to 1 decimal)."
  def percent_change(0, 0), do: 0.0
  def percent_change(0, _new), do: 100.0
  def percent_change(old, new), do: Float.round((new - old) / old * 100, 1)

  @doc "Builds a date range tuple for common presets."
  def date_range(:today) do
    now = DateTime.utc_now()
    start = %{now | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    {start, now}
  end

  def date_range(:yesterday) do
    now = DateTime.utc_now()
    today_start = %{now | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    start = DateTime.add(today_start, -86_400, :second)
    end_dt = DateTime.add(today_start, -1, :second)
    {start, end_dt}
  end

  def date_range(:this_week) do
    now = DateTime.utc_now()
    day_of_week = Date.day_of_week(DateTime.to_date(now))
    start = DateTime.add(now, -(day_of_week - 1) * 86_400, :second)
    start = %{start | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    {start, now}
  end

  def date_range(:this_month) do
    now = DateTime.utc_now()
    start = %{now | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    {start, now}
  end

  def date_range(:last_30_days) do
    now = DateTime.utc_now()
    start = DateTime.add(now, -30 * 86_400, :second)
    {start, now}
  end
end
