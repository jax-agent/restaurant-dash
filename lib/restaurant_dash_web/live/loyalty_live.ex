defmodule RestaurantDashWeb.LoyaltyLive do
  @moduledoc "Owner dashboard for loyalty program."
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.Loyalty

  @impl true
  def mount(_params, session, socket) do
    restaurant = session["current_restaurant"]

    if is_nil(restaurant) do
      {:ok, push_navigate(socket, to: "/")}
    else
      {:ok,
       socket
       |> assign(:restaurant, restaurant)
       |> assign(:rewards, Loyalty.list_rewards(restaurant.id))
       |> assign(:top_members, Loyalty.list_top_members(restaurant.id, 10))
       |> assign(:show_reward_form, false)
       |> assign(:form_data, %{"name" => "", "points_cost" => "", "discount_value" => ""})
       |> assign(:form_errors, %{})}
    end
  end

  @impl true
  def handle_event("show-reward-form", _, socket) do
    {:noreply, assign(socket, show_reward_form: true, form_errors: %{})}
  end

  @impl true
  def handle_event("hide-reward-form", _, socket) do
    {:noreply, assign(socket, show_reward_form: false)}
  end

  @impl true
  def handle_event("update-field", %{"field" => field, "value" => value}, socket) do
    form_data = Map.put(socket.assigns.form_data, field, value)
    {:noreply, assign(socket, form_data: form_data)}
  end

  @impl true
  def handle_event("save-reward", _, socket) do
    restaurant = socket.assigns.restaurant
    form = socket.assigns.form_data

    points_cost = parse_int(form["points_cost"])
    discount_cents = parse_dollars_to_cents(form["discount_value"])

    attrs = %{
      restaurant_id: restaurant.id,
      name: form["name"],
      points_cost: points_cost,
      discount_value: discount_cents
    }

    case Loyalty.create_reward(attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:rewards, Loyalty.list_rewards(restaurant.id))
         |> assign(:show_reward_form, false)
         |> assign(:form_errors, %{})}

      {:error, changeset} ->
        errors = errors_from_changeset(changeset)
        {:noreply, assign(socket, form_errors: errors)}
    end
  end

  @impl true
  def handle_event("deactivate-reward", %{"id" => id}, socket) do
    reward = Loyalty.get_reward!(String.to_integer(id))
    {:ok, _} = Loyalty.deactivate_reward(reward)

    {:noreply, assign(socket, rewards: Loyalty.list_rewards(socket.assigns.restaurant.id))}
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(str) do
    case Integer.parse(str) do
      {v, _} -> v
      :error -> nil
    end
  end

  defp parse_dollars_to_cents(nil), do: nil
  defp parse_dollars_to_cents(""), do: nil

  defp parse_dollars_to_cents(str) do
    case Float.parse(str) do
      {v, _} -> round(v * 100)
      :error -> nil
    end
  end

  defp errors_from_changeset(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.map(fn {k, v} -> {to_string(k), Enum.join(v, ", ")} end)
    |> Map.new()
  end

  defp format_price(nil), do: "$0.00"

  defp format_price(cents),
    do: "$#{div(cents, 100)}.#{String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6 space-y-8">
      <h1 class="text-2xl font-bold text-gray-900">Loyalty Program</h1>

      <%!-- Point Rate Info --%>
      <div class="bg-indigo-50 border border-indigo-200 rounded-xl p-4">
        <p class="text-indigo-800 font-medium">
          Earning Rate: <strong>{@restaurant.loyalty_points_rate} point(s) per $1 spent</strong>
        </p>
        <p class="text-indigo-600 text-sm mt-1">
          Points are awarded after payment is confirmed.
        </p>
      </div>

      <%!-- Rewards --%>
      <div>
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold text-gray-800">Rewards</h2>
          <button
            phx-click="show-reward-form"
            class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700 text-sm font-medium"
          >
            + Add Reward
          </button>
        </div>

        <%= if @show_reward_form do %>
          <div class="bg-white border border-gray-200 rounded-xl p-4 mb-4 shadow-sm">
            <div class="grid grid-cols-3 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Reward Name</label>
                <input
                  type="text"
                  value={@form_data["name"]}
                  phx-blur="update-field"
                  phx-value-field="name"
                  placeholder="Free Dessert"
                  class="w-full border border-gray-300 rounded-lg px-3 py-2"
                />
                <%= if @form_errors["name"] do %>
                  <p class="text-red-500 text-xs mt-1">{@form_errors["name"]}</p>
                <% end %>
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Points Cost</label>
                <input
                  type="number"
                  value={@form_data["points_cost"]}
                  phx-blur="update-field"
                  phx-value-field="points_cost"
                  placeholder="100"
                  class="w-full border border-gray-300 rounded-lg px-3 py-2"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Discount Value ($)</label>
                <input
                  type="number"
                  step="0.01"
                  value={@form_data["discount_value"]}
                  phx-blur="update-field"
                  phx-value-field="discount_value"
                  placeholder="5.00"
                  class="w-full border border-gray-300 rounded-lg px-3 py-2"
                />
              </div>
            </div>
            <div class="flex gap-3 mt-4">
              <button
                phx-click="save-reward"
                class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700 text-sm font-medium"
              >
                Save
              </button>
              <button
                phx-click="hide-reward-form"
                class="border border-gray-300 text-gray-700 px-4 py-2 rounded-lg text-sm"
              >
                Cancel
              </button>
            </div>
          </div>
        <% end %>

        <%= if Enum.empty?(@rewards) do %>
          <div class="bg-white border border-gray-200 rounded-xl p-8 text-center text-gray-500">
            No rewards yet. Add one to let customers redeem points.
          </div>
        <% else %>
          <div class="bg-white border border-gray-200 rounded-xl overflow-hidden">
            <table class="w-full">
              <thead class="bg-gray-50 border-b">
                <tr>
                  <th class="text-left px-4 py-3 text-sm font-medium text-gray-600">Name</th>
                  <th class="text-left px-4 py-3 text-sm font-medium text-gray-600">Points</th>
                  <th class="text-left px-4 py-3 text-sm font-medium text-gray-600">Discount</th>
                  <th class="text-left px-4 py-3 text-sm font-medium text-gray-600">Status</th>
                  <th class="px-4 py-3"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100">
                <%= for reward <- @rewards do %>
                  <tr>
                    <td class="px-4 py-3 font-medium">{reward.name}</td>
                    <td class="px-4 py-3 text-gray-600">{reward.points_cost} pts</td>
                    <td class="px-4 py-3 text-gray-600">{format_price(reward.discount_value)}</td>
                    <td class="px-4 py-3">
                      <%= if reward.is_active do %>
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
                      <%= if reward.is_active do %>
                        <button
                          phx-click="deactivate-reward"
                          phx-value-id={reward.id}
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
          </div>
        <% end %>
      </div>

      <%!-- Top Members --%>
      <div>
        <h2 class="text-lg font-semibold text-gray-800 mb-4">Top Loyalty Members</h2>
        <%= if Enum.empty?(@top_members) do %>
          <div class="bg-white border border-gray-200 rounded-xl p-8 text-center text-gray-500">
            No loyalty members yet.
          </div>
        <% else %>
          <div class="bg-white border border-gray-200 rounded-xl overflow-hidden">
            <table class="w-full">
              <thead class="bg-gray-50 border-b">
                <tr>
                  <th class="text-left px-4 py-3 text-sm font-medium text-gray-600">#</th>
                  <th class="text-left px-4 py-3 text-sm font-medium text-gray-600">Customer</th>
                  <th class="text-left px-4 py-3 text-sm font-medium text-gray-600">
                    Points Balance
                  </th>
                  <th class="text-left px-4 py-3 text-sm font-medium text-gray-600">Total Earned</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100">
                <%= for {member, idx} <- Enum.with_index(@top_members, 1) do %>
                  <tr>
                    <td class="px-4 py-3 text-gray-500">{idx}</td>
                    <td class="px-4 py-3">{member.customer_email}</td>
                    <td class="px-4 py-3 font-semibold text-indigo-600">
                      {member.points_balance} pts
                    </td>
                    <td class="px-4 py-3 text-gray-600">{member.total_points_earned} pts</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
