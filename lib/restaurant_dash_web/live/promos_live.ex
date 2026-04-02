defmodule RestaurantDashWeb.PromosLive do
  @moduledoc "Owner dashboard for managing promo codes."
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.Promotions

  @impl true
  def mount(_params, session, socket) do
    restaurant = session["current_restaurant"]

    if is_nil(restaurant) do
      {:ok, push_navigate(socket, to: "/")}
    else
      {:ok,
       socket
       |> assign(:restaurant, restaurant)
       |> assign(:promos, Promotions.list_promo_codes(restaurant.id))
       |> assign(:show_form, false)
       |> assign(:editing, nil)
       |> assign(:form_errors, %{})
       |> assign(:form_data, default_form())}
    end
  end

  @impl true
  def handle_event("show-form", _, socket) do
    {:noreply,
     assign(socket, show_form: true, editing: nil, form_data: default_form(), form_errors: %{})}
  end

  @impl true
  def handle_event("hide-form", _, socket) do
    {:noreply, assign(socket, show_form: false, editing: nil)}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    promo = Promotions.get_promo_code!(String.to_integer(id))

    form_data = %{
      "code" => promo.code,
      "discount_type" => promo.discount_type,
      "discount_value" => to_string(promo.discount_value),
      "min_order" => if(promo.min_order, do: to_string(div(promo.min_order, 100)), else: ""),
      "max_uses" => if(promo.max_uses, do: to_string(promo.max_uses), else: ""),
      "expires_at" => format_datetime_for_input(promo.expires_at)
    }

    {:noreply,
     assign(socket, show_form: true, editing: promo, form_data: form_data, form_errors: %{})}
  end

  @impl true
  def handle_event("update-field", %{"field" => field, "value" => value}, socket) do
    form_data = Map.put(socket.assigns.form_data, field, value)
    {:noreply, assign(socket, form_data: form_data)}
  end

  @impl true
  def handle_event("save", _, socket) do
    restaurant = socket.assigns.restaurant
    form = socket.assigns.form_data

    attrs = build_attrs(form, restaurant.id)

    result =
      if socket.assigns.editing do
        Promotions.update_promo_code(socket.assigns.editing, attrs)
      else
        Promotions.create_promo_code(attrs)
      end

    case result do
      {:ok, _promo} ->
        {:noreply,
         socket
         |> assign(:promos, Promotions.list_promo_codes(restaurant.id))
         |> assign(:show_form, false)
         |> assign(:editing, nil)
         |> assign(:form_errors, %{})}

      {:error, changeset} ->
        errors = errors_from_changeset(changeset)
        {:noreply, assign(socket, form_errors: errors)}
    end
  end

  @impl true
  def handle_event("deactivate", %{"id" => id}, socket) do
    promo = Promotions.get_promo_code!(String.to_integer(id))
    {:ok, _} = Promotions.deactivate_promo_code(promo)

    {:noreply, assign(socket, promos: Promotions.list_promo_codes(socket.assigns.restaurant.id))}
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  defp default_form do
    %{
      "code" => "",
      "discount_type" => "percentage",
      "discount_value" => "",
      "min_order" => "",
      "max_uses" => "",
      "expires_at" => ""
    }
  end

  defp build_attrs(form, restaurant_id) do
    discount_value =
      case Integer.parse(form["discount_value"] || "") do
        {v, _} -> v
        :error -> nil
      end

    min_order =
      case Float.parse(form["min_order"] || "") do
        {v, _} -> round(v * 100)
        :error -> nil
      end

    max_uses =
      case Integer.parse(form["max_uses"] || "") do
        {v, _} -> v
        :error -> nil
      end

    expires_at =
      case form["expires_at"] do
        "" ->
          nil

        nil ->
          nil

        dt_str ->
          case NaiveDateTime.from_iso8601(dt_str <> ":00") do
            {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC")
            _ -> nil
          end
      end

    %{
      restaurant_id: restaurant_id,
      code: form["code"],
      discount_type: form["discount_type"],
      discount_value: discount_value,
      min_order: min_order,
      max_uses: max_uses,
      expires_at: expires_at,
      is_active: true
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
    |> Map.put(:restaurant_id, restaurant_id)
    |> Map.put(:is_active, true)
  end

  defp format_datetime_for_input(nil), do: ""

  defp format_datetime_for_input(%DateTime{} = dt) do
    NaiveDateTime.to_string(DateTime.to_naive(dt))
    |> String.slice(0, 16)
  end

  defp errors_from_changeset(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.map(fn {k, v} -> {to_string(k), Enum.join(v, ", ")} end)
    |> Map.new()
  end

  defp format_price(nil), do: "—"

  defp format_price(cents),
    do: "$#{div(cents, 100)}.#{String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-gray-900">Promo Codes</h1>
        <button
          phx-click="show-form"
          class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700 font-medium"
        >
          + New Promo Code
        </button>
      </div>

      <%= if @show_form do %>
        <div class="bg-white border border-gray-200 rounded-xl p-6 mb-6 shadow-sm">
          <h2 class="text-lg font-semibold mb-4">
            {if @editing, do: "Edit Promo Code", else: "New Promo Code"}
          </h2>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Code</label>
              <input
                type="text"
                value={@form_data["code"]}
                phx-blur="update-field"
                phx-value-field="code"
                placeholder="SAVE10"
                class="w-full border border-gray-300 rounded-lg px-3 py-2 uppercase"
              />
              <%= if @form_errors["code"] do %>
                <p class="text-red-500 text-sm mt-1">{@form_errors["code"]}</p>
              <% end %>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Discount Type</label>
              <select
                phx-change="update-field"
                phx-value-field="discount_type"
                name="discount_type"
                class="w-full border border-gray-300 rounded-lg px-3 py-2"
              >
                <option value="percentage" selected={@form_data["discount_type"] == "percentage"}>
                  Percentage (%)
                </option>
                <option value="fixed" selected={@form_data["discount_type"] == "fixed"}>
                  Fixed Amount ($)
                </option>
              </select>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">
                Discount Value ({if @form_data["discount_type"] == "percentage", do: "%", else: "$"})
              </label>
              <input
                type="number"
                value={@form_data["discount_value"]}
                phx-blur="update-field"
                phx-value-field="discount_value"
                min="1"
                class="w-full border border-gray-300 rounded-lg px-3 py-2"
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">
                Min Order ($, optional)
              </label>
              <input
                type="number"
                step="0.01"
                value={@form_data["min_order"]}
                phx-blur="update-field"
                phx-value-field="min_order"
                placeholder="0.00"
                class="w-full border border-gray-300 rounded-lg px-3 py-2"
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Max Uses (optional)</label>
              <input
                type="number"
                value={@form_data["max_uses"]}
                phx-blur="update-field"
                phx-value-field="max_uses"
                placeholder="unlimited"
                class="w-full border border-gray-300 rounded-lg px-3 py-2"
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">
                Expires At (optional)
              </label>
              <input
                type="datetime-local"
                value={@form_data["expires_at"]}
                phx-blur="update-field"
                phx-value-field="expires_at"
                class="w-full border border-gray-300 rounded-lg px-3 py-2"
              />
            </div>
          </div>

          <div class="flex gap-3 mt-4">
            <button
              phx-click="save"
              class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700 font-medium"
            >
              Save
            </button>
            <button
              phx-click="hide-form"
              class="border border-gray-300 text-gray-700 px-4 py-2 rounded-lg hover:bg-gray-50"
            >
              Cancel
            </button>
          </div>
        </div>
      <% end %>

      <div class="bg-white border border-gray-200 rounded-xl overflow-hidden">
        <%= if Enum.empty?(@promos) do %>
          <div class="text-center py-12 text-gray-500">
            <p class="text-lg">No promo codes yet</p>
            <p class="text-sm">Create one to start running promotions</p>
          </div>
        <% else %>
          <table class="w-full">
            <thead class="bg-gray-50 border-b border-gray-200">
              <tr>
                <th class="text-left px-4 py-3 text-sm font-medium text-gray-600">Code</th>
                <th class="text-left px-4 py-3 text-sm font-medium text-gray-600">Discount</th>
                <th class="text-left px-4 py-3 text-sm font-medium text-gray-600">Min Order</th>
                <th class="text-left px-4 py-3 text-sm font-medium text-gray-600">Uses</th>
                <th class="text-left px-4 py-3 text-sm font-medium text-gray-600">Status</th>
                <th class="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-100">
              <%= for promo <- @promos do %>
                <tr class="hover:bg-gray-50">
                  <td class="px-4 py-3 font-mono font-bold text-indigo-600">{promo.code}</td>
                  <td class="px-4 py-3">
                    <%= if promo.discount_type == "percentage" do %>
                      {promo.discount_value}%
                    <% else %>
                      {format_price(promo.discount_value)}
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-gray-600">{format_price(promo.min_order)}</td>
                  <td class="px-4 py-3 text-gray-600">
                    {promo.current_uses}{if promo.max_uses, do: "/#{promo.max_uses}", else: ""}
                  </td>
                  <td class="px-4 py-3">
                    <%= if promo.is_active do %>
                      <span class="bg-green-100 text-green-700 px-2 py-0.5 rounded-full text-xs font-medium">
                        Active
                      </span>
                    <% else %>
                      <span class="bg-gray-100 text-gray-600 px-2 py-0.5 rounded-full text-xs font-medium">
                        Inactive
                      </span>
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-right">
                    <button
                      phx-click="edit"
                      phx-value-id={promo.id}
                      class="text-indigo-600 hover:text-indigo-800 text-sm mr-3"
                    >
                      Edit
                    </button>
                    <%= if promo.is_active do %>
                      <button
                        phx-click="deactivate"
                        phx-value-id={promo.id}
                        data-confirm="Deactivate this promo code?"
                        class="text-red-500 hover:text-red-700 text-sm"
                      >
                        Deactivate
                      </button>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>
    </div>
    """
  end
end
