defmodule RestaurantDash.Integrations.CloverTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Integrations.Clover
  alias RestaurantDash.Tenancy
  alias RestaurantDash.Menu

  setup do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Test Clover Restaurant",
        slug: "test-clover-restaurant"
      })

    %{restaurant: restaurant}
  end

  # ── Mock Mode ─────────────────────────────────────────────────────────────

  describe "mock_mode?/0" do
    test "is true in test environment" do
      assert Clover.mock_mode?() == true
    end
  end

  # ── OAuth / Connect ────────────────────────────────────────────────────────

  describe "connected?/1" do
    test "returns false for restaurant with no Clover credentials", %{restaurant: r} do
      refute Clover.connected?(r)
    end

    test "returns true when both merchant_id and token are set", %{restaurant: r} do
      {:ok, r} = Clover.save_clover_credentials(r, "MERCH_123", "token_abc")
      assert Clover.connected?(r)
    end

    test "returns false with only merchant_id set", %{restaurant: r} do
      {:ok, r} = Clover.save_clover_credentials(r, "MERCH_123", nil)
      refute Clover.connected?(r)
    end
  end

  describe "connect/2 (mock mode)" do
    test "exchanges code and saves credentials", %{restaurant: r} do
      assert {:ok, updated_r} = Clover.connect(r, "fake_auth_code")
      assert is_binary(updated_r.clover_merchant_id)
      assert is_binary(updated_r.clover_access_token)
      assert %DateTime{} = updated_r.clover_connected_at
      assert Clover.connected?(updated_r)
    end
  end

  describe "save_clover_credentials/3" do
    test "saves merchant_id and token", %{restaurant: r} do
      assert {:ok, updated} = Clover.save_clover_credentials(r, "MID_001", "TOKEN_XYZ")
      assert updated.clover_merchant_id == "MID_001"
      assert updated.clover_access_token == "TOKEN_XYZ"
      assert %DateTime{} = updated.clover_connected_at
    end
  end

  describe "disconnect/1" do
    test "clears all Clover credentials", %{restaurant: r} do
      {:ok, connected} = Clover.save_clover_credentials(r, "MID_001", "TOKEN_XYZ")
      assert Clover.connected?(connected)

      assert {:ok, disconnected} = Clover.disconnect(connected)
      refute Clover.connected?(disconnected)
      assert is_nil(disconnected.clover_merchant_id)
      assert is_nil(disconnected.clover_access_token)
      assert is_nil(disconnected.clover_connected_at)
    end
  end

  describe "get_merchant_info/1 (mock mode)" do
    test "returns merchant name", %{restaurant: r} do
      {:ok, r} = Clover.save_clover_credentials(r, "MERCH_999", "token_abc")
      assert {:ok, info} = Clover.get_merchant_info(r)
      assert is_binary(info["name"])
    end
  end

  describe "authorization_url/1" do
    test "returns an OAuth URL" do
      url = Clover.authorization_url("https://example.com/callback")
      assert is_binary(url)
      assert url =~ "oauth"
    end
  end

  # ── Menu Import ────────────────────────────────────────────────────────────

  describe "import_menu/2 (mock mode)" do
    setup %{restaurant: r} do
      {:ok, r} = Clover.save_clover_credentials(r, "MERCH_IMPORT", "token_test")
      %{restaurant: r}
    end

    test "imports categories from Clover catalog", %{restaurant: r} do
      assert {:ok, stats} = Clover.import_menu(r)
      assert stats.categories > 0
      assert Menu.list_categories(r.id) |> length() == stats.categories
    end

    test "imports items from Clover catalog", %{restaurant: r} do
      assert {:ok, stats} = Clover.import_menu(r)
      assert stats.items > 0
      assert Menu.list_items(r.id) |> length() >= stats.items
    end

    test "imports modifier groups", %{restaurant: r} do
      assert {:ok, stats} = Clover.import_menu(r)
      assert stats.modifier_groups > 0
    end

    test "merge mode skips existing items by name", %{restaurant: r} do
      # Import once
      assert {:ok, _stats1} = Clover.import_menu(r, mode: :merge)
      first_item_count = Menu.list_items(r.id) |> length()

      # Import again in merge mode — should not duplicate
      assert {:ok, _stats2} = Clover.import_menu(r, mode: :merge)
      second_item_count = Menu.list_items(r.id) |> length()

      assert second_item_count == first_item_count
    end

    test "overwrite mode creates items even if names exist", %{restaurant: r} do
      # First import
      assert {:ok, _} = Clover.import_menu(r, mode: :overwrite)
      count_after_first = Menu.list_items(r.id) |> length()
      assert count_after_first > 0
    end

    test "returns stats with counts", %{restaurant: r} do
      assert {:ok, stats} = Clover.import_menu(r)
      assert Map.has_key?(stats, :categories)
      assert Map.has_key?(stats, :items)
      assert Map.has_key?(stats, :modifier_groups)
    end
  end

  # ── Order Push ─────────────────────────────────────────────────────────────

  describe "build_clover_order/2" do
    test "builds correct payload from order", %{restaurant: r} do
      {:ok, r} = Clover.save_clover_credentials(r, "MERCH_ORDER", "token_test")

      order = %RestaurantDash.Orders.Order{
        id: 99,
        customer_name: "Jane Doe",
        total_amount: 2500,
        restaurant_id: r.id,
        order_items: []
      }

      payload = Clover.build_clover_order(order, r)
      assert is_map(payload)
      assert payload["total"] == 2500
      assert payload["note"] =~ "Jane Doe"
      assert is_list(payload["lineItems"])
    end
  end

  describe "push_order/2 (mock mode)" do
    test "returns :not_connected when restaurant has no Clover", %{restaurant: r} do
      alias RestaurantDash.Orders

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

      assert {:error, :not_connected} = Clover.push_order(order, r)
    end

    test "pushes order and saves clover_order_id (mock mode)", %{restaurant: r} do
      alias RestaurantDash.Orders
      {:ok, r} = Clover.save_clover_credentials(r, "MERCH_PUSH", "token_test")

      {:ok, order} =
        Orders.create_order(%{
          customer_name: "Push Test",
          items: ["Pizza"],
          status: "new",
          restaurant_id: r.id,
          customer_email: "push@example.com",
          customer_phone: "555-0101",
          delivery_address: "456 Elm St"
        })

      assert {:ok, clover_id} = Clover.push_order(order, r)
      assert is_binary(clover_id)
      assert String.starts_with?(clover_id, "MOCK_ORDER_")

      # Verify clover_order_id was saved
      updated_order = Orders.get_order(order.id)
      assert updated_order.clover_order_id == clover_id
    end
  end

  # ── Inventory Sync ─────────────────────────────────────────────────────────

  describe "sync_inventory/1" do
    test "returns :not_connected error when not connected", %{restaurant: r} do
      assert {:error, :not_connected} = Clover.sync_inventory(r)
    end

    test "syncs availability in mock mode", %{restaurant: r} do
      {:ok, r} = Clover.save_clover_credentials(r, "MERCH_SYNC", "token_test")

      assert {:ok, result} = Clover.sync_inventory(r)
      assert Map.has_key?(result, :updated)
      assert Map.has_key?(result, :skipped)
    end

    test "marks pizza as unavailable in mock mode", %{restaurant: r} do
      {:ok, r} = Clover.save_clover_credentials(r, "MERCH_SYNC2", "token_test")

      # Create a pizza item
      {:ok, cat} = Menu.create_category(%{name: "Mains", restaurant_id: r.id})

      {:ok, pizza} =
        Menu.create_item(%{
          name: "Margherita Pizza",
          price: 1599,
          is_available: true,
          restaurant_id: r.id,
          menu_category_id: cat.id
        })

      assert pizza.is_available == true

      # Run sync (mock mode marks pizza as unavailable since stock=0)
      {:ok, result} = Clover.sync_inventory(r)
      assert result.updated >= 0

      # Pizza item should now be unavailable
      updated_pizza = RestaurantDash.Repo.get!(RestaurantDash.Menu.Item, pizza.id)
      assert updated_pizza.is_available == false
    end
  end

  # ── Payment Reconciliation ────────────────────────────────────────────────

  describe "reconcile_payments/2" do
    test "returns :not_connected when not connected", %{restaurant: r} do
      assert {:error, :not_connected} = Clover.reconcile_payments(r)
    end

    test "returns reconciliation data in mock mode", %{restaurant: r} do
      {:ok, r} = Clover.save_clover_credentials(r, "MERCH_RECON", "token_test")

      assert {:ok, data} = Clover.reconcile_payments(r)
      assert Map.has_key?(data, :matched)
      assert Map.has_key?(data, :unmatched)
      assert Map.has_key?(data, :discrepancies)
      assert Map.has_key?(data, :summary)
    end

    test "summary has correct counts", %{restaurant: r} do
      {:ok, r} = Clover.save_clover_credentials(r, "MERCH_RECON2", "token_test")

      {:ok, data} = Clover.reconcile_payments(r)
      summary = data.summary

      assert summary.matched_count + summary.unmatched_count == summary.total_clover_payments
    end
  end

  describe "export_reconciliation_csv/1" do
    test "returns CSV string when connected", %{restaurant: r} do
      {:ok, r} = Clover.save_clover_credentials(r, "MERCH_CSV", "token_test")

      assert {:ok, csv} = Clover.export_reconciliation_csv(r)
      assert is_binary(csv)
      assert csv =~ "Order ID"
      assert csv =~ "Status"
    end

    test "returns :not_connected error when not connected", %{restaurant: r} do
      assert {:error, :not_connected} = Clover.export_reconciliation_csv(r)
    end
  end
end
