defmodule RestaurantDashWeb.PublicMenuLiveTest do
  use RestaurantDashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias RestaurantDash.{Menu, Tenancy}

  defp create_restaurant_with_menu do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Menu Display Test",
        slug: "menu-display-#{System.unique_integer([:positive])}",
        primary_color: "#E63946"
      })

    {:ok, cat1} =
      Menu.create_category(%{
        restaurant_id: restaurant.id,
        name: "Starters",
        position: 10,
        is_active: true
      })

    {:ok, cat2} =
      Menu.create_category(%{
        restaurant_id: restaurant.id,
        name: "Mains",
        position: 20,
        is_active: true
      })

    {:ok, _hidden_cat} =
      Menu.create_category(%{
        restaurant_id: restaurant.id,
        name: "Hidden Category",
        is_active: false
      })

    {:ok, item1} =
      Menu.create_item(%{
        restaurant_id: restaurant.id,
        menu_category_id: cat1.id,
        name: "Bruschetta",
        description: "Toasted bread with tomato",
        price: 799,
        is_active: true,
        is_available: true
      })

    {:ok, sold_out} =
      Menu.create_item(%{
        restaurant_id: restaurant.id,
        menu_category_id: cat1.id,
        name: "Sold Out Item",
        price: 999,
        is_active: true,
        is_available: false
      })

    {:ok, _hidden_item} =
      Menu.create_item(%{
        restaurant_id: restaurant.id,
        menu_category_id: cat2.id,
        name: "Hidden Item",
        price: 1599,
        is_active: false,
        is_available: true
      })

    {:ok, main} =
      Menu.create_item(%{
        restaurant_id: restaurant.id,
        menu_category_id: cat2.id,
        name: "Pasta Carbonara",
        description: "Classic Italian pasta",
        price: 1599,
        is_active: true,
        is_available: true
      })

    {restaurant, [cat1, cat2], [item1, sold_out, main]}
  end

  describe "public menu display" do
    test "renders without login (public access)", %{conn: conn} do
      {restaurant, _cats, _items} = create_restaurant_with_menu()
      {:ok, _lv, html} = live(conn, ~p"/menu?restaurant_slug=#{restaurant.slug}")
      assert html =~ restaurant.name
    end

    test "shows active categories", %{conn: conn} do
      {restaurant, [cat1, cat2], _items} = create_restaurant_with_menu()
      {:ok, _lv, html} = live(conn, ~p"/menu?restaurant_slug=#{restaurant.slug}")
      assert html =~ cat1.name
      assert html =~ cat2.name
    end

    test "does not show inactive categories", %{conn: conn} do
      {restaurant, _cats, _items} = create_restaurant_with_menu()
      {:ok, _lv, html} = live(conn, ~p"/menu?restaurant_slug=#{restaurant.slug}")
      refute html =~ "Hidden Category"
    end

    test "shows available items with name, description, price", %{conn: conn} do
      {restaurant, _cats, [item1 | _]} = create_restaurant_with_menu()
      {:ok, _lv, html} = live(conn, ~p"/menu?restaurant_slug=#{restaurant.slug}")
      assert html =~ item1.name
      assert html =~ item1.description
      assert html =~ "$7.99"
    end

    test "shows sold out badge for unavailable items", %{conn: conn} do
      {restaurant, _cats, [_item1, sold_out | _]} = create_restaurant_with_menu()
      {:ok, _lv, html} = live(conn, ~p"/menu?restaurant_slug=#{restaurant.slug}")
      # The item still shows, but with "Sold Out" indicator
      assert html =~ sold_out.name
      assert html =~ "Sold Out"
    end

    test "does not show hidden (inactive) items", %{conn: conn} do
      {restaurant, _cats, _items} = create_restaurant_with_menu()
      {:ok, _lv, html} = live(conn, ~p"/menu?restaurant_slug=#{restaurant.slug}")
      refute html =~ "Hidden Item"
    end

    test "shows restaurant branding color", %{conn: conn} do
      {restaurant, _cats, _items} = create_restaurant_with_menu()
      {:ok, _lv, html} = live(conn, ~p"/menu?restaurant_slug=#{restaurant.slug}")
      assert html =~ restaurant.primary_color
    end

    test "shows error when restaurant not found", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/menu?restaurant_slug=nonexistent-restaurant")
      assert html =~ "not found" or html =~ "Restaurant not found"
    end
  end
end
