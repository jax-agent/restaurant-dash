defmodule RestaurantDash.Integrations.Square.Client do
  @moduledoc """
  Low-level Square REST API client using Req.
  Falls back to mock mode when no SQUARE_APP_SECRET is configured.

  All API calls require a merchant access token obtained via OAuth.
  Base URLs:
    Production: https://connect.squareup.com/v2
    Sandbox:    https://connect.squareupsandbox.com/v2

  Square OAuth:
    Production: https://connect.squareup.com/oauth2
    Sandbox:    https://connect.squareupsandbox.com/oauth2
  """

  @production_base "https://connect.squareup.com/v2"
  @sandbox_base "https://connect.squareupsandbox.com/v2"
  @production_oauth_base "https://connect.squareup.com/oauth2"
  @sandbox_oauth_base "https://connect.squareupsandbox.com/oauth2"

  # ── Config ─────────────────────────────────────────────────────────────────

  def app_id do
    Application.get_env(:restaurant_dash, :square, [])[:app_id]
  end

  def app_secret do
    Application.get_env(:restaurant_dash, :square, [])[:app_secret]
  end

  def mock_mode? do
    secret = app_secret()
    is_nil(secret) or secret == "" or secret == "square_mock"
  end

  def base_url do
    env = Application.get_env(:restaurant_dash, :square, [])[:env] || :sandbox

    case env do
      :production -> @production_base
      _ -> @sandbox_base
    end
  end

  def oauth_base_url do
    env = Application.get_env(:restaurant_dash, :square, [])[:env] || :sandbox

    case env do
      :production -> @production_oauth_base
      _ -> @sandbox_oauth_base
    end
  end

  # ── OAuth ──────────────────────────────────────────────────────────────────

  @doc """
  Build the Square OAuth authorization URL.
  Redirects the merchant to Square to authorize our app.
  """
  def authorization_url(redirect_uri, state \\ nil) do
    params = %{
      client_id: app_id(),
      redirect_uri: redirect_uri,
      response_type: "code",
      scope:
        "MERCHANT_PROFILE_READ ITEMS_READ ITEMS_WRITE ORDERS_READ ORDERS_WRITE PAYMENTS_WRITE INVENTORY_READ INVENTORY_WRITE"
    }

    params = if state, do: Map.put(params, :state, state), else: params
    query = URI.encode_query(params)
    "#{oauth_base_url()}/authorize?#{query}"
  end

  @doc """
  Exchange an authorization code for access + refresh tokens.
  Returns {:ok, token_data} or {:error, reason}.
  Token data includes: access_token, refresh_token, merchant_id, expires_at.
  """
  def exchange_code(code) do
    if mock_mode?() do
      {:ok,
       %{
         "access_token" => "mock_square_token_#{random_id(32)}",
         "refresh_token" => "mock_square_refresh_#{random_id(32)}",
         "merchant_id" => "MOCK_SQ_MERCHANT_#{random_id(8)}",
         "expires_at" =>
           DateTime.utc_now() |> DateTime.add(30 * 24 * 3600) |> DateTime.to_iso8601(),
         "token_type" => "bearer"
       }}
    else
      Req.post("#{oauth_base_url()}/token",
        json: %{
          client_id: app_id(),
          client_secret: app_secret(),
          code: code,
          grant_type: "authorization_code"
        }
      )
      |> handle_response()
    end
  end

  @doc """
  Refresh an access token using the refresh token.
  Returns {:ok, token_data} or {:error, reason}.
  """
  def refresh_token(refresh_token) do
    if mock_mode?() do
      {:ok,
       %{
         "access_token" => "mock_square_token_refreshed_#{random_id(32)}",
         "refresh_token" => "mock_square_refresh_new_#{random_id(32)}",
         "expires_at" =>
           DateTime.utc_now() |> DateTime.add(30 * 24 * 3600) |> DateTime.to_iso8601()
       }}
    else
      Req.post("#{oauth_base_url()}/token",
        headers: [
          {"Square-Version", square_version()},
          {"Authorization", "Client #{app_secret()}"}
        ],
        json: %{
          client_id: app_id(),
          grant_type: "refresh_token",
          refresh_token: refresh_token
        }
      )
      |> handle_response()
    end
  end

  # ── Merchant / Locations ───────────────────────────────────────────────────

  @doc """
  Fetch the merchant profile (name, etc).
  """
  def get_merchant(merchant_id, access_token) do
    if mock_mode?() do
      {:ok,
       %{
         "merchant" => %{
           "id" => merchant_id,
           "business_name" => "Mock Square Restaurant",
           "country" => "US",
           "language_code" => "en-US",
           "currency" => "USD",
           "status" => "ACTIVE"
         }
       }}
    else
      get("/merchants/#{merchant_id}", access_token)
    end
  end

  @doc """
  List locations for a merchant (needed to push orders to a specific location).
  """
  def list_locations(access_token) do
    if mock_mode?() do
      {:ok,
       %{
         "locations" => [
           %{
             "id" => "MOCK_LOCATION_#{random_id(8)}",
             "name" => "Main Location",
             "status" => "ACTIVE",
             "address" => %{
               "address_line_1" => "123 Main St",
               "locality" => "Springfield",
               "administrative_district_level_1" => "IL",
               "postal_code" => "62701",
               "country" => "US"
             }
           }
         ]
       }}
    else
      get("/locations", access_token)
    end
  end

  # ── Catalog ───────────────────────────────────────────────────────────────

  @doc """
  List all catalog objects of specific types.
  Types: CATEGORY, ITEM, MODIFIER_LIST
  Returns paginated results — we collect all pages.
  """
  def list_catalog(access_token, types \\ ["CATEGORY", "ITEM", "MODIFIER_LIST"]) do
    if mock_mode?() do
      {:ok, mock_catalog()}
    else
      list_catalog_page(access_token, types, nil, [])
    end
  end

  defp list_catalog_page(access_token, types, cursor, acc) do
    params = %{types: Enum.join(types, ",")}
    params = if cursor, do: Map.put(params, :cursor, cursor), else: params
    query = URI.encode_query(params)

    case get("/catalog/list?#{query}", access_token) do
      {:ok, %{"objects" => objects, "cursor" => next_cursor}} when not is_nil(next_cursor) ->
        list_catalog_page(access_token, types, next_cursor, acc ++ objects)

      {:ok, %{"objects" => objects}} ->
        {:ok, acc ++ objects}

      {:ok, _} ->
        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetch a single catalog object by ID.
  """
  def get_catalog_object(object_id, access_token) do
    if mock_mode?() do
      {:ok, %{"object" => %{"id" => object_id, "type" => "ITEM"}}}
    else
      get("/catalog/object/#{object_id}", access_token)
    end
  end

  # ── Inventory ─────────────────────────────────────────────────────────────

  @doc """
  Batch retrieve inventory counts for a list of catalog object IDs.
  """
  def batch_retrieve_inventory_counts(catalog_object_ids, location_id, access_token) do
    if mock_mode?() do
      {:ok, mock_inventory_counts(catalog_object_ids)}
    else
      body = %{
        catalog_object_ids: catalog_object_ids,
        location_ids: if(location_id, do: [location_id], else: []),
        states: ["IN_STOCK"]
      }

      post("/inventory/counts/batch-retrieve", body, access_token)
      |> case do
        {:ok, %{"counts" => counts}} -> {:ok, counts}
        {:ok, _} -> {:ok, []}
        error -> error
      end
    end
  end

  # ── Orders ────────────────────────────────────────────────────────────────

  @doc """
  Create an order in Square POS.
  Returns {:ok, order_data} or {:error, reason}.
  """
  def create_order(location_id, access_token, order_payload) do
    if mock_mode?() do
      {:ok,
       %{
         "order" => %{
           "id" => "MOCK_SQ_ORDER_#{random_id(12)}",
           "location_id" => location_id,
           "state" => "OPEN",
           "total_money" => %{
             "amount" => order_payload[:total_money][:amount] || 0,
             "currency" => "USD"
           }
         }
       }}
    else
      post("/orders", %{order: order_payload}, access_token)
    end
  end

  @doc """
  Retrieve an order by ID.
  """
  def get_order(order_id, access_token) do
    if mock_mode?() do
      {:ok,
       %{
         "order" => %{
           "id" => order_id,
           "state" => "OPEN",
           "total_money" => %{"amount" => 0, "currency" => "USD"}
         }
       }}
    else
      get("/orders/#{order_id}", access_token)
    end
  end

  # ── Payments ──────────────────────────────────────────────────────────────

  @doc """
  Create a payment using a source_id (from Square Web Payments SDK).
  Returns {:ok, payment_data} or {:error, reason}.
  """
  def create_payment(access_token, payment_params) do
    if mock_mode?() do
      {:ok,
       %{
         "payment" => %{
           "id" => "MOCK_SQ_PAYMENT_#{random_id(12)}",
           "status" => "COMPLETED",
           "amount_money" => %{
             "amount" => payment_params[:amount_money][:amount] || 0,
             "currency" => "USD"
           },
           "source_type" => "CARD"
         }
       }}
    else
      post("/payments", payment_params, access_token)
    end
  end

  # ── HTTP Helpers ───────────────────────────────────────────────────────────

  defp get(path, access_token) do
    Req.get("#{base_url()}#{path}",
      headers: [
        {"Authorization", "Bearer #{access_token}"},
        {"Square-Version", square_version()},
        {"Content-Type", "application/json"}
      ]
    )
    |> handle_response()
  end

  defp post(path, body, access_token) do
    Req.post("#{base_url()}#{path}",
      headers: [
        {"Authorization", "Bearer #{access_token}"},
        {"Square-Version", square_version()},
        {"Content-Type", "application/json"}
      ],
      json: body
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

  defp square_version, do: "2024-12-18"

  # ── Mock Data ─────────────────────────────────────────────────────────────

  defp mock_catalog do
    categories = [
      %{
        "type" => "CATEGORY",
        "id" => "SQ_CAT_APPETIZERS",
        "category_data" => %{
          "name" => "Appetizers"
        }
      },
      %{
        "type" => "CATEGORY",
        "id" => "SQ_CAT_MAINS",
        "category_data" => %{
          "name" => "Main Courses"
        }
      },
      %{
        "type" => "CATEGORY",
        "id" => "SQ_CAT_DRINKS",
        "category_data" => %{
          "name" => "Drinks"
        }
      },
      %{
        "type" => "CATEGORY",
        "id" => "SQ_CAT_DESSERTS",
        "category_data" => %{
          "name" => "Desserts"
        }
      }
    ]

    modifier_lists = [
      %{
        "type" => "MODIFIER_LIST",
        "id" => "SQ_ML_SIZE",
        "modifier_list_data" => %{
          "name" => "Size",
          "selection_type" => "SINGLE",
          "modifiers" => [
            %{
              "type" => "MODIFIER",
              "id" => "SQ_MOD_SMALL",
              "modifier_data" => %{
                "name" => "Small",
                "price_money" => %{"amount" => -200, "currency" => "USD"},
                "modifier_list_id" => "SQ_ML_SIZE"
              }
            },
            %{
              "type" => "MODIFIER",
              "id" => "SQ_MOD_MEDIUM",
              "modifier_data" => %{
                "name" => "Medium",
                "price_money" => %{"amount" => 0, "currency" => "USD"},
                "modifier_list_id" => "SQ_ML_SIZE"
              }
            },
            %{
              "type" => "MODIFIER",
              "id" => "SQ_MOD_LARGE",
              "modifier_data" => %{
                "name" => "Large",
                "price_money" => %{"amount" => 200, "currency" => "USD"},
                "modifier_list_id" => "SQ_ML_SIZE"
              }
            }
          ]
        }
      },
      %{
        "type" => "MODIFIER_LIST",
        "id" => "SQ_ML_TOPPINGS",
        "modifier_list_data" => %{
          "name" => "Extra Toppings",
          "selection_type" => "MULTIPLE",
          "modifiers" => [
            %{
              "type" => "MODIFIER",
              "id" => "SQ_MOD_CHEESE",
              "modifier_data" => %{
                "name" => "Extra Cheese",
                "price_money" => %{"amount" => 150, "currency" => "USD"},
                "modifier_list_id" => "SQ_ML_TOPPINGS"
              }
            },
            %{
              "type" => "MODIFIER",
              "id" => "SQ_MOD_BACON",
              "modifier_data" => %{
                "name" => "Bacon",
                "price_money" => %{"amount" => 200, "currency" => "USD"},
                "modifier_list_id" => "SQ_ML_TOPPINGS"
              }
            }
          ]
        }
      }
    ]

    items = [
      %{
        "type" => "ITEM",
        "id" => "SQ_ITEM_NACHOS",
        "item_data" => %{
          "name" => "Square Nachos",
          "description" => "Loaded nachos with cheese, jalapeños, and sour cream",
          "category_id" => "SQ_CAT_APPETIZERS",
          "modifier_list_info" => [
            %{"modifier_list_id" => "SQ_ML_TOPPINGS", "enabled" => true}
          ],
          "variations" => [
            %{
              "type" => "ITEM_VARIATION",
              "id" => "SQ_VAR_NACHOS_REG",
              "item_variation_data" => %{
                "item_id" => "SQ_ITEM_NACHOS",
                "name" => "Regular",
                "price_money" => %{"amount" => 899, "currency" => "USD"},
                "pricing_type" => "FIXED_PRICING"
              }
            }
          ]
        }
      },
      %{
        "type" => "ITEM",
        "id" => "SQ_ITEM_BURGER",
        "item_data" => %{
          "name" => "Square Burger",
          "description" => "8oz beef patty with lettuce, tomato, onion",
          "category_id" => "SQ_CAT_MAINS",
          "modifier_list_info" => [
            %{"modifier_list_id" => "SQ_ML_SIZE", "enabled" => true},
            %{"modifier_list_id" => "SQ_ML_TOPPINGS", "enabled" => true}
          ],
          "variations" => [
            %{
              "type" => "ITEM_VARIATION",
              "id" => "SQ_VAR_BURGER_SM",
              "item_variation_data" => %{
                "item_id" => "SQ_ITEM_BURGER",
                "name" => "Single",
                "price_money" => %{"amount" => 1299, "currency" => "USD"},
                "pricing_type" => "FIXED_PRICING"
              }
            },
            %{
              "type" => "ITEM_VARIATION",
              "id" => "SQ_VAR_BURGER_DBL",
              "item_variation_data" => %{
                "item_id" => "SQ_ITEM_BURGER",
                "name" => "Double",
                "price_money" => %{"amount" => 1699, "currency" => "USD"},
                "pricing_type" => "FIXED_PRICING"
              }
            }
          ]
        }
      },
      %{
        "type" => "ITEM",
        "id" => "SQ_ITEM_PIZZA",
        "item_data" => %{
          "name" => "Square Margherita Pizza",
          "description" => "Fresh mozzarella, tomato sauce, basil",
          "category_id" => "SQ_CAT_MAINS",
          "modifier_list_info" => [
            %{"modifier_list_id" => "SQ_ML_SIZE", "enabled" => true}
          ],
          "variations" => [
            %{
              "type" => "ITEM_VARIATION",
              "id" => "SQ_VAR_PIZZA",
              "item_variation_data" => %{
                "item_id" => "SQ_ITEM_PIZZA",
                "name" => "Regular",
                "price_money" => %{"amount" => 1599, "currency" => "USD"},
                "pricing_type" => "FIXED_PRICING"
              }
            }
          ]
        }
      },
      %{
        "type" => "ITEM",
        "id" => "SQ_ITEM_COLA",
        "item_data" => %{
          "name" => "Square Soft Drink",
          "description" => "Coke, Sprite, or Dr Pepper",
          "category_id" => "SQ_CAT_DRINKS",
          "modifier_list_info" => [],
          "variations" => [
            %{
              "type" => "ITEM_VARIATION",
              "id" => "SQ_VAR_COLA",
              "item_variation_data" => %{
                "item_id" => "SQ_ITEM_COLA",
                "name" => "Regular",
                "price_money" => %{"amount" => 299, "currency" => "USD"},
                "pricing_type" => "FIXED_PRICING"
              }
            }
          ]
        }
      }
    ]

    categories ++ modifier_lists ++ items
  end

  defp mock_inventory_counts(catalog_object_ids) do
    # Simulate most items in stock; pizza variation is out
    Enum.map(catalog_object_ids, fn id ->
      quantity =
        if String.contains?(id, "PIZZA") or String.contains?(id, "pizza") do
          "0"
        else
          "10"
        end

      %{
        "catalog_object_id" => id,
        "catalog_object_type" => "ITEM_VARIATION",
        "state" => "IN_STOCK",
        "location_id" => "MOCK_LOCATION",
        "quantity" => quantity,
        "calculated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    end)
  end

  defp random_id(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode16(case: :lower)
    |> binary_part(0, length)
  end
end
