defmodule RestaurantDash.Promotions.PromoCode do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_discount_types ~w(percentage fixed)

  schema "promo_codes" do
    field :code, :string
    field :discount_type, :string
    field :discount_value, :integer
    field :min_order, :integer
    field :max_uses, :integer
    field :current_uses, :integer, default: 0
    field :expires_at, :utc_datetime
    field :is_active, :boolean, default: true

    belongs_to :restaurant, RestaurantDash.Tenancy.Restaurant

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(promo_code, attrs) do
    promo_code
    |> cast(attrs, [
      :restaurant_id,
      :code,
      :discount_type,
      :discount_value,
      :min_order,
      :max_uses,
      :current_uses,
      :expires_at,
      :is_active
    ])
    |> validate_required([:restaurant_id, :code, :discount_type, :discount_value])
    |> validate_inclusion(:discount_type, @valid_discount_types)
    |> validate_number(:discount_value, greater_than: 0)
    |> validate_number(:min_order, greater_than_or_equal_to: 0)
    |> validate_number(:max_uses, greater_than: 0)
    |> validate_percentage()
    |> upcase_code()
    |> unique_constraint(:code, name: :promo_codes_restaurant_id_code_index)
  end

  defp upcase_code(changeset) do
    case get_change(changeset, :code) do
      nil -> changeset
      code -> put_change(changeset, :code, String.upcase(code))
    end
  end

  defp validate_percentage(changeset) do
    case get_field(changeset, :discount_type) do
      "percentage" ->
        validate_number(changeset, :discount_value,
          greater_than: 0,
          less_than_or_equal_to: 100
        )

      _ ->
        changeset
    end
  end
end
