defmodule RestaurantDash.Integrations.SquareTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Integrations.Square
  alias RestaurantDash.Tenancy
  alias RestaurantDash.Menu
  alias RestaurantDash.Orders

  setup do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Test Square Restaurant",
        slug: "test-square-restaurant"
      })

    %{restaurant: restaurant}
  end

  # ── Mock Mode ─────────────────────────────────────────────────────────────

  describe "mock_mode?/0" do
    test "is true in test environment" do
      assert Square.mock_mode?() == true
    end
  end

  # ── OAuth / Connect ────────────────────────────────────────────────────────

  describe "connected?/1" do
    test "returns false for restaurant with no Square credentials", %{restaurant: r} do
      refute Square.connected?(r)
    end

    test "returns true when both merchant_id and token are set", %{restaurant: r} do
      {:ok, r} =
        Square.save_square_credentials(r, "SQ_MERCH_123", "sq_token_abc", "sq_refresh_xyz")

      assert Square.connected?(r)
    end

    test "returns false with only merchant_id set", %{restaurant: r} do
      {:ok, r} = Square.save_square_credentials(r, "SQ_MERCH_123", nil, nil)
      refute Square.connected?(r)
    end
  end

  describe "connect/2 (mock mode)" do
    test "exchanges code and saves credentials including refresh token", %{restaurant: r} do
      assert {:ok, updated_r} = Square.connect(r, "fake_auth_code")
      assert is_binary(updated_r.square_merchant_id)
      assert is_binary(updated_r.square_access_token)
      assert is_binary(updated_r.square_refresh_token)
      assert %DateTime{} = updated_r.square_connected_at
      assert Square.connected?(updated_r)
    end

    test "fetches and saves location_id on connect", %{restaurant: r} do
      assert {:ok, updated_r} = Square.connect(r, "fake_auth_code")
      # In mock mode, location_id is fetched from mock list_locations
      assert is_binary(updated_r.square_location_id)
    end
  end

  describe "save_square_credentials/4" do
    test "saves all required fields", %{restaurant: r} do
      assert {:ok, updated} =
               Square.save_square_credentials(r, "SQ_MID_001", "SQ_TOKEN_XYZ", "SQ_REFRESH_ABC")

      assert updated.square_merchant_id == "SQ_MID_001"
      assert updated.square_access_token == "SQ_TOKEN_XYZ"
      assert updated.square_refresh_token == "SQ_REFRESH_ABC"
      assert %DateTime{} = updated.square_connected_at
    end

    test "saves optional location_id when provided", %{restaurant: r} do
      assert {:ok, updated} =
               Square.save_square_credentials(
                 r,
                 "SQ_MID_001",
                 "SQ_TOKEN_XYZ",
                 "SQ_REFRESH_ABC",
                 "LOC_123"
               )

      assert updated.square_location_id == "LOC_123"
    end
  end

  describe "disconnect/1" do
    test "clears all Square credentials", %{restaurant: r} do
      {:ok, connected} =
        Square.save_square_credentials(r, "SQ_MID_001", "SQ_TOKEN_XYZ", "SQ_REFRESH_ABC")

      assert Square.connected?(connected)

      assert {:ok, disconnected} = Square.disconnect(connected)
      refute Square.connected?(disconnected)
      assert is_nil(disconnected.square_merchant_id)
      assert is_nil(disconnected.square_access_token)
      assert is_nil(disconnected.square_refresh_token)
      assert is_nil(disconnected.square_location_id)
      assert is_nil(disconnected.square_connected_at)
    end
  end

  describe "refresh_access_token/1" do
    test "returns error when no refresh token stored", %{restaurant: r} do
      assert {:error, :no_refresh_token} = Square.refresh_access_token(r)
    end

    test "refreshes token and saves new credentials (mock mode)", %{restaurant: r} do
      {:ok, r} =
        Square.save_square_credentials(r, "SQ_MID", "SQ_OLD_TOKEN", "SQ_REFRESH_TOKEN")

      assert {:ok, updated_r} = Square.refresh_access_token(r)
      assert is_binary(updated_r.square_access_token)
      # New token should differ from old in mock mode (refreshed token)
      assert is_binary(updated_r.square_refresh_token)
    end
  end

  describe "get_merchant_info/1 (mock mode)" do
    test "returns merchant business_name", %{restaurant: r} do
      {:ok, r} = Square.save_square_credentials(r, "SQ_MERCH_999", "sq_token_abc", "refresh")
      assert {:ok, info} = Square.get_merchant_info(r)
      assert is_binary(info["business_name"])
    end
  end

  describe "authorization_url/1" do
    test "returns an OAuth URL pointing to Square" do
      url = Square.authorization_url("https://example.com/callback")
      assert is_binary(url)
      assert url =~ "authorize"
    end
  end

  # ── Menu Import (Slice 9.2) ────────────────────────────────────────────────

  describe "import_menu/2 (mock mode)" do
    setup %{restaurant: r} do
      {:ok, r} =
        Square.save_square_credentials(r, "SQ_IMPORT_MERCH", "sq_import_token", "sq_refresh")

      %{restaurant: r}
    end

    test "imports categories from Square catalog", %{restaurant: r} do
      assert {:ok, stats} = Square.import_menu(r)
      assert stats.categories > 0
      assert Menu.list_categories(r.id) |> length() == stats.categories
    end

    test "imports items from Square catalog", %{restaurant: r} do
      assert {:ok, stats} = Square.import_menu(r)
      assert stats.items > 0
      assert Menu.list_items(r.id) |> length() >= stats.items
    end

    test "imports modifier groups from MODIFIER_LIST objects", %{restaurant: r} do
      assert {:ok, stats} = Square.import_menu(r)
      assert stats.modifier_groups > 0
    end

    test "handles single-variation items (uses variation price as item price)", %{restaurant: r} do
      assert {:ok, _stats} = Square.import_menu(r)
      items = Menu.list_items(r.id)
      nachos = Enum.find(items, fn i -> String.contains?(i.name, "Nachos") end)
      assert nachos != nil
      # Mock nachos has single variation with price 899
      assert nachos.price == 899
    end

    test "handles multi-variation items (creates modifier group)", %{restaurant: r} do
      assert {:ok, _stats} = Square.import_menu(r)
      items = Menu.list_items(r.id)
      burger = Enum.find(items, fn i -> String.contains?(i.name, "Burger") end)
      assert burger != nil
      # Burger has 2 variations (Single/Double) → creates extra modifier group
      # Verify modifier groups for burger exist
      modifier_groups = Menu.list_modifier_groups(r.id)
      variation_mg = Enum.find(modifier_groups, fn mg -> String.contains?(mg.name, "Options") end)
      assert variation_mg != nil
    end

    test "merge mode skips existing items by name", %{restaurant: r} do
      assert {:ok, _stats1} = Square.import_menu(r, mode: :merge)
      first_item_count = Menu.list_items(r.id) |> length()

      assert {:ok, _stats2} = Square.import_menu(r, mode: :merge)
      second_item_count = Menu.list_items(r.id) |> length()

      assert second_item_count == first_item_count
    end

    test "overwrite mode creates new items", %{restaurant: r} do
      assert {:ok, _} = Square.import_menu(r, mode: :overwrite)
      count_after_first = Menu.list_items(r.id) |> length()
      assert count_after_first > 0
    end

    test "returns stats with all required keys", %{restaurant: r} do
      assert {:ok, stats} = Square.import_menu(r)
      assert Map.has_key?(stats, :categories)
      assert Map.has_key?(stats, :items)
      assert Map.has_key?(stats, :modifier_groups)
    end
  end

  # ── Order Mapping (Slice 9.3) ──────────────────────────────────────────────

  describe "build_square_order/2" do
    test "builds correct payload from order", %{restaurant: r} do
      {:ok, r} =
        Square.save_square_credentials(
          r,
          "SQ_ORDER_MERCH",
          "sq_order_token",
          "sq_refresh",
          "SQ_LOC_1"
        )

      order = %RestaurantDash.Orders.Order{
        id: 99,
        customer_name: "Jane Square",
        customer_phone: "555-0200",
        delivery_address: "789 Oak Ave",
        total_amount: 2500,
        restaurant_id: r.id,
        order_items: []
      }

      payload = Square.build_square_order(order, r)
      assert is_map(payload)
      assert payload["location_id"] == "SQ_LOC_1"
      assert is_list(payload["line_items"])
      assert is_list(payload["fulfillments"])

      # Check fulfillment type
      [fulfillment] = payload["fulfillments"]
      assert fulfillment["type"] == "DELIVERY"

      assert get_in(fulfillment, ["delivery_details", "recipient", "display_name"]) ==
               "Jane Square"

      assert get_in(fulfillment, ["delivery_details", "recipient", "address", "address_line_1"]) ==
               "789 Oak Ave"
    end

    test "includes total_money in payload", %{restaurant: r} do
      {:ok, r} =
        Square.save_square_credentials(r, "SQ_TOT_MERCH", "sq_tot_token", "sq_refresh")

      order = %RestaurantDash.Orders.Order{
        id: 100,
        customer_name: "Bob",
        total_amount: 3000,
        restaurant_id: r.id,
        order_items: []
      }

      payload = Square.build_square_order(order, r)
      assert payload["total_money"]["amount"] == 3000
      assert payload["total_money"]["currency"] == "USD"
    end
  end

  describe "push_order/2 (mock mode)" do
    test "returns :not_connected when restaurant has no Square", %{restaurant: r} do
      {:ok, order} =
        Orders.create_order(%{
          customer_name: "Test Customer",
          items: ["Burger"],
          status: "new",
          restaurant_id: r.id,
          customer_email: "test@example.com",
          customer_phone: "555-0100",
          delivery_address: "123 Main St"
        })

      assert {:error, :not_connected} = Square.push_order(order, r)
    end

    test "pushes order and saves square_order_id (mock mode)", %{restaurant: r} do
      {:ok, r} =
        Square.save_square_credentials(
          r,
          "SQ_PUSH_MERCH",
          "sq_push_token",
          "sq_refresh",
          "SQ_PUSH_LOC"
        )

      {:ok, order} =
        Orders.create_order(%{
          customer_name: "Square Push Test",
          items: ["Pizza"],
          status: "new",
          restaurant_id: r.id,
          customer_email: "sq_push@example.com",
          customer_phone: "555-0201",
          delivery_address: "101 Square St"
        })

      assert {:ok, square_id} = Square.push_order(order, r)
      assert is_binary(square_id)
      assert String.starts_with?(square_id, "MOCK_SQ_ORDER_")

      # Verify square_order_id was saved to the order
      updated_order = Orders.get_order(order.id)
      assert updated_order.square_order_id == square_id
    end
  end

  # ── Inventory Sync (Slice 9.4) ─────────────────────────────────────────────

  describe "sync_inventory/1" do
    test "returns :not_connected error when not connected", %{restaurant: r} do
      assert {:error, :not_connected} = Square.sync_inventory(r)
    end

    test "syncs availability in mock mode", %{restaurant: r} do
      {:ok, r} =
        Square.save_square_credentials(r, "SQ_SYNC_MERCH", "sq_sync_token", "sq_refresh")

      assert {:ok, result} = Square.sync_inventory(r)
      assert Map.has_key?(result, :updated)
      assert Map.has_key?(result, :skipped)
      assert is_integer(result.updated)
      assert is_integer(result.skipped)
    end

    test "marks pizza as unavailable in mock mode", %{restaurant: r} do
      {:ok, r} =
        Square.save_square_credentials(r, "SQ_SYNC2_MERCH", "sq_sync2_token", "sq_refresh")

      {:ok, cat} = Menu.create_category(%{name: "Mains SQ", restaurant_id: r.id})

      {:ok, pizza} =
        Menu.create_item(%{
          name: "Square Margherita Pizza",
          price: 1599,
          is_available: true,
          restaurant_id: r.id,
          menu_category_id: cat.id
        })

      assert pizza.is_available == true

      {:ok, result} = Square.sync_inventory(r)
      assert result.updated >= 0

      # Pizza should be marked unavailable (mock: pizza catalog id has quantity 0)
      updated_pizza = RestaurantDash.Repo.get!(RestaurantDash.Menu.Item, pizza.id)
      assert updated_pizza.is_available == false
    end
  end

  # ── Payments (Slice 9.5) ───────────────────────────────────────────────────

  describe "payment_provider/1" do
    test "returns :stripe when restaurant has no Square connection", %{restaurant: r} do
      assert Square.payment_provider(r) == :stripe
    end

    test "returns :square when restaurant has Square connected", %{restaurant: r} do
      {:ok, r} =
        Square.save_square_credentials(r, "SQ_PAY_MERCH", "sq_pay_token", "sq_refresh")

      assert Square.payment_provider(r) == :square
    end
  end

  describe "create_payment/2 (mock mode)" do
    test "returns :not_connected when restaurant has no Square", %{restaurant: r} do
      params = %{source_id: "cnon:card-nonce-ok", amount: 1500}
      assert {:error, :not_connected} = Square.create_payment(r, params)
    end

    test "creates payment in mock mode", %{restaurant: r} do
      {:ok, r} =
        Square.save_square_credentials(
          r,
          "SQ_PAY2_MERCH",
          "sq_pay2_token",
          "sq_refresh",
          "SQ_PAY_LOC"
        )

      params = %{
        source_id: "cnon:card-nonce-ok",
        amount: 1500,
        currency: "USD",
        idempotency_key: "test-idem-key-#{System.unique_integer([:positive])}"
      }

      assert {:ok, payment} = Square.create_payment(r, params)
      assert is_binary(payment["id"])
      assert String.starts_with?(payment["id"], "MOCK_SQ_PAYMENT_")
      assert payment["status"] == "COMPLETED"
    end
  end

  # ── Webhook Signature ──────────────────────────────────────────────────────

  describe "valid_webhook_signature?/3" do
    test "returns true in mock mode when no key configured" do
      assert Square.valid_webhook_signature?("body", "any_sig", nil) == true
      assert Square.valid_webhook_signature?("body", "any_sig", "") == true
    end

    test "validates correct HMAC-SHA256 signature" do
      body = ~s({"type":"inventory.count.updated"})
      key = "webhook_secret_key"
      sig = :crypto.mac(:hmac, :sha256, key, body) |> Base.encode64()
      assert Square.valid_webhook_signature?(body, sig, key) == true
    end

    test "rejects incorrect signature" do
      body = ~s({"type":"inventory.count.updated"})
      key = "webhook_secret_key"
      assert Square.valid_webhook_signature?(body, "wrong_sig", key) == false
    end
  end
end
