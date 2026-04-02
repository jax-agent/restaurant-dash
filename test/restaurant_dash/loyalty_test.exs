defmodule RestaurantDash.LoyaltyTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Loyalty
  alias RestaurantDash.Loyalty.{LoyaltyAccount, LoyaltyReward}
  alias RestaurantDash.Tenancy

  defp restaurant_fixture(slug \\ nil) do
    slug = slug || "loyalty-test-#{System.unique_integer([:positive])}"

    {:ok, r} =
      Tenancy.create_restaurant(%{name: "Loyalty Test", slug: slug, timezone: "America/Chicago"})

    r
  end

  defp reward_attrs(restaurant_id, attrs \\ %{}) do
    Map.merge(
      %{
        restaurant_id: restaurant_id,
        name: "Free Coffee",
        points_cost: 100,
        discount_value: 500
      },
      attrs
    )
  end

  describe "get_or_create_account/2" do
    test "creates an account if none exists" do
      restaurant = restaurant_fixture()

      assert {:ok, %LoyaltyAccount{} = account} =
               Loyalty.get_or_create_account(restaurant.id, "customer@example.com")

      assert account.customer_email == "customer@example.com"
      assert account.points_balance == 0
      assert account.total_points_earned == 0
    end

    test "returns existing account on second call" do
      restaurant = restaurant_fixture()
      {:ok, account1} = Loyalty.get_or_create_account(restaurant.id, "repeat@example.com")
      {:ok, account2} = Loyalty.get_or_create_account(restaurant.id, "repeat@example.com")
      assert account1.id == account2.id
    end

    test "lowercases email" do
      restaurant = restaurant_fixture()
      {:ok, account} = Loyalty.get_or_create_account(restaurant.id, "UPPER@EXAMPLE.COM")
      assert account.customer_email == "upper@example.com"
    end
  end

  describe "calculate_points_earned/2" do
    test "calculates points at default 1 per dollar" do
      # $10.00 order = 10 points
      assert Loyalty.calculate_points_earned(1000) == 10
    end

    test "calculates points at custom rate" do
      # $10.00 order at 2x rate = 20 points
      assert Loyalty.calculate_points_earned(1000, 2) == 20
    end

    test "truncates sub-dollar amounts" do
      # $1.99 = 1 point
      assert Loyalty.calculate_points_earned(199) == 1
    end

    test "zero for empty order" do
      assert Loyalty.calculate_points_earned(0) == 0
    end
  end

  describe "award_points/3" do
    test "creates account and awards points" do
      restaurant = restaurant_fixture()
      assert {:ok, account} = Loyalty.award_points(restaurant.id, "new@example.com", 50)
      assert account.points_balance == 50
      assert account.total_points_earned == 50
    end

    test "accumulates points" do
      restaurant = restaurant_fixture()
      Loyalty.award_points(restaurant.id, "loyal@example.com", 30)
      {:ok, account} = Loyalty.award_points(restaurant.id, "loyal@example.com", 20)
      assert account.points_balance == 50
      assert account.total_points_earned == 50
    end

    test "does nothing for 0 points" do
      restaurant = restaurant_fixture()
      assert {:ok, :no_points} = Loyalty.award_points(restaurant.id, "zero@example.com", 0)
    end
  end

  describe "rewards CRUD" do
    test "create_reward/1 creates a reward" do
      restaurant = restaurant_fixture()

      assert {:ok, %LoyaltyReward{} = reward} =
               Loyalty.create_reward(reward_attrs(restaurant.id))

      assert reward.name == "Free Coffee"
      assert reward.points_cost == 100
      assert reward.discount_value == 500
      assert reward.is_active == true
    end

    test "list_rewards/1 returns rewards for restaurant" do
      restaurant = restaurant_fixture()
      {:ok, reward} = Loyalty.create_reward(reward_attrs(restaurant.id))
      rewards = Loyalty.list_rewards(restaurant.id)
      assert Enum.any?(rewards, &(&1.id == reward.id))
    end

    test "list_active_rewards/1 excludes inactive" do
      restaurant = restaurant_fixture()
      {:ok, active} = Loyalty.create_reward(reward_attrs(restaurant.id, %{name: "Active"}))

      {:ok, inactive} =
        Loyalty.create_reward(reward_attrs(restaurant.id, %{name: "Inactive", is_active: false}))

      rewards = Loyalty.list_active_rewards(restaurant.id)
      assert Enum.any?(rewards, &(&1.id == active.id))
      refute Enum.any?(rewards, &(&1.id == inactive.id))
    end

    test "deactivate_reward/1 deactivates" do
      restaurant = restaurant_fixture()
      {:ok, reward} = Loyalty.create_reward(reward_attrs(restaurant.id))
      assert {:ok, r} = Loyalty.deactivate_reward(reward)
      assert r.is_active == false
    end
  end

  describe "validate_redemption/3" do
    test "succeeds with enough points" do
      restaurant = restaurant_fixture()
      {:ok, _} = Loyalty.award_points(restaurant.id, "rich@example.com", 200)
      {:ok, reward} = Loyalty.create_reward(reward_attrs(restaurant.id, %{points_cost: 100}))

      assert {:ok, ^reward} =
               Loyalty.validate_redemption(restaurant.id, "rich@example.com", reward.id)
    end

    test "fails with insufficient points" do
      restaurant = restaurant_fixture()
      {:ok, _} = Loyalty.award_points(restaurant.id, "poor@example.com", 50)
      {:ok, reward} = Loyalty.create_reward(reward_attrs(restaurant.id, %{points_cost: 100}))

      assert {:error, msg} =
               Loyalty.validate_redemption(restaurant.id, "poor@example.com", reward.id)

      assert msg =~ "Insufficient"
    end

    test "fails for no account" do
      restaurant = restaurant_fixture()
      {:ok, reward} = Loyalty.create_reward(reward_attrs(restaurant.id))

      assert {:error, _} =
               Loyalty.validate_redemption(restaurant.id, "nobody@example.com", reward.id)
    end

    test "fails for inactive reward" do
      restaurant = restaurant_fixture()
      {:ok, _} = Loyalty.award_points(restaurant.id, "has_points@example.com", 200)
      {:ok, reward} = Loyalty.create_reward(reward_attrs(restaurant.id, %{is_active: false}))

      assert {:error, msg} =
               Loyalty.validate_redemption(restaurant.id, "has_points@example.com", reward.id)

      assert msg =~ "no longer available"
    end

    test "fails for missing reward" do
      restaurant = restaurant_fixture()
      assert {:error, msg} = Loyalty.validate_redemption(restaurant.id, "x@example.com", 999_999)
      assert msg =~ "not found"
    end
  end

  describe "redeem_reward/3" do
    test "deducts points on redemption" do
      restaurant = restaurant_fixture()
      {:ok, _} = Loyalty.award_points(restaurant.id, "redeem@example.com", 200)
      {:ok, reward} = Loyalty.create_reward(reward_attrs(restaurant.id, %{points_cost: 100}))

      assert {:ok, ^reward} =
               Loyalty.redeem_reward(restaurant.id, "redeem@example.com", reward.id)

      account = Loyalty.get_account(restaurant.id, "redeem@example.com")
      assert account.points_balance == 100
      # total_points_earned should not decrease
      assert account.total_points_earned == 200
    end
  end

  describe "list_top_members/2" do
    test "returns members sorted by total points" do
      restaurant = restaurant_fixture()
      Loyalty.award_points(restaurant.id, "bronze@example.com", 10)
      Loyalty.award_points(restaurant.id, "gold@example.com", 100)
      Loyalty.award_points(restaurant.id, "silver@example.com", 50)

      members = Loyalty.list_top_members(restaurant.id)
      totals = Enum.map(members, & &1.total_points_earned)
      assert totals == Enum.sort(totals, :desc)
    end
  end
end
