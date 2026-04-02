defmodule RestaurantDash.Promotions do
  @moduledoc """
  Context for promo codes and discounts.
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Promotions.PromoCode

  # ─── CRUD ────────────────────────────────────────────────────────────────────

  def list_promo_codes(restaurant_id) do
    PromoCode
    |> where([p], p.restaurant_id == ^restaurant_id)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  def get_promo_code!(id), do: Repo.get!(PromoCode, id)

  def get_promo_code_by_code(restaurant_id, code) when is_binary(code) do
    upcased = String.upcase(code)

    PromoCode
    |> where([p], p.restaurant_id == ^restaurant_id and p.code == ^upcased)
    |> Repo.one()
  end

  def create_promo_code(attrs) do
    %PromoCode{}
    |> PromoCode.changeset(attrs)
    |> Repo.insert()
  end

  def update_promo_code(%PromoCode{} = promo_code, attrs) do
    promo_code
    |> PromoCode.changeset(attrs)
    |> Repo.update()
  end

  def deactivate_promo_code(%PromoCode{} = promo_code) do
    promo_code
    |> Ecto.Changeset.change(%{is_active: false})
    |> Repo.update()
  end

  # ─── Validation ──────────────────────────────────────────────────────────────

  @doc """
  Validates a promo code for use at checkout.

  Returns {:ok, promo_code} or {:error, reason_string}.
  """
  def validate_promo_code(restaurant_id, code, order_subtotal_cents) do
    case get_promo_code_by_code(restaurant_id, code) do
      nil ->
        {:error, "Promo code not found"}

      promo_code ->
        validate_code_usability(promo_code, order_subtotal_cents)
    end
  end

  defp validate_code_usability(promo, subtotal) do
    now = DateTime.utc_now()

    cond do
      !promo.is_active ->
        {:error, "Promo code is no longer active"}

      promo.expires_at != nil && DateTime.compare(promo.expires_at, now) == :lt ->
        {:error, "Promo code has expired"}

      promo.max_uses != nil && promo.current_uses >= promo.max_uses ->
        {:error, "Promo code has reached its usage limit"}

      promo.min_order != nil && subtotal < promo.min_order ->
        min_str = format_cents(promo.min_order)
        {:error, "Minimum order of #{min_str} required for this promo code"}

      true ->
        {:ok, promo}
    end
  end

  # ─── Discount calculation ─────────────────────────────────────────────────────

  @doc """
  Calculates the discount amount in cents for a given subtotal and promo code.
  """
  def calculate_discount(%PromoCode{discount_type: "percentage", discount_value: pct}, subtotal) do
    div(subtotal * pct, 100)
  end

  def calculate_discount(%PromoCode{discount_type: "fixed", discount_value: value}, _subtotal) do
    value
  end

  # ─── Usage tracking ───────────────────────────────────────────────────────────

  @doc """
  Increments current_uses on a promo code. Called after order is placed.
  """
  def increment_usage(%PromoCode{} = promo_code) do
    {count, _} =
      PromoCode
      |> where([p], p.id == ^promo_code.id)
      |> Repo.update_all(inc: [current_uses: 1])

    {:ok, count}
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  defp format_cents(cents) do
    dollars = div(cents, 100)
    remaining_cents = rem(cents, 100)
    "$#{dollars}.#{String.pad_leading(Integer.to_string(remaining_cents), 2, "0")}"
  end
end
