defmodule RestaurantDashWeb.DashboardLive do
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.{Branding, Orders}
  alias RestaurantDash.Orders.Order
  alias RestaurantDash.Workers.OrderLifecycleWorker

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
      |> assign(:show_new_order_modal, false)
      |> assign(:form, to_form(Orders.change_order(%Order{})))

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    live_action = socket.assigns.live_action

    socket =
      case live_action do
        :new -> assign(socket, :show_new_order_modal, true)
        _ -> assign(socket, :show_new_order_modal, false)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("new_order", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/orders/new")}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_new_order_modal, false)
     |> assign(:form, to_form(Orders.change_order(%Order{})))
     |> push_patch(to: ~p"/")}
  end

  @impl true
  def handle_event("validate", %{"order" => order_params}, socket) do
    changeset =
      %Order{}
      |> Orders.change_order(normalize_params(order_params))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save_order", %{"order" => order_params}, socket) do
    params = normalize_params(order_params)

    case Orders.create_order(params) do
      {:ok, order} ->
        # Schedule the lifecycle pipeline
        OrderLifecycleWorker.schedule_for(order)

        socket =
          socket
          |> put_flash(:info, "Order created for #{order.customer_name}! 🎉")
          |> assign(:show_new_order_modal, false)
          |> assign(:form, to_form(Orders.change_order(%Order{})))
          |> push_patch(to: ~p"/")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
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
    # Push updated position to the map JS hook
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

  defp normalize_params(params), do: assign_random_sf_coords(params)

  # Assign random SF-area coordinates for demo (no real geocoding)
  defp assign_random_sf_coords(params) do
    {lat, lng} = random_sf_coords()
    params |> Map.put("lat", lat) |> Map.put("lng", lng)
  end

  defp random_sf_coords do
    # SF bounding box: roughly 37.70-37.81 lat, -122.52 to -122.37 lng
    lat = 37.70 + :rand.uniform() * 0.11
    lng = -122.52 + :rand.uniform() * 0.15
    {Float.round(lat, 6), Float.round(lng, 6)}
  end

  # ─── Template helpers (imported into template scope) ──────────────────────

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
