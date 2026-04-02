defmodule RestaurantDashWeb.OrderFormLive do
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.{Branding, Orders}
  alias RestaurantDash.Orders.Order
  alias RestaurantDash.Workers.OrderLifecycleWorker

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:branding, branding())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :new ->
        changeset = Orders.change_order(%Order{})

        {:noreply,
         socket
         |> assign(:page_title, "New Order")
         |> assign(:order, %Order{})
         |> assign(:form, to_form(changeset))}

      :edit ->
        order = Orders.get_order!(params["id"])
        items_text = Enum.join(order.items, "\n")
        changeset = Orders.change_order(order, %{items_text: items_text})

        {:noreply,
         socket
         |> assign(:page_title, "Edit Order — #{order.customer_name}")
         |> assign(:order, order)
         |> assign(:form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("validate", %{"order" => order_params}, socket) do
    params = normalize_params(order_params)

    changeset =
      socket.assigns.order
      |> Orders.change_order(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save_order", %{"order" => order_params}, socket) do
    params = normalize_params(order_params)

    case socket.assigns.live_action do
      :new -> create_order(socket, params)
      :edit -> update_order(socket, params)
    end
  end

  defp create_order(socket, params) do
    case Orders.create_order(params) do
      {:ok, order} ->
        OrderLifecycleWorker.schedule_for(order)

        {:noreply,
         socket
         |> put_flash(:info, "Order created for #{order.customer_name}! 🎉")
         |> push_navigate(to: ~p"/")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp update_order(socket, params) do
    case Orders.update_order(socket.assigns.order, params) do
      {:ok, order} ->
        {:noreply,
         socket
         |> put_flash(:info, "Order for #{order.customer_name} updated! ✅")
         |> push_navigate(to: ~p"/")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp normalize_params(params) do
    {lat, lng} = random_sf_coords()

    params
    |> Map.put_new("lat", lat)
    |> Map.put_new("lng", lng)
  end

  defp random_sf_coords do
    lat = 37.70 + :rand.uniform() * 0.11
    lng = -122.52 + :rand.uniform() * 0.15
    {Float.round(lat, 6), Float.round(lng, 6)}
  end

  defp branding do
    %{
      restaurant_name: Branding.restaurant_name(),
      primary_color: Branding.primary_color(),
      logo_url: Branding.logo_url()
    }
  end
end
