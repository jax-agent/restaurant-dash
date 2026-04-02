defmodule RestaurantDash.Integrations.Clover.Client do
  @moduledoc """
  Low-level Clover REST API client using Req.
  Falls back to mock mode when no CLOVER_APP_SECRET is configured.

  All API calls require a merchant access token obtained via OAuth.
  Base URLs:
    Production: https://api.clover.com
    Sandbox:    https://sandbox.dev.clover.com
  """

  @production_base "https://api.clover.com"
  @sandbox_base "https://sandbox.dev.clover.com"

  # ── Config ─────────────────────────────────────────────────────────────────

  def app_id do
    Application.get_env(:restaurant_dash, :clover, [])[:app_id]
  end

  def app_secret do
    Application.get_env(:restaurant_dash, :clover, [])[:app_secret]
  end

  def mock_mode? do
    secret = app_secret()
    is_nil(secret) or secret == "" or secret == "clover_mock"
  end

  def base_url do
    env = Application.get_env(:restaurant_dash, :clover, [])[:env] || :sandbox

    case env do
      :production -> @production_base
      _ -> @sandbox_base
    end
  end

  # ── OAuth ──────────────────────────────────────────────────────────────────

  @doc """
  Build the Clover OAuth authorization URL.
  Redirects the merchant to Clover to authorize our app.
  """
  def authorization_url(redirect_uri, state \\ nil) do
    params = %{
      client_id: app_id(),
      redirect_uri: redirect_uri,
      response_type: "code"
    }

    params = if state, do: Map.put(params, :state, state), else: params
    query = URI.encode_query(params)
    "#{base_url()}/oauth/authorize?#{query}"
  end

  @doc """
  Exchange an authorization code for an access token.
  Returns {:ok, %{merchant_id: ..., access_token: ...}} or {:error, reason}.
  """
  def exchange_code(code) do
    if mock_mode?() do
      {:ok,
       %{
         "merchant_id" => "MOCK_MERCHANT_#{random_id(8)}",
         "access_token" => "mock_token_#{random_id(32)}"
       }}
    else
      Req.post("#{base_url()}/oauth/token",
        json: %{
          client_id: app_id(),
          client_secret: app_secret(),
          code: code
        }
      )
      |> handle_response()
    end
  end

  # ── Merchant ───────────────────────────────────────────────────────────────

  @doc """
  Fetch merchant info (name, address, etc).
  """
  def get_merchant(merchant_id, access_token) do
    if mock_mode?() do
      {:ok,
       %{
         "id" => merchant_id,
         "name" => "Mock Restaurant",
         "address" => %{
           "address1" => "123 Main St",
           "city" => "Springfield",
           "state" => "IL",
           "zip" => "62701"
         }
       }}
    else
      get("/v3/merchants/#{merchant_id}", access_token)
    end
  end

  # ── Inventory ─────────────────────────────────────────────────────────────

  @doc """
  Fetch all inventory categories for a merchant.
  """
  def list_categories(merchant_id, access_token) do
    if mock_mode?() do
      {:ok, mock_categories()}
    else
      get("/v3/merchants/#{merchant_id}/categories?expand=items", access_token)
      |> unwrap_elements()
    end
  end

  @doc """
  Fetch all inventory items for a merchant.
  """
  def list_items(merchant_id, access_token) do
    if mock_mode?() do
      {:ok, mock_items()}
    else
      get(
        "/v3/merchants/#{merchant_id}/items?expand=categories,modifierGroups",
        access_token
      )
      |> unwrap_elements()
    end
  end

  @doc """
  Fetch all modifier groups for a merchant.
  """
  def list_modifier_groups(merchant_id, access_token) do
    if mock_mode?() do
      {:ok, mock_modifier_groups()}
    else
      get("/v3/merchants/#{merchant_id}/modifier_groups?expand=modifiers", access_token)
      |> unwrap_elements()
    end
  end

  @doc """
  Fetch item stock/availability.
  """
  def get_item_stock(merchant_id, item_id, access_token) do
    if mock_mode?() do
      {:ok, %{"quantity" => 10, "quantityInStock" => 10}}
    else
      get("/v3/merchants/#{merchant_id}/item_stocks/#{item_id}", access_token)
    end
  end

  @doc """
  Fetch all item stocks in bulk.
  """
  def list_item_stocks(merchant_id, access_token) do
    if mock_mode?() do
      {:ok, mock_item_stocks()}
    else
      get("/v3/merchants/#{merchant_id}/item_stocks", access_token)
      |> unwrap_elements()
    end
  end

  # ── Orders ────────────────────────────────────────────────────────────────

  @doc """
  Push an order to Clover using the Atomic Orders API.
  Returns {:ok, %{"id" => clover_order_id}} or {:error, reason}.
  """
  def create_atomic_order(merchant_id, access_token, order_payload) do
    if mock_mode?() do
      {:ok,
       %{
         "id" => "MOCK_ORDER_#{random_id(12)}",
         "total" => order_payload[:total] || 0,
         "state" => "open"
       }}
    else
      Req.post(
        "#{base_url()}/v3/merchants/#{merchant_id}/atomic_order/orders",
        headers: [{"Authorization", "Bearer #{access_token}"}],
        json: order_payload
      )
      |> handle_response()
    end
  end

  @doc """
  Fetch a Clover order by ID.
  """
  def get_order(merchant_id, clover_order_id, access_token) do
    if mock_mode?() do
      {:ok,
       %{
         "id" => clover_order_id,
         "total" => 1000,
         "state" => "open"
       }}
    else
      get("/v3/merchants/#{merchant_id}/orders/#{clover_order_id}", access_token)
    end
  end

  # ── Payments (Reconciliation) ─────────────────────────────────────────────

  @doc """
  List payments for a merchant (for reconciliation).
  """
  def list_payments(merchant_id, access_token, opts \\ []) do
    if mock_mode?() do
      {:ok, mock_payments()}
    else
      params =
        opts
        |> Keyword.take([:limit, :offset, :filter])
        |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
        |> Enum.join("&")

      path =
        if params != "",
          do: "/v3/merchants/#{merchant_id}/payments?#{params}",
          else: "/v3/merchants/#{merchant_id}/payments"

      get(path, access_token)
      |> unwrap_elements()
    end
  end

  # ── HTTP Helpers ───────────────────────────────────────────────────────────

  defp get(path, access_token) do
    Req.get("#{base_url()}#{path}",
      headers: [{"Authorization", "Bearer #{access_token}"}]
    )
    |> handle_response()
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, %{status: status, body: body}}
  end

  defp handle_response({:error, exception}) do
    {:error, Exception.message(exception)}
  end

  defp unwrap_elements({:ok, %{"elements" => elements}}), do: {:ok, elements}
  defp unwrap_elements({:ok, data}) when is_list(data), do: {:ok, data}
  defp unwrap_elements(result), do: result

  # ── Mock Data ─────────────────────────────────────────────────────────────

  defp mock_categories do
    [
      %{
        "id" => "CAT_APPETIZERS",
        "name" => "Appetizers",
        "sortOrder" => 0
      },
      %{
        "id" => "CAT_MAINS",
        "name" => "Main Courses",
        "sortOrder" => 1
      },
      %{
        "id" => "CAT_DRINKS",
        "name" => "Drinks",
        "sortOrder" => 2
      },
      %{
        "id" => "CAT_DESSERTS",
        "name" => "Desserts",
        "sortOrder" => 3
      }
    ]
  end

  defp mock_items do
    [
      %{
        "id" => "ITEM_NACHOS",
        "name" => "Nachos",
        "price" => 899,
        "description" => "Loaded nachos with cheese, jalapeños, and sour cream",
        "available" => true,
        "categories" => %{"elements" => [%{"id" => "CAT_APPETIZERS"}]},
        "modifierGroups" => %{"elements" => [%{"id" => "MG_TOPPINGS"}]}
      },
      %{
        "id" => "ITEM_BURGER",
        "name" => "Classic Burger",
        "price" => 1299,
        "description" => "8oz beef patty with lettuce, tomato, onion",
        "available" => true,
        "categories" => %{"elements" => [%{"id" => "CAT_MAINS"}]},
        "modifierGroups" => %{"elements" => [%{"id" => "MG_SIZE"}, %{"id" => "MG_TOPPINGS"}]}
      },
      %{
        "id" => "ITEM_PIZZA",
        "name" => "Margherita Pizza",
        "price" => 1599,
        "description" => "Fresh mozzarella, tomato sauce, basil",
        "available" => true,
        "categories" => %{"elements" => [%{"id" => "CAT_MAINS"}]},
        "modifierGroups" => %{"elements" => [%{"id" => "MG_SIZE"}]}
      },
      %{
        "id" => "ITEM_COLA",
        "name" => "Soft Drink",
        "price" => 299,
        "description" => "Coke, Sprite, or Dr Pepper",
        "available" => true,
        "categories" => %{"elements" => [%{"id" => "CAT_DRINKS"}]},
        "modifierGroups" => %{"elements" => []}
      },
      %{
        "id" => "ITEM_CAKE",
        "name" => "Chocolate Lava Cake",
        "price" => 699,
        "description" => "Warm chocolate cake with vanilla ice cream",
        "available" => true,
        "categories" => %{"elements" => [%{"id" => "CAT_DESSERTS"}]},
        "modifierGroups" => %{"elements" => []}
      }
    ]
  end

  defp mock_modifier_groups do
    [
      %{
        "id" => "MG_SIZE",
        "name" => "Size",
        "modifiers" => %{
          "elements" => [
            %{"id" => "MOD_SMALL", "name" => "Small", "price" => -200},
            %{"id" => "MOD_MEDIUM", "name" => "Medium", "price" => 0},
            %{"id" => "MOD_LARGE", "name" => "Large", "price" => 200}
          ]
        }
      },
      %{
        "id" => "MG_TOPPINGS",
        "name" => "Extra Toppings",
        "modifiers" => %{
          "elements" => [
            %{"id" => "MOD_CHEESE", "name" => "Extra Cheese", "price" => 150},
            %{"id" => "MOD_BACON", "name" => "Bacon", "price" => 200},
            %{"id" => "MOD_AVOCADO", "name" => "Avocado", "price" => 175}
          ]
        }
      }
    ]
  end

  defp mock_item_stocks do
    [
      %{"item" => %{"id" => "ITEM_NACHOS"}, "quantity" => 10, "quantityInStock" => 10},
      %{"item" => %{"id" => "ITEM_BURGER"}, "quantity" => 8, "quantityInStock" => 8},
      %{"item" => %{"id" => "ITEM_PIZZA"}, "quantity" => 0, "quantityInStock" => 0},
      %{"item" => %{"id" => "ITEM_COLA"}, "quantity" => 50, "quantityInStock" => 50},
      %{"item" => %{"id" => "ITEM_CAKE"}, "quantity" => 5, "quantityInStock" => 5}
    ]
  end

  defp mock_payments do
    [
      %{
        "id" => "PAY_#{random_id(8)}",
        "amount" => 1499,
        "tipAmount" => 200,
        "order" => %{"id" => "MOCK_ORDER_001"},
        "result" => "SUCCESS",
        "createdTime" => System.os_time(:millisecond)
      },
      %{
        "id" => "PAY_#{random_id(8)}",
        "amount" => 2599,
        "tipAmount" => 300,
        "order" => %{"id" => "MOCK_ORDER_002"},
        "result" => "SUCCESS",
        "createdTime" => System.os_time(:millisecond)
      }
    ]
  end

  defp random_id(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode16(case: :lower)
    |> binary_part(0, length)
  end
end
