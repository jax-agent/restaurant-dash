defmodule RestaurantDash.Integrations.Square.ClientTest do
  use ExUnit.Case, async: true

  alias RestaurantDash.Integrations.Square.Client

  describe "mock_mode?/0" do
    test "returns true in test environment (no API key configured)" do
      assert Client.mock_mode?() == true
    end
  end

  describe "app_id/0" do
    test "returns nil or a string in test environment" do
      assert is_nil(Client.app_id()) or is_binary(Client.app_id())
    end
  end

  describe "authorization_url/1" do
    test "builds a URL with client_id and redirect_uri" do
      url = Client.authorization_url("https://example.com/callback")
      assert url =~ "redirect_uri="
      assert url =~ "authorize"
    end

    test "includes required Square scopes" do
      url = Client.authorization_url("https://example.com/callback")
      assert url =~ "scope="
    end

    test "includes state when provided" do
      url = Client.authorization_url("https://example.com/callback", "my_state")
      assert url =~ "state=my_state"
    end
  end

  describe "exchange_code/1 (mock mode)" do
    test "returns access_token, refresh_token, and merchant_id" do
      assert {:ok, result} = Client.exchange_code("fake_code")
      assert is_binary(result["access_token"])
      assert is_binary(result["refresh_token"])
      assert is_binary(result["merchant_id"])
      assert String.starts_with?(result["access_token"], "mock_square_token_")
      assert String.starts_with?(result["refresh_token"], "mock_square_refresh_")
      assert String.starts_with?(result["merchant_id"], "MOCK_SQ_MERCHANT_")
    end

    test "returns expires_at timestamp" do
      assert {:ok, result} = Client.exchange_code("fake_code")
      assert is_binary(result["expires_at"])
    end
  end

  describe "refresh_token/1 (mock mode)" do
    test "returns new access_token and refresh_token" do
      assert {:ok, result} = Client.refresh_token("mock_refresh_token")
      assert is_binary(result["access_token"])
      assert is_binary(result["refresh_token"])
    end
  end

  describe "get_merchant/2 (mock mode)" do
    test "returns merchant info with business_name" do
      assert {:ok, result} = Client.get_merchant("MOCK_MID", "mock_token")
      assert %{"merchant" => merchant} = result
      assert merchant["id"] == "MOCK_MID"
      assert is_binary(merchant["business_name"])
    end
  end

  describe "list_locations/1 (mock mode)" do
    test "returns a list of locations" do
      assert {:ok, result} = Client.list_locations("mock_token")
      assert %{"locations" => locations} = result
      assert is_list(locations)
      assert length(locations) > 0
      first = List.first(locations)
      assert is_binary(first["id"])
      assert is_binary(first["name"])
    end
  end

  describe "list_catalog/2 (mock mode)" do
    test "returns a list of catalog objects" do
      assert {:ok, objects} = Client.list_catalog("mock_token")
      assert is_list(objects)
      assert length(objects) > 0
    end

    test "includes CATEGORY, ITEM, and MODIFIER_LIST types" do
      assert {:ok, objects} = Client.list_catalog("mock_token")
      types = Enum.map(objects, & &1["type"]) |> Enum.uniq() |> Enum.sort()
      assert "CATEGORY" in types
      assert "ITEM" in types
      assert "MODIFIER_LIST" in types
    end

    test "ITEM objects have variations" do
      assert {:ok, objects} = Client.list_catalog("mock_token")
      items = Enum.filter(objects, &(&1["type"] == "ITEM"))
      assert length(items) > 0

      Enum.each(items, fn item ->
        variations = get_in(item, ["item_data", "variations"]) || []
        assert length(variations) > 0, "Item #{item["id"]} has no variations"
      end)
    end

    test "ITEM variations have price_money" do
      assert {:ok, objects} = Client.list_catalog("mock_token")
      items = Enum.filter(objects, &(&1["type"] == "ITEM"))

      Enum.each(items, fn item ->
        variations = get_in(item, ["item_data", "variations"]) || []

        Enum.each(variations, fn var ->
          price = get_in(var, ["item_variation_data", "price_money", "amount"])
          assert is_integer(price), "Variation #{var["id"]} missing price"
        end)
      end)
    end

    test "MODIFIER_LIST objects have nested modifiers" do
      assert {:ok, objects} = Client.list_catalog("mock_token")
      mls = Enum.filter(objects, &(&1["type"] == "MODIFIER_LIST"))
      assert length(mls) > 0

      Enum.each(mls, fn ml ->
        modifiers = get_in(ml, ["modifier_list_data", "modifiers"]) || []
        assert length(modifiers) > 0, "ModifierList #{ml["id"]} has no modifiers"
      end)
    end
  end

  describe "batch_retrieve_inventory_counts/3 (mock mode)" do
    test "returns inventory counts for each catalog object ID" do
      ids = ["SQ_VAR_PIZZA", "SQ_VAR_BURGER", "SQ_VAR_NACHOS"]
      assert {:ok, counts} = Client.batch_retrieve_inventory_counts(ids, "LOC_1", "mock_token")
      assert is_list(counts)
      assert length(counts) == length(ids)
    end

    test "pizza variation has zero quantity (86'd)" do
      ids = ["SQ_VAR_PIZZA"]
      assert {:ok, counts} = Client.batch_retrieve_inventory_counts(ids, "LOC_1", "mock_token")
      pizza = List.first(counts)
      assert pizza["quantity"] == "0"
    end

    test "non-pizza items have positive quantity" do
      ids = ["SQ_VAR_BURGER"]
      assert {:ok, counts} = Client.batch_retrieve_inventory_counts(ids, "LOC_1", "mock_token")
      burger = List.first(counts)
      {qty, _} = Float.parse(burger["quantity"])
      assert qty > 0
    end

    test "returns empty list when given empty ids" do
      assert {:ok, counts} = Client.batch_retrieve_inventory_counts([], "LOC_1", "mock_token")
      assert counts == []
    end
  end

  describe "create_order/3 (mock mode)" do
    test "returns a Square order ID" do
      payload = %{"line_items" => [], "total_money" => %{"amount" => 1000, "currency" => "USD"}}
      assert {:ok, result} = Client.create_order("LOC_1", "mock_token", payload)
      assert %{"order" => order} = result
      assert is_binary(order["id"])
      assert String.starts_with?(order["id"], "MOCK_SQ_ORDER_")
      assert order["state"] == "OPEN"
    end
  end

  describe "create_payment/2 (mock mode)" do
    test "returns a completed payment" do
      params = %{
        source_id: "cnon:card-nonce-ok",
        idempotency_key: "test-key-123",
        amount_money: %{amount: 1500, currency: "USD"}
      }

      assert {:ok, result} = Client.create_payment("mock_token", params)
      assert %{"payment" => payment} = result
      assert is_binary(payment["id"])
      assert String.starts_with?(payment["id"], "MOCK_SQ_PAYMENT_")
      assert payment["status"] == "COMPLETED"
    end
  end
end
