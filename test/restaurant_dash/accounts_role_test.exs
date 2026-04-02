defmodule RestaurantDash.AccountsRoleTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Accounts
  alias RestaurantDash.Accounts.User
  alias RestaurantDash.Tenancy

  @restaurant_attrs %{
    name: "Test Restaurant",
    slug: "test-restaurant"
  }

  @valid_user_attrs %{
    email: "owner@example.com",
    password: "hello world!"
  }

  describe "register_user_with_role/1" do
    test "creates a user with default customer role" do
      assert {:ok, %User{} = user} = Accounts.register_user_with_role(@valid_user_attrs)
      assert user.role == "customer"
    end

    test "creates an owner user" do
      {:ok, restaurant} = Tenancy.create_restaurant(@restaurant_attrs)

      attrs =
        Map.merge(@valid_user_attrs, %{
          role: "owner",
          restaurant_id: restaurant.id,
          name: "Jane Owner"
        })

      assert {:ok, %User{} = user} = Accounts.register_user_with_role(attrs)
      assert user.role == "owner"
      assert user.restaurant_id == restaurant.id
      assert user.name == "Jane Owner"
    end

    test "creates a staff user" do
      {:ok, restaurant} = Tenancy.create_restaurant(@restaurant_attrs)

      attrs =
        Map.merge(@valid_user_attrs, %{
          role: "staff",
          restaurant_id: restaurant.id
        })

      assert {:ok, %User{} = user} = Accounts.register_user_with_role(attrs)
      assert user.role == "staff"
    end

    test "rejects invalid role" do
      attrs = Map.put(@valid_user_attrs, :role, "superadmin")
      assert {:error, changeset} = Accounts.register_user_with_role(attrs)
      assert "must be one of: owner, staff, driver, customer" in errors_on(changeset).role
    end

    test "requires email" do
      attrs = Map.delete(@valid_user_attrs, :email)
      assert {:error, changeset} = Accounts.register_user_with_role(attrs)
      assert "can't be blank" in errors_on(changeset).email
    end

    test "requires password" do
      attrs = Map.delete(@valid_user_attrs, :password)
      assert {:error, changeset} = Accounts.register_user_with_role(attrs)
      assert "can't be blank" in errors_on(changeset).password
    end

    test "enforces minimum password length" do
      attrs = Map.put(@valid_user_attrs, :password, "short")
      assert {:error, changeset} = Accounts.register_user_with_role(attrs)
      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end
  end

  describe "User.valid_roles/0" do
    test "returns the valid roles list" do
      assert User.valid_roles() == ~w(owner staff driver customer)
    end
  end

  describe "role checks" do
    test "owner role is valid" do
      {:ok, restaurant} = Tenancy.create_restaurant(@restaurant_attrs)

      {:ok, user} =
        Accounts.register_user_with_role(%{
          email: "owner2@example.com",
          password: "hello world!",
          role: "owner",
          restaurant_id: restaurant.id
        })

      assert user.role == "owner"
    end

    test "driver role is valid" do
      {:ok, restaurant} = Tenancy.create_restaurant(@restaurant_attrs)

      {:ok, user} =
        Accounts.register_user_with_role(%{
          email: "driver@example.com",
          password: "hello world!",
          role: "driver",
          restaurant_id: restaurant.id
        })

      assert user.role == "driver"
    end
  end
end
