defmodule RestaurantDashWeb.MenuManagementLiveTest do
  use RestaurantDashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias RestaurantDash.{Accounts, Menu, Tenancy}

  defp create_owner_with_restaurant do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Menu Test Pizza",
        slug: "menu-test-pizza-#{System.unique_integer([:positive])}",
        primary_color: "#E63946"
      })

    {:ok, user} =
      Accounts.register_user_with_role(%{
        email: "menu_owner#{System.unique_integer([:positive])}@test.com",
        password: "hello world!",
        role: "owner",
        restaurant_id: restaurant.id,
        name: "Menu Owner"
      })

    {restaurant, user}
  end

  describe "access control" do
    test "redirects unauthenticated user to login", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/menu")
      assert path =~ "/users/log-in"
    end

    test "allows owner to access menu management", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/menu")
      assert html =~ "Menu"
    end
  end

  describe "category management" do
    test "shows existing categories", %{conn: conn} do
      {restaurant, user} = create_owner_with_restaurant()
      {:ok, _cat} = Menu.create_category(%{name: "Appetizers", restaurant_id: restaurant.id})
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/dashboard/menu")
      assert html =~ "Appetizers"
    end

    test "can add a new category", %{conn: conn} do
      {_restaurant, user} = create_owner_with_restaurant()
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/dashboard/menu")

      # Click "Add Category"
      lv |> element("button", "Add Category") |> render_click()

      # Fill in form and submit
      lv
      |> form("#category-form", category: %{name: "Specials", description: "Today's specials"})
      |> render_submit()

      html = render(lv)
      assert html =~ "Specials"
    end

    test "can edit a category", %{conn: conn} do
      {restaurant, user} = create_owner_with_restaurant()
      {:ok, cat} = Menu.create_category(%{name: "Old Name", restaurant_id: restaurant.id})
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/dashboard/menu")

      # Click edit button for this category
      lv |> element("[data-action='edit-category'][data-id='#{cat.id}']") |> render_click()

      lv
      |> form("#category-form", category: %{name: "New Name"})
      |> render_submit()

      html = render(lv)
      assert html =~ "New Name"
      refute html =~ "Old Name"
    end

    test "can delete a category", %{conn: conn} do
      {restaurant, user} = create_owner_with_restaurant()
      {:ok, cat} = Menu.create_category(%{name: "To Delete", restaurant_id: restaurant.id})
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/dashboard/menu")

      assert render(lv) =~ "To Delete"

      lv
      |> element("[data-action='delete-category'][data-id='#{cat.id}']")
      |> render_click()

      refute render(lv) =~ "To Delete"
    end

    test "can reorder categories", %{conn: conn} do
      {restaurant, user} = create_owner_with_restaurant()

      {:ok, _c1} =
        Menu.create_category(%{name: "Pizzas", position: 10, restaurant_id: restaurant.id})

      {:ok, c2} =
        Menu.create_category(%{name: "Drinks", position: 20, restaurant_id: restaurant.id})

      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/dashboard/menu")

      # Move c2 up (before c1)
      lv |> element("[data-action='move-category-up'][data-id='#{c2.id}']") |> render_click()

      html = render(lv)
      # Drinks should now appear before Pizzas
      drinks_pos = :binary.match(html, "Drinks") |> elem(0)
      pizzas_pos = :binary.match(html, "Pizzas") |> elem(0)
      assert drinks_pos < pizzas_pos
    end
  end

  describe "item management" do
    test "shows items for selected category", %{conn: conn} do
      {restaurant, user} = create_owner_with_restaurant()
      {:ok, cat} = Menu.create_category(%{name: "Pizzas", restaurant_id: restaurant.id})

      {:ok, _item} =
        Menu.create_item(%{
          name: "Margherita",
          price: 1499,
          restaurant_id: restaurant.id,
          menu_category_id: cat.id
        })

      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/dashboard/menu")

      # Select the category
      lv |> element("[data-action='select-category'][data-id='#{cat.id}']") |> render_click()
      html = render(lv)
      assert html =~ "Margherita"
    end

    test "can add a new item", %{conn: conn} do
      {restaurant, user} = create_owner_with_restaurant()
      {:ok, cat} = Menu.create_category(%{name: "Pizzas", restaurant_id: restaurant.id})
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/dashboard/menu")

      # Select category
      lv |> element("[data-action='select-category'][data-id='#{cat.id}']") |> render_click()

      # Click add item
      lv |> element("button", "Add Item") |> render_click()

      lv
      |> form("#item-form",
        item: %{
          name: "Pepperoni",
          description: "Classic",
          price: "16.99",
          menu_category_id: cat.id
        }
      )
      |> render_submit()

      html = render(lv)
      assert html =~ "Pepperoni"
    end

    test "can delete an item", %{conn: conn} do
      {restaurant, user} = create_owner_with_restaurant()
      {:ok, cat} = Menu.create_category(%{name: "Pizzas", restaurant_id: restaurant.id})

      {:ok, item} =
        Menu.create_item(%{
          name: "Delete Me",
          price: 999,
          restaurant_id: restaurant.id,
          menu_category_id: cat.id
        })

      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/dashboard/menu")
      lv |> element("[data-action='select-category'][data-id='#{cat.id}']") |> render_click()

      assert render(lv) =~ "Delete Me"

      lv |> element("[data-action='delete-item'][data-id='#{item.id}']") |> render_click()

      refute render(lv) =~ "Delete Me"
    end

    test "can toggle item availability (86 button)", %{conn: conn} do
      {restaurant, user} = create_owner_with_restaurant()
      {:ok, cat} = Menu.create_category(%{name: "Pizzas", restaurant_id: restaurant.id})

      {:ok, item} =
        Menu.create_item(%{
          name: "Avail Item",
          price: 999,
          restaurant_id: restaurant.id,
          menu_category_id: cat.id,
          is_available: true
        })

      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/dashboard/menu")
      lv |> element("[data-action='select-category'][data-id='#{cat.id}']") |> render_click()

      # Toggle availability
      lv |> element("[data-action='toggle-availability'][data-id='#{item.id}']") |> render_click()

      html = render(lv)
      assert html =~ "eighty-sixed"
    end
  end
end
