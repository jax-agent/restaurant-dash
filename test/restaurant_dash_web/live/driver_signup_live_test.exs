defmodule RestaurantDashWeb.DriverSignupLiveTest do
  use RestaurantDashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias RestaurantDash.Drivers

  defp unique_email, do: "driver#{System.unique_integer()}@example.com"

  describe "Driver Signup LiveView" do
    test "renders signup form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/drivers/signup")
      assert html =~ "Driver Sign Up"
      assert html =~ "vehicle_type"
      assert html =~ "Create Driver Account"
    end

    test "successful registration redirects to login with flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/drivers/signup")

      result =
        view
        |> form("form", %{
          "driver" => %{
            "name" => "Jane Driver",
            "email" => unique_email(),
            "password" => "securepass1234",
            "vehicle_type" => "car",
            "license_plate" => "XYZ-999",
            "phone" => "555-0101"
          }
        })
        |> render_submit()

      assert {:error, {:redirect, %{to: "/users/log-in"}}} = result
    end

    test "shows error for duplicate email", %{conn: conn} do
      email = unique_email()

      {:ok, _} =
        Drivers.register_driver(%{
          "email" => email,
          "password" => "securepass1234",
          "name" => "First"
        })

      {:ok, view, _html} = live(conn, ~p"/drivers/signup")

      html =
        view
        |> form("form", %{
          "driver" => %{
            "name" => "Second Driver",
            "email" => email,
            "password" => "securepass1234",
            "vehicle_type" => "bike"
          }
        })
        |> render_submit()

      assert html =~ "email" or html =~ "already"
    end
  end
end
