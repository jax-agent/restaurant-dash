defmodule RestaurantDash.Loyalty.LoyaltyAccount do
  use Ecto.Schema
  import Ecto.Changeset

  schema "loyalty_accounts" do
    field :customer_email, :string
    field :points_balance, :integer, default: 0
    field :total_points_earned, :integer, default: 0

    belongs_to :restaurant, RestaurantDash.Tenancy.Restaurant

    timestamps(type: :utc_datetime)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:restaurant_id, :customer_email, :points_balance, :total_points_earned])
    |> validate_required([:restaurant_id, :customer_email])
    |> validate_format(:customer_email, ~r/^[^\s]+@[^\s]+$/, message: "is not a valid email")
    |> validate_number(:points_balance, greater_than_or_equal_to: 0)
    |> downcase_email()
    |> unique_constraint(:customer_email,
      name: :loyalty_accounts_restaurant_id_customer_email_index
    )
  end

  defp downcase_email(changeset) do
    case get_change(changeset, :customer_email) do
      nil -> changeset
      email -> put_change(changeset, :customer_email, String.downcase(email))
    end
  end
end
