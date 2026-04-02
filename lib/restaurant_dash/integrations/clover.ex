defmodule RestaurantDash.Integrations.Clover do
  @moduledoc """
  Clover POS integration context for RestaurantDash.

  Handles:
  - OAuth connection/disconnection
  - Menu import from Clover catalog
  - Order push to Clover POS
  - Inventory sync (86'd items)
  - Payment reconciliation

  Operates in mock mode when no CLOVER_APP_SECRET is configured.
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Tenancy.Restaurant
  alias RestaurantDash.Integrations.Clover.Client
  alias RestaurantDash.Menu
  alias RestaurantDash.Orders.Order

  # ── Config ─────────────────────────────────────────────────────────────────

  @doc "Returns true when running without real Clover credentials."
  def mock_mode?, do: Client.mock_mode?()

  # ── OAuth ──────────────────────────────────────────────────────────────────

  @doc """
  Build the URL to redirect the merchant to Clover for authorization.
  """
  def authorization_url(redirect_uri) do
    Client.authorization_url(redirect_uri)
  end

  @doc """
  Complete OAuth flow: exchange code for access token, save to restaurant.
  Returns {:ok, restaurant} or {:error, reason}.
  """
  def connect(restaurant, code) do
    with {:ok, token_data} <- Client.exchange_code(code),
         merchant_id <- Map.get(token_data, "merchant_id"),
         access_token <- Map.get(token_data, "access_token"),
         true <- (not is_nil(merchant_id) && not is_nil(access_token)) || :missing_data,
         {:ok, restaurant} <- save_clover_credentials(restaurant, merchant_id, access_token) do
      {:ok, restaurant}
    else
      :missing_data -> {:error, "Invalid response from Clover: missing merchant_id or token"}
      false -> {:error, "Invalid response from Clover: missing merchant_id or token"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Save Clover merchant_id and access_token to the restaurant.
  """
  def save_clover_credentials(restaurant, merchant_id, access_token) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    restaurant
    |> Ecto.Changeset.change(%{
      clover_merchant_id: merchant_id,
      clover_access_token: access_token,
      clover_connected_at: now
    })
    |> Repo.update()
  end

  @doc """
  Disconnect Clover from a restaurant (clear all Clover credentials).
  Returns {:ok, restaurant} or {:error, changeset}.
  """
  def disconnect(restaurant) do
    restaurant
    |> Ecto.Changeset.change(%{
      clover_merchant_id: nil,
      clover_access_token: nil,
      clover_connected_at: nil
    })
    |> Repo.update()
  end

  @doc """
  Returns true if a restaurant has a valid Clover connection.
  """
  def connected?(%Restaurant{clover_merchant_id: mid, clover_access_token: token}) do
    not is_nil(mid) and not is_nil(token)
  end

  def connected?(_), do: false

  @doc """
  Fetch merchant info for a connected restaurant.
  """
  def get_merchant_info(%Restaurant{clover_merchant_id: mid, clover_access_token: token}) do
    Client.get_merchant(mid, token)
  end

  # ── Menu Import ─────────────────────────────────────────────────────────────

  @doc """
  Import the full Clover catalog into our menu system.
  Returns {:ok, %{categories: n, items: n, modifier_groups: n}} or {:error, reason}.

  Options:
    - :mode - :overwrite (replace existing) | :merge (default, skip existing by name)
  """
  def import_menu(%Restaurant{} = restaurant, opts \\ []) do
    mode = Keyword.get(opts, :mode, :merge)

    with {:ok, clover_categories} <-
           Client.list_categories(restaurant.clover_merchant_id, restaurant.clover_access_token),
         {:ok, clover_items} <-
           Client.list_items(restaurant.clover_merchant_id, restaurant.clover_access_token),
         {:ok, clover_modifier_groups} <-
           Client.list_modifier_groups(
             restaurant.clover_merchant_id,
             restaurant.clover_access_token
           ) do
      # Import categories first
      {cat_count, category_map} = import_categories(restaurant, clover_categories, mode)

      # Import modifier groups
      {mg_count, modifier_group_map} =
        import_modifier_groups(restaurant, clover_modifier_groups, mode)

      # Import items with their category and modifier group associations
      item_count = import_items(restaurant, clover_items, category_map, modifier_group_map, mode)

      {:ok, %{categories: cat_count, items: item_count, modifier_groups: mg_count}}
    end
  end

  defp import_categories(restaurant, clover_categories, mode) do
    existing = Menu.list_categories(restaurant.id)
    existing_by_name = Map.new(existing, &{String.downcase(&1.name), &1})

    results =
      clover_categories
      |> Enum.with_index()
      |> Enum.map(fn {cat, idx} ->
        name = cat["name"] || "Category #{idx + 1}"
        clover_id = cat["id"]

        case {mode, Map.get(existing_by_name, String.downcase(name))} do
          {:merge, existing_cat} when not is_nil(existing_cat) ->
            # Already exists, return mapping
            {clover_id, existing_cat.id}

          _ ->
            # Create new
            attrs = %{
              name: name,
              description: cat["description"],
              position: cat["sortOrder"] || idx,
              restaurant_id: restaurant.id,
              is_active: true
            }

            case Menu.create_category(attrs) do
              {:ok, new_cat} -> {clover_id, new_cat.id}
              _ -> nil
            end
        end
      end)
      |> Enum.reject(&is_nil/1)

    count = length(results)
    mapping = Map.new(results)
    {count, mapping}
  end

  defp import_modifier_groups(restaurant, clover_groups, _mode) do
    existing = Menu.list_modifier_groups(restaurant.id)
    existing_by_name = Map.new(existing, &{String.downcase(&1.name), &1})

    results =
      Enum.map(clover_groups, fn group ->
        name = group["name"] || "Modifier Group"
        clover_id = group["id"]
        modifiers = get_in(group, ["modifiers", "elements"]) || []

        existing_group = Map.get(existing_by_name, String.downcase(name))

        mg =
          case existing_group do
            nil ->
              attrs = %{name: name, restaurant_id: restaurant.id, required: false}

              case Menu.create_modifier_group(attrs) do
                {:ok, mg} -> mg
                _ -> nil
              end

            mg ->
              mg
          end

        if mg do
          # Import modifiers for this group
          import_modifiers(mg, modifiers, restaurant.id)
          {clover_id, mg.id}
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    count = length(results)
    mapping = Map.new(results)
    {count, mapping}
  end

  defp import_modifiers(modifier_group, clover_modifiers, restaurant_id) do
    existing = Menu.list_modifiers(modifier_group.id)
    existing_names = MapSet.new(existing, &String.downcase(&1.name))

    Enum.each(clover_modifiers, fn mod ->
      name = mod["name"] || "Modifier"

      unless MapSet.member?(existing_names, String.downcase(name)) do
        attrs = %{
          name: name,
          price_adjustment: mod["price"] || 0,
          modifier_group_id: modifier_group.id,
          restaurant_id: restaurant_id,
          is_active: true
        }

        Menu.create_modifier(attrs)
      end
    end)
  end

  defp import_items(restaurant, clover_items, category_map, modifier_group_map, mode) do
    existing = Menu.list_items(restaurant.id)
    existing_by_name = Map.new(existing, &{String.downcase(&1.name), &1})

    results =
      clover_items
      |> Enum.with_index()
      |> Enum.map(fn {item, idx} ->
        name = item["name"] || "Item #{idx + 1}"
        clover_category_ids = get_in(item, ["categories", "elements"]) || []
        clover_mg_ids = get_in(item, ["modifierGroups", "elements"]) || []

        # Map to our category ID (use first matching category)
        category_id =
          clover_category_ids
          |> Enum.find_value(fn %{"id" => cid} -> Map.get(category_map, cid) end)

        modifier_group_ids =
          clover_mg_ids
          |> Enum.map(fn %{"id" => mgid} -> Map.get(modifier_group_map, mgid) end)
          |> Enum.reject(&is_nil/1)

        case {mode, Map.get(existing_by_name, String.downcase(name))} do
          {:merge, existing_item} when not is_nil(existing_item) ->
            # Exists, skip
            :skipped

          _ ->
            attrs = %{
              name: name,
              description: item["description"],
              price: item["price"] || 0,
              position: idx,
              is_active: item["available"] != false,
              is_available: item["available"] != false,
              restaurant_id: restaurant.id,
              menu_category_id: category_id
            }

            case Menu.create_item(attrs) do
              {:ok, new_item} ->
                # Associate modifier groups
                if modifier_group_ids != [] do
                  Menu.set_item_modifier_groups(new_item, modifier_group_ids)
                end

                :created

              _ ->
                :failed
            end
        end
      end)

    Enum.count(results, &(&1 == :created))
  end

  # ── Order Push ─────────────────────────────────────────────────────────────

  @doc """
  Push an order to Clover POS.
  Returns {:ok, clover_order_id} or {:error, reason}.
  On failure the order still exists in our system — push is best-effort.
  """
  def push_order(%Order{} = order, %Restaurant{} = restaurant) do
    unless connected?(restaurant) do
      {:error, :not_connected}
    else
      payload = build_clover_order(order, restaurant)

      case Client.create_atomic_order(
             restaurant.clover_merchant_id,
             restaurant.clover_access_token,
             payload
           ) do
        {:ok, clover_order} ->
          clover_id = clover_order["id"]

          # Save clover_order_id to our order
          order
          |> Ecto.Changeset.change(%{clover_order_id: clover_id})
          |> Repo.update()

          {:ok, clover_id}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Build the Clover Atomic Orders payload from our Order struct.
  """
  def build_clover_order(%Order{} = order, %Restaurant{} = _restaurant) do
    order = Repo.preload(order, order_items: [:item, modifier_selections: [:modifier]])

    line_items =
      Enum.map(order.order_items, fn oi ->
        item_name = if oi.item, do: oi.item.name, else: oi.item_name || "Item"

        base = %{
          "name" => item_name,
          "price" => oi.unit_price,
          "unitQty" => oi.quantity * 1000
        }

        # Add modifiers if present
        modifications =
          (oi.modifier_selections || [])
          |> Enum.map(fn ms ->
            mod_name = if ms.modifier, do: ms.modifier.name, else: "Modifier"
            %{"name" => mod_name, "amount" => ms.price_adjustment || 0}
          end)

        if modifications != [] do
          Map.put(base, "modifications", modifications)
        else
          base
        end
      end)

    %{
      "orderType" => %{"label" => "Online Order"},
      "note" => "Online order for #{order.customer_name}",
      "lineItems" => line_items,
      "total" => order.total_amount
    }
  end

  # ── Inventory Sync ─────────────────────────────────────────────────────────

  @doc """
  Sync item availability from Clover to our menu.
  Returns {:ok, %{updated: n, skipped: n}} or {:error, reason}.
  """
  def sync_inventory(%Restaurant{} = restaurant) do
    unless connected?(restaurant) do
      {:error, :not_connected}
    else
      case Client.list_item_stocks(restaurant.clover_merchant_id, restaurant.clover_access_token) do
        {:ok, stocks} ->
          results = apply_stock_changes(restaurant, stocks)
          {:ok, results}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp apply_stock_changes(restaurant, stocks) do
    # Build lookup: clover_item_id → available?
    # Quantity == 0 means 86'd (unavailable)
    availability_map =
      Map.new(stocks, fn stock ->
        item_id = get_in(stock, ["item", "id"]) || stock["id"]
        qty = stock["quantityInStock"] || stock["quantity"] || 0
        {item_id, qty > 0}
      end)

    # We don't store clover item IDs currently, so match by name in mock mode
    # In production this would need clover_item_id on menu_items
    # For now: in mock mode, simulate some items being unavailable
    if mock_mode?() do
      apply_mock_stock_changes(restaurant, availability_map)
    else
      # TODO: match by clover_item_id once we store it
      %{updated: 0, skipped: length(stocks)}
    end
  end

  defp apply_mock_stock_changes(restaurant, availability_map) do
    items = Menu.list_items(restaurant.id)

    results =
      Enum.map(items, fn item ->
        # Mock: ITEM_PIZZA maps to unavailable
        mock_clover_id = mock_clover_id_for(item.name)
        available = Map.get(availability_map, mock_clover_id, true)

        if item.is_available != available do
          case Menu.update_item(item, %{is_available: available}) do
            {:ok, _} -> :updated
            _ -> :skipped
          end
        else
          :skipped
        end
      end)

    %{
      updated: Enum.count(results, &(&1 == :updated)),
      skipped: Enum.count(results, &(&1 == :skipped))
    }
  end

  # Simple heuristic for mock mode
  defp mock_clover_id_for(name) do
    cond do
      String.contains?(String.downcase(name), "pizza") -> "ITEM_PIZZA"
      String.contains?(String.downcase(name), "burger") -> "ITEM_BURGER"
      String.contains?(String.downcase(name), "nacho") -> "ITEM_NACHOS"
      true -> "ITEM_UNKNOWN"
    end
  end

  # ── Payment Reconciliation ─────────────────────────────────────────────────

  @doc """
  Fetch Clover payments and reconcile with our orders.
  Returns {:ok, %{matched: [...], unmatched: [...], discrepancies: [...]}} or {:error, reason}.
  """
  def reconcile_payments(%Restaurant{} = restaurant, opts \\ []) do
    unless connected?(restaurant) do
      {:error, :not_connected}
    else
      case Client.list_payments(
             restaurant.clover_merchant_id,
             restaurant.clover_access_token,
             opts
           ) do
        {:ok, clover_payments} ->
          our_orders = list_orders_with_clover(restaurant.id)
          reconciliation = do_reconcile(our_orders, clover_payments)
          {:ok, reconciliation}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp list_orders_with_clover(restaurant_id) do
    Order
    |> where([o], o.restaurant_id == ^restaurant_id)
    |> where([o], not is_nil(o.clover_order_id))
    |> Repo.all()
  end

  defp do_reconcile(our_orders, clover_payments) do
    our_by_clover_id = Map.new(our_orders, &{&1.clover_order_id, &1})

    {matched, unmatched} =
      Enum.split_with(clover_payments, fn pay ->
        clover_order_id = get_in(pay, ["order", "id"])
        Map.has_key?(our_by_clover_id, clover_order_id)
      end)

    discrepancies =
      Enum.flat_map(matched, fn pay ->
        clover_order_id = get_in(pay, ["order", "id"])
        our_order = Map.get(our_by_clover_id, clover_order_id)

        if our_order && our_order.total_amount != pay["amount"] do
          [
            %{
              order_id: our_order.id,
              clover_order_id: clover_order_id,
              our_amount: our_order.total_amount,
              clover_amount: pay["amount"],
              difference: abs(our_order.total_amount - pay["amount"])
            }
          ]
        else
          []
        end
      end)

    %{
      matched: matched,
      unmatched: unmatched,
      discrepancies: discrepancies,
      summary: %{
        total_clover_payments: length(clover_payments),
        matched_count: length(matched),
        unmatched_count: length(unmatched),
        discrepancy_count: length(discrepancies)
      }
    }
  end

  @doc """
  Export reconciliation data as CSV string.
  """
  def export_reconciliation_csv(%Restaurant{} = restaurant) do
    case reconcile_payments(restaurant) do
      {:ok, data} ->
        header = "Order ID,Clover Order ID,Our Amount,Clover Amount,Status,Discrepancy\n"

        rows =
          (data.matched ++ data.unmatched)
          |> Enum.map(fn pay ->
            clover_id = get_in(pay, ["order", "id"]) || ""
            clover_amount = pay["amount"] || 0
            status = if is_nil(clover_id) or clover_id == "", do: "UNMATCHED", else: "MATCHED"

            discrepancy =
              Enum.find(data.discrepancies, fn d -> d.clover_order_id == clover_id end)

            diff = if discrepancy, do: discrepancy.difference, else: 0
            our_amount = if discrepancy, do: discrepancy.our_amount, else: clover_amount

            "#{clover_id},#{clover_id},#{our_amount},#{clover_amount},#{status},#{diff}\n"
          end)

        {:ok, header <> Enum.join(rows)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
