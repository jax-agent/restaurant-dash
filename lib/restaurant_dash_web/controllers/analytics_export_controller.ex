defmodule RestaurantDashWeb.AnalyticsExportController do
  @moduledoc """
  Handles CSV export downloads for analytics data.
  """
  use RestaurantDashWeb, :controller

  alias RestaurantDash.{Analytics, Tenancy}

  @valid_ranges ~w(today yesterday this_week this_month last_30_days)

  def sales_csv(conn, params) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, restaurant} <- authorize(user) do
      range = parse_range(params["range"])
      {start_dt, end_dt} = Analytics.date_range(range)

      summary = Analytics.revenue_summary(restaurant.id, start_dt, end_dt)
      orders_by_day = Analytics.orders_by_day(restaurant.id, start_dt, end_dt)

      csv_data = build_sales_csv(summary, orders_by_day, range)
      filename = "sales-#{range}-#{Date.utc_today()}.csv"

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, csv_data)
    else
      {:error, :unauthenticated} ->
        conn
        |> put_flash(:error, "You must be logged in.")
        |> redirect(to: ~p"/users/log-in")

      {:error, :unauthorized} ->
        conn
        |> put_flash(:error, "Access denied.")
        |> redirect(to: ~p"/")
    end
  end

  # ── Private ─────────────────────────────────────────────────────────────────

  defp build_sales_csv(summary, orders_by_day, range) do
    header_row = "Sales Report - #{range_label(range)}\n"
    summary_header = "Metric,Value\n"

    summary_rows = [
      "Total Revenue,#{Analytics.format_money(summary.total_revenue)}",
      "Total Orders,#{summary.order_count}",
      "Avg Order Value,#{Analytics.format_money(summary.avg_order_value)}",
      "Total Tips,#{Analytics.format_money(summary.total_tips)}"
    ]

    daily_header = "\nDate,Orders\n"

    daily_rows =
      Enum.map(orders_by_day, fn row ->
        "#{format_date(row.date)},#{row.count}"
      end)

    [
      header_row,
      summary_header,
      Enum.join(summary_rows, "\n"),
      daily_header,
      Enum.join(daily_rows, "\n")
    ]
    |> Enum.join("")
  end

  defp parse_range(nil), do: :today

  defp parse_range(str) when str in @valid_ranges do
    String.to_existing_atom(str)
  end

  defp parse_range(_), do: :today

  defp range_label("today"), do: "Today"
  defp range_label("yesterday"), do: "Yesterday"
  defp range_label("this_week"), do: "This Week"
  defp range_label("this_month"), do: "This Month"
  defp range_label("last_30_days"), do: "Last 30 Days"
  defp range_label(a) when is_atom(a), do: range_label(Atom.to_string(a))
  defp range_label(_), do: "Custom"

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = d), do: Date.to_iso8601(d)
  defp format_date(str) when is_binary(str), do: str

  defp get_current_user(conn) do
    case conn.assigns[:current_scope] do
      %{user: user} when not is_nil(user) -> {:ok, user}
      _ -> {:error, :unauthenticated}
    end
  end

  defp authorize(user) do
    if user.role in ~w(owner staff) do
      case user.restaurant_id && Tenancy.get_restaurant(user.restaurant_id) do
        nil -> {:error, :unauthorized}
        restaurant -> {:ok, restaurant}
      end
    else
      {:error, :unauthorized}
    end
  end
end
