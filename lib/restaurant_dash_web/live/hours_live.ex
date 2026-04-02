defmodule RestaurantDashWeb.HoursLive do
  @moduledoc "Owner dashboard for managing operating hours and holiday closures."
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.Hours

  @days [
    {0, "Sunday"},
    {1, "Monday"},
    {2, "Tuesday"},
    {3, "Wednesday"},
    {4, "Thursday"},
    {5, "Friday"},
    {6, "Saturday"}
  ]

  @impl true
  def mount(_params, session, socket) do
    restaurant = session["current_restaurant"]

    if is_nil(restaurant) do
      {:ok, push_navigate(socket, to: "/")}
    else
      hours = Hours.list_hours(restaurant.id)
      hours_map = Map.new(hours, &{&1.day_of_week, &1})

      closures = Hours.list_upcoming_closures(restaurant.id)

      form_data =
        Enum.map(@days, fn {dow, _name} ->
          h = Map.get(hours_map, dow)

          {dow,
           %{
             "open_time" => if(h, do: time_to_string(h.open_time), else: "09:00"),
             "close_time" => if(h, do: time_to_string(h.close_time), else: "21:00"),
             "is_closed" => if(h, do: h.is_closed, else: false)
           }}
        end)
        |> Map.new()

      {:ok,
       socket
       |> assign(:restaurant, restaurant)
       |> assign(:days, @days)
       |> assign(:hours_map, hours_map)
       |> assign(:form_data, form_data)
       |> assign(:closures, closures)
       |> assign(:closure_date, "")
       |> assign(:closure_reason, "")
       |> assign(:save_status, nil)}
    end
  end

  @impl true
  def handle_event("toggle-closed", %{"day" => day_str}, socket) do
    dow = String.to_integer(day_str)

    form_data =
      Map.update!(socket.assigns.form_data, dow, fn d ->
        Map.put(d, "is_closed", !d["is_closed"])
      end)

    {:noreply, assign(socket, form_data: form_data)}
  end

  @impl true
  def handle_event("update-time", %{"day" => day_str, "field" => field, "value" => value}, socket) do
    dow = String.to_integer(day_str)

    form_data =
      Map.update!(socket.assigns.form_data, dow, fn d ->
        Map.put(d, field, value)
      end)

    {:noreply, assign(socket, form_data: form_data)}
  end

  @impl true
  def handle_event("save-hours", _, socket) do
    restaurant = socket.assigns.restaurant

    results =
      Enum.map(socket.assigns.form_data, fn {dow, data} ->
        open_time = parse_time(data["open_time"])
        close_time = parse_time(data["close_time"])

        Hours.upsert_hours(%{
          restaurant_id: restaurant.id,
          day_of_week: dow,
          open_time: open_time || ~T[09:00:00],
          close_time: close_time || ~T[21:00:00],
          is_closed: data["is_closed"] || false
        })
      end)

    if Enum.all?(results, fn r -> match?({:ok, _}, r) end) do
      hours = Hours.list_hours(restaurant.id)
      hours_map = Map.new(hours, &{&1.day_of_week, &1})
      {:noreply, assign(socket, hours_map: hours_map, save_status: :saved)}
    else
      {:noreply, assign(socket, save_status: :error)}
    end
  end

  @impl true
  def handle_event("update-closure-field", %{"field" => "date", "value" => v}, socket) do
    {:noreply, assign(socket, closure_date: v)}
  end

  def handle_event("update-closure-field", %{"field" => "reason", "value" => v}, socket) do
    {:noreply, assign(socket, closure_reason: v)}
  end

  @impl true
  def handle_event("add-closure", _, socket) do
    restaurant = socket.assigns.restaurant

    case Date.from_iso8601(socket.assigns.closure_date) do
      {:ok, date} ->
        attrs = %{
          restaurant_id: restaurant.id,
          date: date,
          reason:
            if(socket.assigns.closure_reason == "", do: nil, else: socket.assigns.closure_reason)
        }

        case Hours.create_closure(attrs) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:closures, Hours.list_upcoming_closures(restaurant.id))
             |> assign(:closure_date, "")
             |> assign(:closure_reason, "")}

          _ ->
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove-closure", %{"id" => id}, socket) do
    from = Enum.find(socket.assigns.closures, &(&1.id == String.to_integer(id)))
    if from, do: Hours.delete_closure(from)

    {:noreply,
     assign(socket, closures: Hours.list_upcoming_closures(socket.assigns.restaurant.id))}
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  defp time_to_string(%Time{hour: h, minute: m}) do
    "#{String.pad_leading(Integer.to_string(h), 2, "0")}:#{String.pad_leading(Integer.to_string(m), 2, "0")}"
  end

  defp parse_time(nil), do: nil
  defp parse_time(""), do: nil

  defp parse_time(str) do
    case Time.from_iso8601(str <> ":00") do
      {:ok, t} ->
        t

      _ ->
        case Time.from_iso8601(str) do
          {:ok, t} -> t
          _ -> nil
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6 space-y-8">
      <h1 class="text-2xl font-bold text-gray-900">Operating Hours</h1>

      <div class="bg-white border border-gray-200 rounded-xl p-6">
        <div class="space-y-3">
          <%= for {dow, day_name} <- @days do %>
            <% data = @form_data[dow] %>
            <div class="flex items-center gap-4">
              <div class="w-28 font-medium text-gray-700">{day_name}</div>
              <label class="flex items-center gap-2 text-sm text-gray-600">
                <input
                  type="checkbox"
                  checked={data["is_closed"]}
                  phx-click="toggle-closed"
                  phx-value-day={dow}
                  class="rounded"
                /> Closed
              </label>
              <%= if !data["is_closed"] do %>
                <input
                  type="time"
                  value={data["open_time"]}
                  phx-blur="update-time"
                  phx-value-day={dow}
                  phx-value-field="open_time"
                  class="border border-gray-300 rounded px-2 py-1 text-sm"
                />
                <span class="text-gray-400">to</span>
                <input
                  type="time"
                  value={data["close_time"]}
                  phx-blur="update-time"
                  phx-value-day={dow}
                  phx-value-field="close_time"
                  class="border border-gray-300 rounded px-2 py-1 text-sm"
                />
              <% else %>
                <span class="text-gray-400 text-sm italic">Closed all day</span>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="mt-4 flex items-center gap-3">
          <button
            phx-click="save-hours"
            class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700 font-medium"
          >
            Save Hours
          </button>
          <%= if @save_status == :saved do %>
            <span class="text-green-600 text-sm">✓ Saved!</span>
          <% end %>
          <%= if @save_status == :error do %>
            <span class="text-red-500 text-sm">Error saving hours</span>
          <% end %>
        </div>
      </div>

      <%!-- Holiday Closures --%>
      <div>
        <h2 class="text-lg font-semibold text-gray-800 mb-4">Holiday Closures</h2>

        <div class="bg-white border border-gray-200 rounded-xl p-4 mb-4">
          <div class="flex gap-3 items-end">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Date</label>
              <input
                type="date"
                value={@closure_date}
                phx-blur="update-closure-field"
                phx-value-field="date"
                class="border border-gray-300 rounded-lg px-3 py-2"
              />
            </div>
            <div class="flex-1">
              <label class="block text-sm font-medium text-gray-700 mb-1">Reason (optional)</label>
              <input
                type="text"
                value={@closure_reason}
                phx-blur="update-closure-field"
                phx-value-field="reason"
                placeholder="Holiday, private event..."
                class="w-full border border-gray-300 rounded-lg px-3 py-2"
              />
            </div>
            <button
              phx-click="add-closure"
              class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700 font-medium"
            >
              Add
            </button>
          </div>
        </div>

        <%= if Enum.empty?(@closures) do %>
          <div class="text-gray-500 text-sm">No upcoming closures.</div>
        <% else %>
          <div class="space-y-2">
            <%= for closure <- @closures do %>
              <div class="bg-white border border-gray-200 rounded-lg p-3 flex items-center justify-between">
                <div>
                  <span class="font-medium text-gray-800">{to_string(closure.date)}</span>
                  <%= if closure.reason do %>
                    <span class="text-gray-500 text-sm ml-2">— {closure.reason}</span>
                  <% end %>
                </div>
                <button
                  phx-click="remove-closure"
                  phx-value-id={closure.id}
                  class="text-red-500 hover:text-red-700 text-sm"
                >
                  Remove
                </button>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
