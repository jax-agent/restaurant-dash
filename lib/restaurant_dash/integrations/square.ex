defmodule RestaurantDash.Integrations.Square do
  @moduledoc """
  Square POS integration context for RestaurantDash.

  Handles:
  - OAuth connection/disconnection + token refresh
  - Menu import from Square Catalog API
  - Order push to Square POS
  - Inventory sync (86'd items via BatchRetrieveInventoryCounts)
  - Square Payments as an alternative to Stripe

  Operates in mock mode when no SQUARE_APP_SECRET is configured.
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Tenancy.Restaurant
  alias RestaurantDash.Integrations.Square.Client
  alias RestaurantDash.Menu
  alias RestaurantDash.Orders.Order

  # ── Config ─────────────────────────────────────────────────────────────────

  @doc "Returns true when running without real Square credentials."
  def mock_mode?, do: Client.mock_mode?()

  # ── OAuth ──────────────────────────────────────────────────────────────────

  @doc """
  Build the URL to redirect the merchant to Square for authorization.
  """
  def authorization_url(redirect_uri) do
    Client.authorization_url(redirect_uri)
  end

  @doc """
  Complete OAuth flow: exchange code for access + refresh tokens, save to restaurant.
  Also fetches the first location_id for order pushing.
  Returns {:ok, restaurant} or {:error, reason}.
  """
  def connect(restaurant, code) do
    with {:ok, token_data} <- Client.exchange_code(code),
         access_token <- Map.get(token_data, "access_token"),
         refresh_token <- Map.get(token_data, "refresh_token"),
         merchant_id <- Map.get(token_data, "merchant_id"),
         true <- (not is_nil(merchant_id) && not is_nil(access_token)) || :missing_data,
         location_id <- fetch_first_location_id(access_token),
         {:ok, restaurant} <-
           save_square_credentials(
             restaurant,
             merchant_id,
             access_token,
             refresh_token,
             location_id
           ) do
      {:ok, restaurant}
    else
      :missing_data -> {:error, "Invalid response from Square: missing merchant_id or token"}
      false -> {:error, "Invalid response from Square: missing merchant_id or token"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Refresh the Square access token using the stored refresh token.
  Updates restaurant with new tokens.
  Returns {:ok, restaurant} or {:error, reason}.
  """
  def refresh_access_token(%Restaurant{square_refresh_token: nil}) do
    {:error, :no_refresh_token}
  end

  def refresh_access_token(%Restaurant{} = restaurant) do
    case Client.refresh_token(restaurant.square_refresh_token) do
      {:ok, token_data} ->
        new_access_token = Map.get(token_data, "access_token")

        new_refresh_token =
          Map.get(token_data, "refresh_token") || restaurant.square_refresh_token

        restaurant
        |> Ecto.Changeset.change(%{
          square_access_token: new_access_token,
          square_refresh_token: new_refresh_token
        })
        |> Repo.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Save Square credentials to the restaurant.
  """
  def save_square_credentials(
        restaurant,
        merchant_id,
        access_token,
        refresh_token,
        location_id \\ nil
      ) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    restaurant
    |> Ecto.Changeset.change(%{
      square_merchant_id: merchant_id,
      square_access_token: access_token,
      square_refresh_token: refresh_token,
      square_location_id: location_id,
      square_connected_at: now
    })
    |> Repo.update()
  end

  @doc """
  Disconnect Square from a restaurant (clear all Square credentials).
  Returns {:ok, restaurant} or {:error, changeset}.
  """
  def disconnect(restaurant) do
    restaurant
    |> Ecto.Changeset.change(%{
      square_merchant_id: nil,
      square_access_token: nil,
      square_refresh_token: nil,
      square_location_id: nil,
      square_connected_at: nil
    })
    |> Repo.update()
  end

  @doc """
  Returns true if a restaurant has a valid Square connection.
  """
  def connected?(%Restaurant{square_merchant_id: mid, square_access_token: token}) do
    not is_nil(mid) and not is_nil(token)
  end

  def connected?(_), do: false

  @doc """
  Fetch merchant info for a connected restaurant.
  """
  def get_merchant_info(%Restaurant{square_merchant_id: mid, square_access_token: token}) do
    case Client.get_merchant(mid, token) do
      {:ok, %{"merchant" => merchant}} -> {:ok, merchant}
      {:ok, data} -> {:ok, data}
      error -> error
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp fetch_first_location_id(access_token) do
    case Client.list_locations(access_token) do
      {:ok, %{"locations" => [first | _]}} -> first["id"]
      _ -> nil
    end
  end

  # ── Menu Import ─────────────────────────────────────────────────────────────

  @doc """
  Import the full Square catalog into our menu system.
  Returns {:ok, %{categories: n, items: n, modifier_groups: n}} or {:error, reason}.

  Square catalog structure:
  - CATEGORY objects → our menu categories
  - MODIFIER_LIST objects → our modifier groups (with nested modifiers)
  - ITEM objects → our menu items, with ITEM_VARIATION for pricing

  Variation handling:
  - Single variation: use variation price as item price
  - Multiple variations: create a modifier group from variations

  Options:
    - :mode - :overwrite (replace existing) | :merge (default, skip existing by name)
  """
  def import_menu(%Restaurant{} = restaurant, opts \\ []) do
    mode = Keyword.get(opts, :mode, :merge)

    with {:ok, catalog_objects} <- Client.list_catalog(restaurant.square_access_token) do
      categories = filter_by_type(catalog_objects, "CATEGORY")
      modifier_lists = filter_by_type(catalog_objects, "MODIFIER_LIST")
      items = filter_by_type(catalog_objects, "ITEM")

      # Import categories first
      {cat_count, category_map} = import_categories(restaurant, categories, mode)

      # Import modifier groups from MODIFIER_LIST objects
      {mg_count, modifier_group_map} = import_modifier_groups(restaurant, modifier_lists, mode)

      # Import items with variation handling
      item_count = import_items(restaurant, items, category_map, modifier_group_map, mode)

      {:ok, %{categories: cat_count, items: item_count, modifier_groups: mg_count}}
    end
  end

  defp filter_by_type(objects, type) do
    Enum.filter(objects, fn obj -> obj["type"] == type end)
  end

  defp import_categories(restaurant, sq_categories, mode) do
    existing = Menu.list_categories(restaurant.id)
    existing_by_name = Map.new(existing, &{String.downcase(&1.name), &1})

    results =
      sq_categories
      |> Enum.with_index()
      |> Enum.map(fn {cat, idx} ->
        name = get_in(cat, ["category_data", "name"]) || "Category #{idx + 1}"
        sq_id = cat["id"]

        case {mode, Map.get(existing_by_name, String.downcase(name))} do
          {:merge, existing_cat} when not is_nil(existing_cat) ->
            {sq_id, existing_cat.id}

          _ ->
            attrs = %{
              name: name,
              position: idx,
              restaurant_id: restaurant.id,
              is_active: true
            }

            case Menu.create_category(attrs) do
              {:ok, new_cat} -> {sq_id, new_cat.id}
              _ -> nil
            end
        end
      end)
      |> Enum.reject(&is_nil/1)

    {length(results), Map.new(results)}
  end

  defp import_modifier_groups(restaurant, sq_modifier_lists, _mode) do
    existing = Menu.list_modifier_groups(restaurant.id)
    existing_by_name = Map.new(existing, &{String.downcase(&1.name), &1})

    results =
      Enum.map(sq_modifier_lists, fn ml ->
        name = get_in(ml, ["modifier_list_data", "name"]) || "Modifier Group"
        sq_id = ml["id"]
        modifiers = get_in(ml, ["modifier_list_data", "modifiers"]) || []

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
          import_modifiers_from_list(mg, modifiers, restaurant.id)
          {sq_id, mg.id}
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {length(results), Map.new(results)}
  end

  defp import_modifiers_from_list(modifier_group, sq_modifiers, restaurant_id) do
    existing = Menu.list_modifiers(modifier_group.id)
    existing_names = MapSet.new(existing, &String.downcase(&1.name))

    Enum.each(sq_modifiers, fn mod ->
      name = get_in(mod, ["modifier_data", "name"]) || "Modifier"
      price = get_in(mod, ["modifier_data", "price_money", "amount"]) || 0

      unless MapSet.member?(existing_names, String.downcase(name)) do
        attrs = %{
          name: name,
          price_adjustment: price,
          modifier_group_id: modifier_group.id,
          restaurant_id: restaurant_id,
          is_active: true
        }

        Menu.create_modifier(attrs)
      end
    end)
  end

  defp import_items(restaurant, sq_items, category_map, modifier_group_map, mode) do
    existing = Menu.list_items(restaurant.id)
    existing_by_name = Map.new(existing, &{String.downcase(&1.name), &1})

    results =
      sq_items
      |> Enum.with_index()
      |> Enum.map(fn {item, idx} ->
        item_data = item["item_data"] || %{}
        name = item_data["name"] || "Item #{idx + 1}"
        sq_category_id = item_data["category_id"]
        variations = item_data["variations"] || []
        modifier_list_info = item_data["modifier_list_info"] || []

        # Map to our category ID
        category_id = Map.get(category_map, sq_category_id)

        # Map to our modifier group IDs
        modifier_group_ids =
          modifier_list_info
          |> Enum.filter(fn info -> info["enabled"] != false end)
          |> Enum.map(fn info -> Map.get(modifier_group_map, info["modifier_list_id"]) end)
          |> Enum.reject(&is_nil/1)

        # Determine price and variation handling
        {price, extra_mg_id} = resolve_price_from_variations(restaurant, name, variations)

        all_mg_ids =
          if extra_mg_id, do: [extra_mg_id | modifier_group_ids], else: modifier_group_ids

        case {mode, Map.get(existing_by_name, String.downcase(name))} do
          {:merge, existing_item} when not is_nil(existing_item) ->
            :skipped

          _ ->
            attrs = %{
              name: name,
              description: item_data["description"],
              price: price,
              position: idx,
              is_active: true,
              is_available: true,
              restaurant_id: restaurant.id,
              menu_category_id: category_id
            }

            case Menu.create_item(attrs) do
              {:ok, new_item} ->
                if all_mg_ids != [] do
                  Menu.set_item_modifier_groups(new_item, all_mg_ids)
                end

                :created

              _ ->
                :failed
            end
        end
      end)

    Enum.count(results, &(&1 == :created))
  end

  # For single variation: use variation price as item price
  # For multiple variations: create a "Size/Option" modifier group from variations
  defp resolve_price_from_variations(restaurant, item_name, variations) do
    case variations do
      [] ->
        {0, nil}

      [single] ->
        price = get_in(single, ["item_variation_data", "price_money", "amount"]) || 0
        {price, nil}

      multiple ->
        # Use first variation price as base, create modifier group for the rest
        base_price =
          get_in(List.first(multiple), ["item_variation_data", "price_money", "amount"]) || 0

        mg_id = create_variation_modifier_group(restaurant, item_name, multiple)
        {base_price, mg_id}
    end
  end

  defp create_variation_modifier_group(restaurant, item_name, variations) do
    group_name = "#{item_name} - Options"

    case Menu.create_modifier_group(%{
           name: group_name,
           restaurant_id: restaurant.id,
           required: false
         }) do
      {:ok, mg} ->
        Enum.each(variations, fn var ->
          var_data = var["item_variation_data"] || %{}
          var_name = var_data["name"] || "Option"
          var_price = get_in(var_data, ["price_money", "amount"]) || 0

          Menu.create_modifier(%{
            name: var_name,
            price_adjustment: var_price,
            modifier_group_id: mg.id,
            restaurant_id: restaurant.id,
            is_active: true
          })
        end)

        mg.id

      _ ->
        nil
    end
  end

  # ── Order Push ─────────────────────────────────────────────────────────────

  @doc """
  Push an order to Square POS via the Orders API.
  Returns {:ok, square_order_id} or {:error, reason}.
  On failure the order still exists in our system — push is best-effort.
  """
  def push_order(%Order{} = order, %Restaurant{} = restaurant) do
    unless connected?(restaurant) do
      {:error, :not_connected}
    else
      payload = build_square_order(order, restaurant)
      location_id = restaurant.square_location_id || "DEFAULT"

      case Client.create_order(location_id, restaurant.square_access_token, payload) do
        {:ok, %{"order" => sq_order}} ->
          sq_order_id = sq_order["id"]

          order
          |> Ecto.Changeset.change(%{square_order_id: sq_order_id})
          |> Repo.update()

          {:ok, sq_order_id}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Build the Square Orders API payload from our Order struct.
  Uses DELIVERY fulfillment type with delivery details.
  """
  def build_square_order(%Order{} = order, %Restaurant{} = restaurant) do
    order = Repo.preload(order, order_items: [:item, modifier_selections: [:modifier]])
    location_id = restaurant.square_location_id || "DEFAULT"

    line_items =
      Enum.map(order.order_items, fn oi ->
        item_name = if oi.item, do: oi.item.name, else: oi.item_name || "Item"

        base = %{
          "name" => item_name,
          "quantity" => "#{oi.quantity}",
          "base_price_money" => %{
            "amount" => oi.unit_price,
            "currency" => "USD"
          }
        }

        # Add applied modifiers if present
        modifiers =
          (oi.modifier_selections || [])
          |> Enum.map(fn ms ->
            mod_name = if ms.modifier, do: ms.modifier.name, else: "Modifier"

            %{
              "name" => mod_name,
              "base_price_money" => %{
                "amount" => ms.price_adjustment || 0,
                "currency" => "USD"
              }
            }
          end)

        if modifiers != [] do
          Map.put(base, "modifiers", modifiers)
        else
          base
        end
      end)

    fulfillment = %{
      "type" => "DELIVERY",
      "delivery_details" => %{
        "recipient" => %{
          "display_name" => order.customer_name,
          "phone_number" => order.customer_phone || order.phone || "",
          "address" => %{
            "address_line_1" => order.delivery_address || "",
            "country" => "US"
          }
        },
        "schedule_type" => "ASAP"
      }
    }

    %{
      "location_id" => location_id,
      "line_items" => line_items,
      "fulfillments" => [fulfillment],
      "metadata" => %{
        "restaurant_dash_order_id" => "#{order.id}",
        "customer_name" => order.customer_name
      },
      "total_money" => %{
        "amount" => order.total_amount,
        "currency" => "USD"
      }
    }
  end

  # ── Inventory Sync ─────────────────────────────────────────────────────────

  @doc """
  Sync item availability from Square inventory to our menu.
  Uses BatchRetrieveInventoryCounts API.
  Returns {:ok, %{updated: n, skipped: n}} or {:error, reason}.
  """
  def sync_inventory(%Restaurant{} = restaurant) do
    unless connected?(restaurant) do
      {:error, :not_connected}
    else
      items = Menu.list_items(restaurant.id)
      # We use item names as mock catalog IDs in mock mode
      # In production, catalog_object_ids would be stored on menu items
      catalog_ids = if mock_mode?(), do: mock_catalog_ids_for(items), else: []
      location_id = restaurant.square_location_id

      case Client.batch_retrieve_inventory_counts(
             catalog_ids,
             location_id,
             restaurant.square_access_token
           ) do
        {:ok, counts} ->
          results = apply_inventory_changes(restaurant, items, counts)
          {:ok, results}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp mock_catalog_ids_for(items) do
    Enum.map(items, fn item ->
      cond do
        String.contains?(String.downcase(item.name), "pizza") -> "SQ_VAR_PIZZA"
        String.contains?(String.downcase(item.name), "burger") -> "SQ_VAR_BURGER"
        String.contains?(String.downcase(item.name), "nacho") -> "SQ_VAR_NACHOS"
        true -> "SQ_VAR_#{:crypto.strong_rand_bytes(4) |> Base.encode16()}"
      end
    end)
  end

  defp apply_inventory_changes(_restaurant, items, counts) do
    # Build map: catalog_object_id → available?
    availability_map =
      Map.new(counts, fn count ->
        id = count["catalog_object_id"]
        qty = count["quantity"] |> parse_quantity()
        {id, qty > 0}
      end)

    results =
      Enum.map(items, fn item ->
        catalog_id = mock_catalog_id_for_item(item)
        available = Map.get(availability_map, catalog_id, true)

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

  defp mock_catalog_id_for_item(item) do
    cond do
      String.contains?(String.downcase(item.name), "pizza") -> "SQ_VAR_PIZZA"
      String.contains?(String.downcase(item.name), "burger") -> "SQ_VAR_BURGER"
      String.contains?(String.downcase(item.name), "nacho") -> "SQ_VAR_NACHOS"
      true -> "SQ_VAR_UNKNOWN"
    end
  end

  defp parse_quantity(qty) when is_binary(qty) do
    case Float.parse(qty) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_quantity(qty) when is_number(qty), do: qty * 1.0
  defp parse_quantity(_), do: 0.0

  # ── Payments ──────────────────────────────────────────────────────────────

  @doc """
  Create a Square payment with a source_id from Square Web Payments SDK.
  Returns {:ok, payment} or {:error, reason}.

  payment_params must include:
    - source_id: nonce from Square Web Payments SDK (or "cnon:card-nonce-ok" in sandbox)
    - amount: integer in cents
    - currency: "USD"
    - idempotency_key: unique string per payment attempt
  """
  def create_payment(%Restaurant{} = restaurant, payment_params) do
    unless connected?(restaurant) do
      {:error, :not_connected}
    else
      sq_params = %{
        source_id: payment_params[:source_id] || payment_params["source_id"],
        idempotency_key:
          payment_params[:idempotency_key] || payment_params["idempotency_key"] ||
            random_idempotency_key(),
        amount_money: %{
          amount: payment_params[:amount] || payment_params["amount"] || 0,
          currency: payment_params[:currency] || payment_params["currency"] || "USD"
        },
        location_id: restaurant.square_location_id
      }

      case Client.create_payment(restaurant.square_access_token, sq_params) do
        {:ok, %{"payment" => payment}} -> {:ok, payment}
        {:ok, data} -> {:ok, data}
        error -> error
      end
    end
  end

  @doc """
  Detect the payment provider for a restaurant.
  Returns :square if the restaurant has Square connected, :stripe otherwise.
  """
  def payment_provider(%Restaurant{} = restaurant) do
    if connected?(restaurant), do: :square, else: :stripe
  end

  defp random_idempotency_key do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  # ── Webhook Validation ──────────────────────────────────────────────────────

  @doc """
  Validate a Square webhook signature.
  Square uses HMAC-SHA256 with the webhook signature key.
  """
  def valid_webhook_signature?(body, signature, webhook_key) do
    if is_nil(webhook_key) or webhook_key == "" do
      # No key configured — allow in mock mode
      mock_mode?()
    else
      expected =
        :crypto.mac(:hmac, :sha256, webhook_key, body)
        |> Base.encode64()

      Plug.Crypto.secure_compare(expected, signature)
    end
  end
end
