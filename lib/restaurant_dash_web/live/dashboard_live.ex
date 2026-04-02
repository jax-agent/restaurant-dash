defmodule RestaurantDashWeb.DashboardLive do
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.{Branding, Orders}
  alias RestaurantDash.Orders.Order

  @statuses Order.valid_statuses()

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Orders.subscribe()
    end

    orders = Orders.list_orders()

    socket =
      socket
      |> assign(:branding, branding())
      |> assign(:orders, group_by_status(orders))
      |> assign(:statuses, @statuses)
      |> assign(:status_counts, Orders.count_by_status())
      |> assign(:active_deliveries, filter_active(orders))

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_order", %{"id" => id}, socket) do
    order = Orders.get_order!(id)

    case Orders.delete_order(order) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Order for #{order.customer_name} deleted.")
         |> reload_orders()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete order.")}
    end
  end

  # ─── PubSub handlers ───────────────────────────────────────────────────────

  @impl true
  def handle_info({:order_created, _order}, socket) do
    {:noreply, reload_orders(socket)}
  end

  @impl true
  def handle_info({:order_updated, _order}, socket) do
    {:noreply, reload_orders(socket)}
  end

  @impl true
  def handle_info({:order_position_updated, order}, socket) do
    socket =
      push_event(socket, "update_marker", %{
        id: order.id,
        lat: order.lat,
        lng: order.lng
      })

    {:noreply, reload_orders(socket)}
  end

  # ─── Private ───────────────────────────────────────────────────────────────

  defp reload_orders(socket) do
    orders = Orders.list_orders()

    socket
    |> assign(:orders, group_by_status(orders))
    |> assign(:status_counts, Orders.count_by_status())
    |> assign(:active_deliveries, filter_active(orders))
  end

  defp group_by_status(orders) do
    base = Map.new(@statuses, &{&1, []})

    Enum.reduce(orders, base, fn order, acc ->
      Map.update(acc, order.status, [order], &(&1 ++ [order]))
    end)
  end

  defp filter_active(orders) do
    Enum.filter(orders, &(&1.status == "out_for_delivery" && &1.lat && &1.lng))
  end

  defp branding do
    %{
      restaurant_name: Branding.restaurant_name(),
      primary_color: Branding.primary_color(),
      logo_url: Branding.logo_url()
    }
  end

  defp humanize_status("new"), do: "New"
  defp humanize_status("preparing"), do: "Preparing"
  defp humanize_status("out_for_delivery"), do: "Out for Delivery"
  defp humanize_status("delivered"), do: "Delivered"
  defp humanize_status(s), do: s

  defp time_ago(nil), do: ""

  defp time_ago(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      true -> "#{div(diff, 3600)}h ago"
    end
  end

  defp order_map_data(order) do
    %{
      id: order.id,
      lat: order.lat,
      lng: order.lng,
      customer_name: order.customer_name,
      items: order.items,
      delivery_address: order.delivery_address
    }
  end
end
