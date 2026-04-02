defmodule RestaurantDash.PromotionsTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Promotions
  alias RestaurantDash.Promotions.PromoCode
  alias RestaurantDash.Tenancy

  @restaurant_attrs %{
    name: "Test Bistro",
    slug: "test-bistro-promos",
    timezone: "America/Chicago"
  }

  def restaurant_fixture do
    {:ok, r} = Tenancy.create_restaurant(@restaurant_attrs)
    r
  end

  def restaurant_fixture(attrs) do
    slug = "promo-restaurant-#{System.unique_integer([:positive])}"

    {:ok, r} =
      Tenancy.create_restaurant(
        Map.merge(%{name: "Test", slug: slug, timezone: "America/Chicago"}, attrs)
      )

    r
  end

  defp promo_attrs(restaurant_id, attrs \\ %{}) do
    Map.merge(
      %{
        restaurant_id: restaurant_id,
        code: "SAVE10",
        discount_type: "percentage",
        discount_value: 10
      },
      attrs
    )
  end

  describe "list_promo_codes/1" do
    test "returns promo codes for a restaurant" do
      restaurant = restaurant_fixture()
      {:ok, promo} = Promotions.create_promo_code(promo_attrs(restaurant.id))
      codes = Promotions.list_promo_codes(restaurant.id)
      assert Enum.any?(codes, &(&1.id == promo.id))
    end

    test "does not return promo codes from other restaurants" do
      r1 = restaurant_fixture(%{slug: "r1-promo-test"})
      r2 = restaurant_fixture(%{slug: "r2-promo-test"})
      {:ok, _} = Promotions.create_promo_code(promo_attrs(r1.id, %{code: "R1CODE"}))
      codes = Promotions.list_promo_codes(r2.id)
      refute Enum.any?(codes, &(&1.code == "R1CODE"))
    end
  end

  describe "create_promo_code/1" do
    test "creates a percentage discount" do
      restaurant = restaurant_fixture()

      assert {:ok, %PromoCode{} = promo} =
               Promotions.create_promo_code(promo_attrs(restaurant.id))

      assert promo.code == "SAVE10"
      assert promo.discount_type == "percentage"
      assert promo.discount_value == 10
      assert promo.is_active == true
      assert promo.current_uses == 0
    end

    test "creates a fixed discount" do
      restaurant = restaurant_fixture()

      assert {:ok, promo} =
               Promotions.create_promo_code(
                 promo_attrs(restaurant.id, %{
                   code: "FLAT5",
                   discount_type: "fixed",
                   discount_value: 500
                 })
               )

      assert promo.discount_type == "fixed"
      assert promo.discount_value == 500
    end

    test "upcases the code" do
      restaurant = restaurant_fixture()

      assert {:ok, promo} =
               Promotions.create_promo_code(promo_attrs(restaurant.id, %{code: "lowercase"}))

      assert promo.code == "LOWERCASE"
    end

    test "validates required fields" do
      assert {:error, changeset} = Promotions.create_promo_code(%{})

      assert %{restaurant_id: _, code: _, discount_type: _, discount_value: _} =
               errors_on(changeset)
    end

    test "rejects invalid discount_type" do
      restaurant = restaurant_fixture()

      assert {:error, changeset} =
               Promotions.create_promo_code(promo_attrs(restaurant.id, %{discount_type: "bogus"}))

      assert "is invalid" in errors_on(changeset).discount_type
    end

    test "rejects percentage > 100" do
      restaurant = restaurant_fixture()

      assert {:error, changeset} =
               Promotions.create_promo_code(
                 promo_attrs(restaurant.id, %{
                   discount_type: "percentage",
                   discount_value: 110
                 })
               )

      assert errors_on(changeset).discount_value != []
    end

    test "enforces unique code per restaurant" do
      restaurant = restaurant_fixture()
      {:ok, _} = Promotions.create_promo_code(promo_attrs(restaurant.id))
      assert {:error, changeset} = Promotions.create_promo_code(promo_attrs(restaurant.id))
      assert "has already been taken" in errors_on(changeset).code
    end

    test "allows same code for different restaurants" do
      r1 = restaurant_fixture(%{slug: "uniq-r1-promo"})
      r2 = restaurant_fixture(%{slug: "uniq-r2-promo"})
      assert {:ok, _} = Promotions.create_promo_code(promo_attrs(r1.id, %{code: "SHARED"}))
      assert {:ok, _} = Promotions.create_promo_code(promo_attrs(r2.id, %{code: "SHARED"}))
    end
  end

  describe "update_promo_code/2" do
    test "updates a promo code" do
      restaurant = restaurant_fixture()
      {:ok, promo} = Promotions.create_promo_code(promo_attrs(restaurant.id))
      assert {:ok, updated} = Promotions.update_promo_code(promo, %{discount_value: 20})
      assert updated.discount_value == 20
    end
  end

  describe "deactivate_promo_code/1" do
    test "deactivates a promo code" do
      restaurant = restaurant_fixture()
      {:ok, promo} = Promotions.create_promo_code(promo_attrs(restaurant.id))
      assert {:ok, deactivated} = Promotions.deactivate_promo_code(promo)
      assert deactivated.is_active == false
    end
  end

  describe "validate_promo_code/3" do
    test "returns ok for valid code" do
      restaurant = restaurant_fixture()
      {:ok, _} = Promotions.create_promo_code(promo_attrs(restaurant.id, %{code: "VALID10"}))
      assert {:ok, promo} = Promotions.validate_promo_code(restaurant.id, "VALID10", 1000)
      assert promo.code == "VALID10"
    end

    test "is case insensitive" do
      restaurant = restaurant_fixture()
      {:ok, _} = Promotions.create_promo_code(promo_attrs(restaurant.id, %{code: "CASETEST"}))
      assert {:ok, _} = Promotions.validate_promo_code(restaurant.id, "casetest", 1000)
    end

    test "returns error for unknown code" do
      restaurant = restaurant_fixture()
      assert {:error, msg} = Promotions.validate_promo_code(restaurant.id, "NOSUCHCODE", 1000)
      assert msg =~ "not found"
    end

    test "returns error for inactive code" do
      restaurant = restaurant_fixture()

      {:ok, promo} =
        Promotions.create_promo_code(
          promo_attrs(restaurant.id, %{code: "INACTIVE", is_active: false})
        )

      assert promo.is_active == false
      assert {:error, msg} = Promotions.validate_promo_code(restaurant.id, "INACTIVE", 1000)
      assert msg =~ "no longer active"
    end

    test "returns error for expired code" do
      restaurant = restaurant_fixture()
      past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

      {:ok, _} =
        Promotions.create_promo_code(
          promo_attrs(restaurant.id, %{code: "EXPIRED", expires_at: past})
        )

      assert {:error, msg} = Promotions.validate_promo_code(restaurant.id, "EXPIRED", 1000)
      assert msg =~ "expired"
    end

    test "returns error when max uses reached" do
      restaurant = restaurant_fixture()

      {:ok, promo} =
        Promotions.create_promo_code(
          promo_attrs(restaurant.id, %{code: "MAXUSED", max_uses: 2, current_uses: 2})
        )

      assert promo.current_uses == 2
      assert {:error, msg} = Promotions.validate_promo_code(restaurant.id, "MAXUSED", 1000)
      assert msg =~ "usage limit"
    end

    test "returns error when order below min_order" do
      restaurant = restaurant_fixture()

      {:ok, _} =
        Promotions.create_promo_code(
          promo_attrs(restaurant.id, %{code: "MINORDER", min_order: 2000})
        )

      assert {:error, msg} = Promotions.validate_promo_code(restaurant.id, "MINORDER", 1500)
      assert msg =~ "Minimum order"
    end

    test "succeeds when order meets min_order" do
      restaurant = restaurant_fixture()

      {:ok, _} =
        Promotions.create_promo_code(
          promo_attrs(restaurant.id, %{code: "MINOK", min_order: 1000})
        )

      assert {:ok, _} = Promotions.validate_promo_code(restaurant.id, "MINOK", 1500)
    end
  end

  describe "calculate_discount/2" do
    test "calculates percentage discount" do
      promo = %PromoCode{discount_type: "percentage", discount_value: 10}
      assert Promotions.calculate_discount(promo, 1000) == 100
    end

    test "calculates fixed discount" do
      promo = %PromoCode{discount_type: "fixed", discount_value: 500}
      assert Promotions.calculate_discount(promo, 2000) == 500
    end

    test "handles 20% on $50 order" do
      promo = %PromoCode{discount_type: "percentage", discount_value: 20}
      assert Promotions.calculate_discount(promo, 5000) == 1000
    end
  end

  describe "increment_usage/1" do
    test "increments current_uses" do
      restaurant = restaurant_fixture()
      {:ok, promo} = Promotions.create_promo_code(promo_attrs(restaurant.id, %{code: "INCTEST"}))
      assert promo.current_uses == 0
      assert {:ok, 1} = Promotions.increment_usage(promo)
      updated = Promotions.get_promo_code!(promo.id)
      assert updated.current_uses == 1
    end
  end
end
