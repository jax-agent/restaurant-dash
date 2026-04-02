defmodule RestaurantDashWeb.KitchenLive do
  @moduledoc """
  Kitchen Display System (KDS) — full-screen LiveView for kitchen monitors.

  Features:
  - Shows orders grouped by status: New → Accepted → Preparing → Ready
  - Real-time updates via PubSub
  - Color-coded urgency (green/yellow/red based on time)
  - Large tap targets for touch screens
  - Audio alerts via JS hook
  - Keyboard shortcuts: Enter = accept, Space = mark ready, Esc = reject
  - Order detail modal on card click
  """
  use RestaurantDashWeb, :live_view

  on_mount {RestaurantDashWeb.UserAuth, :mount_current_user}

  alias RestaurantDash.{Kitchen, Orders, Drivers, Tenancy}
  alias RestaurantDash.Orders.Order

  @kds_statuses Order.kds_statuses()
  @tick_interval_ms 10_000

  # ─── Mount ───────────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    current_user = get_current_user(socket)

    case authorize(current_user) do
      {:ok, restaurant} ->
        if connected?(socket) do
          Orders.subscribe(restaurant.id)
          # Tick every 10s to update timers
          :timer.send_interval(@tick_interval_ms, self(), :tick)
        end

        socket =
          socket
          |> assign(:current_user, current_user)
          |> assign(:restaurant, restaurant)
          |> assign(:kds_statuses, @kds_statuses)
          |> assign(:muted, false)
          |> assign(:selected_order, nil)
          |> assign(:show_modal, false)
          |> assign(:audio_ready, false)
          |> assign(:now, DateTime.utc_now())
          |> assign(:available_drivers, Drivers.list_available_drivers())
          |> load_orders(restaurant.id)

        {:ok, socket}

      {:error, :unauthenticated} ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in to access the kitchen display.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "You don't have permission to access the kitchen display.")
         |> redirect(to: ~p"/")}
    end
  end

  # ─── Events ──────────────────────────────────────────────────────────────

  @impl true
  def handle_event("accept_order", %{"id" => id}, socket) do
    with {:ok, order} <- fetch_restaurant_order(id, socket),
         {:ok, _updated} <- Kitchen.accept_order(order) do
      {:noreply, reload_orders(socket)}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, to_string(reason))}
    end
  end

  @impl true
  def handle_event("start_preparing", %{"id" => id}, socket) do
    with {:ok, order} <- fetch_restaurant_order(id, socket),
         {:ok, _updated} <- Kitchen.start_preparing(order) do
      {:noreply, reload_orders(socket)}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, to_string(reason))}
    end
  end

  @impl true
  def handle_event("mark_ready", %{"id" => id}, socket) do
    with {:ok, order} <- fetch_restaurant_order(id, socket),
         {:ok, _updated} <- Kitchen.mark_ready(order) do
      {:noreply, reload_orders(socket)}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, to_string(reason))}
    end
  end

  @impl true
  def handle_event("reject_order", %{"id" => id}, socket) do
    with {:ok, order} <- fetch_restaurant_order(id, socket),
         {:ok, _updated} <- Kitchen.reject_order(order) do
      {:noreply, socket |> reload_orders() |> assign(:show_modal, false)}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, to_string(reason))}
    end
  end

  @impl true
  def handle_event("show_order_detail", %{"id" => id}, socket) do
    order = find_order_in_groups(id, socket.assigns.order_groups)

    if order do
      {:noreply, socket |> assign(:selected_order, order) |> assign(:show_modal, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, socket |> assign(:show_modal, false) |> assign(:selected_order, nil)}
  end

  @impl true
  def handle_event("toggle_mute", _, socket) do
    {:noreply, update(socket, :muted, &(!&1))}
  end

  @impl true
  def handle_event("audio_ready", _, socket) do
    {:noreply, assign(socket, :audio_ready, true)}
  end

  @impl true
  def handle_event("print_order", %{"id" => _id}, socket) do
    # Triggers browser print dialog via JS hook
    {:noreply, push_event(socket, "print_order", %{})}
  end

  @impl true
  def handle_event("assign_driver", %{"order_id" => order_id, "driver_id" => driver_id}, socket) do
    with {:ok, order} <- fetch_restaurant_order(order_id, socket),
         driver_id_int <- String.to_integer(driver_id),
         {:ok, _order} <- Orders.assign_driver(order, driver_id_int),
         driver_profile <- Drivers.get_profile_by_user_id(driver_id_int),
         {:ok, _} <-
           if(driver_profile,
             do: Drivers.set_status(driver_profile, "on_delivery"),
             else: {:ok, nil}
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Driver assigned!")
       |> assign(:available_drivers, Drivers.list_available_drivers())
       |> reload_orders()}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, to_string(reason))}
    end
  end

  # ─── PubSub ──────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:order_created, order}, socket) do
    if order.restaurant_id == socket.assigns.restaurant.id do
      socket =
        socket
        |> reload_orders()
        |> push_event("new_order_alert", %{muted: socket.assigns.muted})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:order_updated, order}, socket) do
    if order.restaurant_id == socket.assigns.restaurant.id do
      socket =
        socket
        |> reload_orders()
        |> maybe_update_selected_order(order)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:order_position_updated, _order}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  # ─── Render ──────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="kds-root"
      id="kds-root"
      phx-hook="KdsKeyboard"
      data-restaurant-id={@restaurant.id}
    >
      <%!-- KDS Header --%>
      <header class="kds-header">
        <div class="kds-header-left">
          <div
            class="kds-logo"
            style={"background-color: #{@restaurant.primary_color}"}
          >
            {String.first(@restaurant.name)}
          </div>
          <div>
            <h1 class="kds-restaurant-name">{@restaurant.name}</h1>
            <p class="kds-subtitle">Kitchen Display System</p>
          </div>
        </div>

        <div class="kds-header-right">
          <span class="kds-time">{format_time(@now)}</span>

          <button
            phx-click="toggle_mute"
            class={"kds-mute-btn #{if @muted, do: "muted", else: ""}"}
            title={if @muted, do: "Unmute alerts", else: "Mute alerts"}
          >
            {if @muted, do: "🔇", else: "🔔"}
          </button>

          <a href="/dashboard" class="kds-nav-link">← Dashboard</a>
        </div>
      </header>

      <%!-- Audio hook element --%>
      <div
        id="kds-audio"
        phx-hook="KdsAudio"
        data-muted={to_string(@muted)}
        style="display: none;"
      />

      <%!-- KDS Board — 4 columns --%>
      <main class="kds-board" id="kds-board">
        <%= for status <- @kds_statuses do %>
          <section class={"kds-column kds-column--#{status}"} id={"kds-col-#{status}"}>
            <div class="kds-column-header">
              <span class={"kds-status-badge kds-status-badge--#{status}"}>
                {humanize_status(status)}
              </span>
              <span class="kds-col-count">
                {length(Map.get(@order_groups, status, []))}
              </span>
            </div>

            <div class="kds-cards" id={"kds-cards-#{status}"}>
              <%= for order <- Map.get(@order_groups, status, []) do %>
                <div
                  class={"kds-card kds-card--#{urgency_class(order, @now)} #{if priority?(order), do: "kds-card--priority", else: ""}"}
                  id={"kds-card-#{order.id}"}
                  phx-click="show_order_detail"
                  phx-value-id={order.id}
                >
                  <%!-- Card header --%>
                  <div class="kds-card-header">
                    <span class="kds-order-number">##{order.id}</span>
                    <span class={"kds-timer kds-timer--#{urgency_class(order, @now)}"}>
                      {format_elapsed(order, @now)}
                    </span>
                    <%= if priority?(order) do %>
                      <span class="kds-priority-badge" title="Priority order">⚡</span>
                    <% end %>
                  </div>

                  <%!-- Customer name --%>
                  <div class="kds-customer-name">{order.customer_name}</div>

                  <%!-- Items --%>
                  <div class="kds-items">
                    <%= for item <- order.order_items do %>
                      <div class="kds-item">
                        <span class="kds-item-qty">{item.quantity}×</span>
                        <span class="kds-item-name">{item.name}</span>
                        <%= if item.modifiers_json && item.modifiers_json != "[]" do %>
                          <div class="kds-item-mods">
                            <%= for mod <- parse_modifiers(item.modifiers_json) do %>
                              <span class="kds-mod">{mod}</span>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                    <%!-- Legacy items array fallback --%>
                    <%= if Enum.empty?(order.order_items) do %>
                      <%= for item <- order.items do %>
                        <div class="kds-item">
                          <span class="kds-item-name">{item}</span>
                        </div>
                      <% end %>
                    <% end %>
                  </div>

                  <%!-- Estimated ready time --%>
                  <%= if order.estimated_prep_minutes do %>
                    <div class="kds-eta">
                      ETA: {format_eta(order)}
                    </div>
                  <% end %>

                  <%!-- Action buttons --%>
                  <div class="kds-actions" phx-click-away="">
                    <%= if order.status == "new" do %>
                      <button
                        class="kds-btn kds-btn--accept"
                        phx-click="accept_order"
                        phx-value-id={order.id}
                      >
                        ✓ Accept
                      </button>
                      <button
                        class="kds-btn kds-btn--reject"
                        phx-click="reject_order"
                        phx-value-id={order.id}
                      >
                        ✕ Reject
                      </button>
                    <% end %>

                    <%= if order.status == "accepted" do %>
                      <button
                        class="kds-btn kds-btn--prepare"
                        phx-click="start_preparing"
                        phx-value-id={order.id}
                      >
                        👨‍🍳 Start Prep
                      </button>
                      <button
                        class="kds-btn kds-btn--reject"
                        phx-click="reject_order"
                        phx-value-id={order.id}
                      >
                        ✕ Cancel
                      </button>
                    <% end %>

                    <%= if order.status == "preparing" do %>
                      <button
                        class="kds-btn kds-btn--ready"
                        phx-click="mark_ready"
                        phx-value-id={order.id}
                      >
                        🍽️ Mark Ready
                      </button>
                      <button
                        class="kds-btn kds-btn--reject"
                        phx-click="reject_order"
                        phx-value-id={order.id}
                      >
                        ✕ Cancel
                      </button>
                    <% end %>

                    <%= if order.status == "ready" do %>
                      <div class="kds-ready-badge">Ready for Pickup</div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%= if Enum.empty?(Map.get(@order_groups, status, [])) do %>
                <div class="kds-empty">No orders</div>
              <% end %>
            </div>
          </section>
        <% end %>
      </main>

      <%!-- Order Detail Modal --%>
      <%= if @show_modal and @selected_order do %>
        <div class="kds-modal-overlay" phx-click="close_modal">
          <div class="kds-modal" phx-click-away="close_modal" id="kds-modal">
            <div class="kds-modal-header">
              <h2 class="kds-modal-title">Order #{@selected_order.id}</h2>
              <button class="kds-modal-close" phx-click="close_modal">✕</button>
            </div>

            <%!-- Customer info --%>
            <div class="kds-modal-section">
              <h3 class="kds-modal-section-title">Customer</h3>
              <div class="kds-modal-customer">
                <div><strong>{@selected_order.customer_name}</strong></div>
                <%= if @selected_order.customer_phone do %>
                  <div>📞 {@selected_order.customer_phone}</div>
                <% end %>
                <%= if @selected_order.phone do %>
                  <div>📞 {@selected_order.phone}</div>
                <% end %>
                <%= if @selected_order.delivery_address do %>
                  <div>📍 {@selected_order.delivery_address}</div>
                <% end %>
              </div>
            </div>

            <%!-- Items --%>
            <div class="kds-modal-section">
              <h3 class="kds-modal-section-title">Items</h3>
              <div class="kds-modal-items">
                <%= for item <- @selected_order.order_items do %>
                  <div class="kds-modal-item">
                    <div class="kds-modal-item-main">
                      <span class="kds-modal-item-qty">{item.quantity}×</span>
                      <span class="kds-modal-item-name">{item.name}</span>
                      <span class="kds-modal-item-price">
                        {format_money(item.line_total)}
                      </span>
                    </div>
                    <%= if item.modifiers_json && item.modifiers_json != "[]" do %>
                      <div class="kds-modal-item-mods">
                        <%= for mod <- parse_modifiers(item.modifiers_json) do %>
                          <span>+ {mod}</span>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% end %>
                <%!-- Legacy items --%>
                <%= if Enum.empty?(@selected_order.order_items) do %>
                  <%= for item <- @selected_order.items do %>
                    <div class="kds-modal-item">
                      <span class="kds-modal-item-name">{item}</span>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>

            <%!-- Order timeline --%>
            <div class="kds-modal-section">
              <h3 class="kds-modal-section-title">Timeline</h3>
              <div class="kds-timeline">
                <div class="kds-timeline-item">
                  <span class="kds-timeline-dot kds-timeline-dot--done">●</span>
                  <span>Placed at {format_datetime(@selected_order.inserted_at)}</span>
                </div>
                <%= if @selected_order.accepted_at do %>
                  <div class="kds-timeline-item">
                    <span class="kds-timeline-dot kds-timeline-dot--done">●</span>
                    <span>Accepted at {format_datetime(@selected_order.accepted_at)}</span>
                  </div>
                <% end %>
                <%= if @selected_order.preparing_at do %>
                  <div class="kds-timeline-item">
                    <span class="kds-timeline-dot kds-timeline-dot--done">●</span>
                    <span>Prep started at {format_datetime(@selected_order.preparing_at)}</span>
                  </div>
                <% end %>
                <%= if @selected_order.ready_at do %>
                  <div class="kds-timeline-item">
                    <span class="kds-timeline-dot kds-timeline-dot--done">●</span>
                    <span>Ready at {format_datetime(@selected_order.ready_at)}</span>
                  </div>
                <% end %>
              </div>
            </div>

            <%!-- Action buttons --%>
            <div class="kds-modal-actions">
              <%= if @selected_order.status == "new" do %>
                <button
                  class="kds-btn kds-btn--accept kds-btn--lg"
                  phx-click="accept_order"
                  phx-value-id={@selected_order.id}
                >
                  ✓ Accept Order
                </button>
              <% end %>

              <%= if @selected_order.status == "accepted" do %>
                <button
                  class="kds-btn kds-btn--prepare kds-btn--lg"
                  phx-click="start_preparing"
                  phx-value-id={@selected_order.id}
                >
                  👨‍🍳 Start Preparing
                </button>
              <% end %>

              <%= if @selected_order.status == "preparing" do %>
                <button
                  class="kds-btn kds-btn--ready kds-btn--lg"
                  phx-click="mark_ready"
                  phx-value-id={@selected_order.id}
                >
                  🍽️ Mark Ready
                </button>
              <% end %>

              <%= if @selected_order.status in ~w(new accepted preparing) do %>
                <button
                  class="kds-btn kds-btn--reject kds-btn--lg"
                  phx-click="reject_order"
                  phx-value-id={@selected_order.id}
                >
                  ✕ Cancel Order
                </button>
              <% end %>

              <button
                class="kds-btn kds-btn--print"
                phx-click="print_order"
                phx-value-id={@selected_order.id}
              >
                🖨️ Print
              </button>

              <button class="kds-btn kds-btn--secondary" phx-click="close_modal">
                Close
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>

    <style>
      /* ── KDS CSS ─────────────────────────────────────────────────── */
      .kds-root {
        display: flex;
        flex-direction: column;
        height: 100vh;
        background: #0f172a;
        color: #f1f5f9;
        font-family: system-ui, -apple-system, sans-serif;
        overflow: hidden;
      }

      /* Header */
      .kds-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 12px 20px;
        background: #1e293b;
        border-bottom: 1px solid #334155;
        flex-shrink: 0;
      }
      .kds-header-left { display: flex; align-items: center; gap: 12px; }
      .kds-header-right { display: flex; align-items: center; gap: 16px; }
      .kds-logo {
        width: 40px; height: 40px; border-radius: 8px;
        display: flex; align-items: center; justify-content: center;
        font-weight: bold; font-size: 18px; color: #fff;
      }
      .kds-restaurant-name { font-size: 18px; font-weight: 700; margin: 0; }
      .kds-subtitle { font-size: 12px; color: #94a3b8; margin: 0; }
      .kds-time { font-size: 20px; font-weight: 600; font-variant-numeric: tabular-nums; }
      .kds-mute-btn {
        background: #334155; border: none; border-radius: 8px;
        padding: 8px 12px; font-size: 20px; cursor: pointer;
        color: #f1f5f9; transition: background 0.2s;
      }
      .kds-mute-btn.muted { background: #7f1d1d; }
      .kds-nav-link { color: #94a3b8; text-decoration: none; font-size: 14px; }
      .kds-nav-link:hover { color: #f1f5f9; }

      /* Board */
      .kds-board {
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        gap: 12px;
        padding: 12px;
        flex: 1;
        overflow: hidden;
        min-height: 0;
      }

      /* Columns */
      .kds-column {
        background: #1e293b;
        border-radius: 12px;
        display: flex;
        flex-direction: column;
        overflow: hidden;
        border: 1px solid #334155;
      }
      .kds-column-header {
        padding: 12px 16px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        border-bottom: 1px solid #334155;
        flex-shrink: 0;
      }
      .kds-col-count {
        background: #334155;
        border-radius: 99px;
        padding: 2px 10px;
        font-size: 14px;
        font-weight: 700;
      }
      .kds-cards {
        flex: 1;
        overflow-y: auto;
        padding: 8px;
        display: flex;
        flex-direction: column;
        gap: 8px;
      }
      .kds-empty {
        text-align: center;
        padding: 40px 0;
        color: #475569;
        font-size: 14px;
      }

      /* Status badges */
      .kds-status-badge {
        font-size: 14px;
        font-weight: 700;
        padding: 4px 12px;
        border-radius: 99px;
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .kds-status-badge--new { background: #1e3a5f; color: #93c5fd; }
      .kds-status-badge--accepted { background: #3b1f6e; color: #c4b5fd; }
      .kds-status-badge--preparing { background: #4a2500; color: #fcd34d; }
      .kds-status-badge--ready { background: #14532d; color: #86efac; }

      /* Cards */
      .kds-card {
        background: #0f172a;
        border-radius: 10px;
        padding: 14px;
        cursor: pointer;
        border: 2px solid #334155;
        transition: border-color 0.2s, transform 0.1s;
        user-select: none;
      }
      .kds-card:active { transform: scale(0.98); }
      .kds-card--green { border-left: 4px solid #22c55e; }
      .kds-card--yellow { border-left: 4px solid #eab308; }
      .kds-card--red { border-left: 4px solid #ef4444; }
      .kds-card--priority { box-shadow: 0 0 0 2px #f59e0b; }

      .kds-card-header {
        display: flex;
        align-items: center;
        gap: 8px;
        margin-bottom: 6px;
      }
      .kds-order-number { font-size: 16px; font-weight: 700; color: #e2e8f0; }
      .kds-timer {
        font-size: 13px;
        font-weight: 600;
        padding: 2px 8px;
        border-radius: 99px;
        font-variant-numeric: tabular-nums;
        margin-left: auto;
      }
      .kds-timer--green { background: #14532d; color: #86efac; }
      .kds-timer--yellow { background: #422006; color: #fcd34d; }
      .kds-timer--red { background: #450a0a; color: #fca5a5; animation: pulse 1.5s infinite; }
      .kds-priority-badge { font-size: 14px; }
      .kds-customer-name { font-size: 15px; font-weight: 600; margin-bottom: 8px; color: #cbd5e1; }

      /* Items */
      .kds-items { margin-bottom: 8px; }
      .kds-item { font-size: 14px; padding: 2px 0; }
      .kds-item-qty { font-weight: 700; color: #94a3b8; margin-right: 4px; }
      .kds-item-name { color: #e2e8f0; }
      .kds-item-mods { margin-left: 20px; }
      .kds-mod {
        font-size: 12px;
        color: #64748b;
        background: #1e293b;
        border-radius: 4px;
        padding: 1px 6px;
        margin-right: 4px;
      }
      .kds-eta { font-size: 12px; color: #64748b; margin-bottom: 8px; }

      /* Action buttons */
      .kds-actions { display: flex; gap: 6px; flex-wrap: wrap; }
      .kds-btn {
        padding: 8px 14px;
        border: none;
        border-radius: 8px;
        font-size: 14px;
        font-weight: 600;
        cursor: pointer;
        min-height: 44px;
        transition: opacity 0.2s;
      }
      .kds-btn:active { opacity: 0.8; }
      .kds-btn--accept { background: #166534; color: #bbf7d0; }
      .kds-btn--prepare { background: #92400e; color: #fde68a; }
      .kds-btn--ready { background: #1e40af; color: #bfdbfe; }
      .kds-btn--reject { background: #7f1d1d; color: #fecaca; }
      .kds-btn--print { background: #334155; color: #e2e8f0; }
      .kds-btn--secondary { background: #334155; color: #94a3b8; }
      .kds-btn--lg { padding: 12px 20px; font-size: 16px; flex: 1; }
      .kds-ready-badge {
        background: #14532d;
        color: #86efac;
        padding: 6px 12px;
        border-radius: 8px;
        font-size: 13px;
        font-weight: 600;
      }

      /* Modal */
      .kds-modal-overlay {
        position: fixed; inset: 0;
        background: rgba(0,0,0,0.7);
        display: flex; align-items: center; justify-content: center;
        z-index: 100;
      }
      .kds-modal {
        background: #1e293b;
        border-radius: 16px;
        width: min(600px, 95vw);
        max-height: 85vh;
        overflow-y: auto;
        padding: 24px;
        border: 1px solid #334155;
      }
      .kds-modal-header {
        display: flex; align-items: center; justify-content: space-between;
        margin-bottom: 20px;
      }
      .kds-modal-title { font-size: 22px; font-weight: 700; margin: 0; }
      .kds-modal-close {
        background: #334155; border: none; color: #94a3b8;
        width: 36px; height: 36px; border-radius: 8px;
        cursor: pointer; font-size: 16px;
      }
      .kds-modal-section { margin-bottom: 20px; }
      .kds-modal-section-title {
        font-size: 13px; font-weight: 600; color: #64748b;
        text-transform: uppercase; letter-spacing: 0.05em;
        margin-bottom: 8px;
      }
      .kds-modal-customer { font-size: 15px; line-height: 1.8; }
      .kds-modal-items { display: flex; flex-direction: column; gap: 8px; }
      .kds-modal-item {
        background: #0f172a;
        border-radius: 8px;
        padding: 10px 14px;
      }
      .kds-modal-item-main { display: flex; align-items: center; gap: 8px; }
      .kds-modal-item-qty { font-weight: 700; color: #94a3b8; min-width: 24px; }
      .kds-modal-item-name { flex: 1; color: #e2e8f0; }
      .kds-modal-item-price { color: #94a3b8; font-size: 14px; }
      .kds-modal-item-mods { margin-left: 30px; margin-top: 4px; font-size: 13px; color: #64748b; }
      .kds-timeline { display: flex; flex-direction: column; gap: 8px; }
      .kds-timeline-item { display: flex; align-items: center; gap: 10px; font-size: 14px; }
      .kds-timeline-dot--done { color: #22c55e; }
      .kds-modal-actions { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 8px; }

      @keyframes pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.6; }
      }

      /* Responsive: collapse to 2 cols on tablets */
      @media (max-width: 900px) {
        .kds-board { grid-template-columns: repeat(2, 1fr); }
      }
      @media (max-width: 600px) {
        .kds-board { grid-template-columns: 1fr; }
      }
    </style>
    """
  end

  # ─── Private ─────────────────────────────────────────────────────────────

  defp load_orders(socket, restaurant_id) do
    groups = Kitchen.list_kds_orders_grouped(restaurant_id)
    assign(socket, :order_groups, groups)
  end

  defp reload_orders(socket) do
    load_orders(socket, socket.assigns.restaurant.id)
  end

  defp fetch_restaurant_order(id, socket) do
    restaurant_id = socket.assigns.restaurant.id

    case Orders.get_order(String.to_integer(id)) do
      nil -> {:error, "Order not found"}
      %{restaurant_id: ^restaurant_id} = order -> {:ok, order}
      _ -> {:error, "Order not found"}
    end
  end

  defp find_order_in_groups(id, groups) do
    id = String.to_integer(id)

    Enum.reduce_while(groups, nil, fn {_status, orders}, _acc ->
      case Enum.find(orders, &(&1.id == id)) do
        nil -> {:cont, nil}
        order -> {:halt, order}
      end
    end)
  end

  defp maybe_update_selected_order(socket, updated_order) do
    if socket.assigns.selected_order && socket.assigns.selected_order.id == updated_order.id do
      # Reload selected order with full preloads
      case Orders.get_order_with_items(updated_order.id) do
        nil ->
          socket |> assign(:selected_order, nil) |> assign(:show_modal, false)

        order ->
          assign(socket, :selected_order, order)
      end
    else
      socket
    end
  end

  defp get_current_user(socket) do
    case socket.assigns[:current_scope] do
      %{user: user} when not is_nil(user) -> user
      _ -> nil
    end
  end

  defp authorize(nil), do: {:error, :unauthenticated}

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

  # ─── Formatting helpers ───────────────────────────────────────────────────

  defp humanize_status("new"), do: "New Orders"
  defp humanize_status("accepted"), do: "Accepted"
  defp humanize_status("preparing"), do: "Preparing"
  defp humanize_status("ready"), do: "Ready"
  defp humanize_status(s), do: s

  defp urgency_class(order, now) do
    seconds = DateTime.diff(now, order.inserted_at, :second)
    minutes = div(seconds, 60)

    cond do
      minutes >= 20 -> "red"
      minutes >= 10 -> "yellow"
      true -> "green"
    end
  end

  defp priority?(order), do: Kitchen.priority_order?(order)

  defp format_elapsed(order, now) do
    seconds = DateTime.diff(now, order.inserted_at, :second)
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)

    "#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_time(dt) do
    hour = dt.hour |> Integer.to_string() |> String.pad_leading(2, "0")
    min = dt.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{hour}:#{min}"
  end

  defp format_datetime(nil), do: "—"

  defp format_datetime(dt) do
    "#{String.pad_leading(Integer.to_string(dt.hour), 2, "0")}:#{String.pad_leading(Integer.to_string(dt.minute), 2, "0")}:#{String.pad_leading(Integer.to_string(dt.second), 2, "0")}"
  end

  defp format_eta(%{estimated_prep_minutes: mins, inserted_at: inserted_at}) do
    ready_at = DateTime.add(inserted_at, mins * 60, :second)
    format_datetime(ready_at)
  end

  defp format_money(nil), do: "$0.00"

  defp format_money(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    rem_cents = rem(cents, 100)
    "$#{dollars}.#{String.pad_leading(Integer.to_string(rem_cents), 2, "0")}"
  end

  defp parse_modifiers(json) do
    case Jason.decode(json) do
      {:ok, mods} when is_list(mods) ->
        Enum.map(mods, fn
          %{"name" => name} -> name
          name when is_binary(name) -> name
          _ -> ""
        end)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end
end
