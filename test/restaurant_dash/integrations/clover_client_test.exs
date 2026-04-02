defmodule RestaurantDash.Integrations.Clover.ClientTest do
  use ExUnit.Case, async: true

  alias RestaurantDash.Integrations.Clover.Client

  describe "mock_mode?/0" do
    test "returns true in test environment (no API key configured)" do
      assert Client.mock_mode?() == true
    end
  end

  describe "app_id/0" do
    test "returns nil in test environment" do
      # In test env no CLOVER_APP_ID is set
      assert is_nil(Client.app_id()) or is_binary(Client.app_id())
    end
  end

  describe "authorization_url/1" do
    test "builds a URL with client_id and redirect_uri" do
      url = Client.authorization_url("https://example.com/callback")
      assert url =~ "redirect_uri="
      assert url =~ "oauth"
    end

    test "includes state when provided" do
      url = Client.authorization_url("https://example.com/callback", "my_state")
      assert url =~ "state=my_state"
    end
  end

  describe "exchange_code/1 (mock mode)" do
    test "returns merchant_id and access_token" do
      assert {:ok, result} = Client.exchange_code("fake_code")
      assert is_binary(result["merchant_id"])
      assert is_binary(result["access_token"])
      assert String.starts_with?(result["merchant_id"], "MOCK_MERCHANT_")
      assert String.starts_with?(result["access_token"], "mock_token_")
    end
  end

  describe "get_merchant/2 (mock mode)" do
    test "returns merchant info" do
      assert {:ok, merchant} = Client.get_merchant("MOCK_MID", "mock_token")
      assert merchant["id"] == "MOCK_MID"
      assert is_binary(merchant["name"])
    end
  end

  describe "list_categories/2 (mock mode)" do
    test "returns a list of categories" do
      assert {:ok, categories} = Client.list_categories("MOCK_MID", "mock_token")
      assert is_list(categories)
      assert length(categories) > 0
      first = List.first(categories)
      assert is_binary(first["id"])
      assert is_binary(first["name"])
    end
  end

  describe "list_items/2 (mock mode)" do
    test "returns a list of items with prices" do
      assert {:ok, items} = Client.list_items("MOCK_MID", "mock_token")
      assert is_list(items)
      assert length(items) > 0
      first = List.first(items)
      assert is_binary(first["name"])
      assert is_integer(first["price"])
    end

    test "items have category associations" do
      assert {:ok, items} = Client.list_items("MOCK_MID", "mock_token")
      assert Enum.all?(items, fn item -> is_map(item["categories"]) end)
    end
  end

  describe "list_modifier_groups/2 (mock mode)" do
    test "returns modifier groups with modifiers" do
      assert {:ok, groups} = Client.list_modifier_groups("MOCK_MID", "mock_token")
      assert is_list(groups)
      assert length(groups) > 0
      first = List.first(groups)
      assert is_binary(first["name"])
      modifiers = get_in(first, ["modifiers", "elements"])
      assert is_list(modifiers)
    end
  end

  describe "list_item_stocks/2 (mock mode)" do
    test "returns stock levels" do
      assert {:ok, stocks} = Client.list_item_stocks("MOCK_MID", "mock_token")
      assert is_list(stocks)
      assert length(stocks) > 0
      first = List.first(stocks)
      assert is_integer(first["quantity"])
    end

    test "includes zero-stock items (86'd)" do
      assert {:ok, stocks} = Client.list_item_stocks("MOCK_MID", "mock_token")
      # Margherita Pizza (ITEM_PIZZA) should have quantity 0
      pizza_stock = Enum.find(stocks, fn s -> get_in(s, ["item", "id"]) == "ITEM_PIZZA" end)
      assert pizza_stock != nil
      assert pizza_stock["quantity"] == 0
    end
  end

  describe "create_atomic_order/3 (mock mode)" do
    test "returns a clover order ID" do
      payload = %{"lineItems" => [], "total" => 1000}
      assert {:ok, order} = Client.create_atomic_order("MOCK_MID", "mock_token", payload)
      assert is_binary(order["id"])
      assert String.starts_with?(order["id"], "MOCK_ORDER_")
    end
  end

  describe "list_payments/2 (mock mode)" do
    test "returns payment records" do
      assert {:ok, payments} = Client.list_payments("MOCK_MID", "mock_token")
      assert is_list(payments)
      assert length(payments) > 0
      first = List.first(payments)
      assert is_integer(first["amount"])
    end
  end
end
