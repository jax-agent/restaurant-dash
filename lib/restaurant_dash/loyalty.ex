defmodule RestaurantDash.Loyalty do
  @moduledoc """
  Context for the customer loyalty program.
  Points are earned after payment confirmation.
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Loyalty.{LoyaltyAccount, LoyaltyReward}

  # ─── Accounts ────────────────────────────────────────────────────────────────

  def get_or_create_account(restaurant_id, customer_email) do
    email = String.downcase(customer_email)

    case Repo.one(
           from a in LoyaltyAccount,
             where: a.restaurant_id == ^restaurant_id and a.customer_email == ^email
         ) do
      nil ->
        %LoyaltyAccount{}
        |> LoyaltyAccount.changeset(%{restaurant_id: restaurant_id, customer_email: email})
        |> Repo.insert()

      account ->
        {:ok, account}
    end
  end

  def get_account(restaurant_id, customer_email) do
    email = String.downcase(customer_email)

    Repo.one(
      from a in LoyaltyAccount,
        where: a.restaurant_id == ^restaurant_id and a.customer_email == ^email
    )
  end

  def list_top_members(restaurant_id, limit \\ 20) do
    LoyaltyAccount
    |> where([a], a.restaurant_id == ^restaurant_id)
    |> order_by([a], desc: a.total_points_earned)
    |> limit(^limit)
    |> Repo.all()
  end

  # ─── Points Earning ───────────────────────────────────────────────────────────

  @doc """
  Calculates points earned for an order.
  rate = points per dollar (default 1).
  total_cents is the order total after discounts.
  """
  def calculate_points_earned(total_cents, points_rate \\ 1) do
    dollars = div(total_cents, 100)
    dollars * points_rate
  end

  @doc """
  Award points to a customer after payment confirmation.
  Creates a loyalty account if one doesn't exist.
  """
  def award_points(restaurant_id, customer_email, points) when points > 0 do
    {:ok, account} = get_or_create_account(restaurant_id, customer_email)

    account
    |> Ecto.Changeset.change(%{
      points_balance: account.points_balance + points,
      total_points_earned: account.total_points_earned + points
    })
    |> Repo.update()
  end

  def award_points(_restaurant_id, _customer_email, 0), do: {:ok, :no_points}
  def award_points(_restaurant_id, _customer_email, _points), do: {:error, :invalid_points}

  # ─── Rewards ─────────────────────────────────────────────────────────────────

  def list_rewards(restaurant_id) do
    LoyaltyReward
    |> where([r], r.restaurant_id == ^restaurant_id)
    |> order_by([r], asc: r.points_cost)
    |> Repo.all()
  end

  def list_active_rewards(restaurant_id) do
    LoyaltyReward
    |> where([r], r.restaurant_id == ^restaurant_id and r.is_active == true)
    |> order_by([r], asc: r.points_cost)
    |> Repo.all()
  end

  def get_reward!(id), do: Repo.get!(LoyaltyReward, id)

  def create_reward(attrs) do
    %LoyaltyReward{}
    |> LoyaltyReward.changeset(attrs)
    |> Repo.insert()
  end

  def update_reward(%LoyaltyReward{} = reward, attrs) do
    reward
    |> LoyaltyReward.changeset(attrs)
    |> Repo.update()
  end

  def deactivate_reward(%LoyaltyReward{} = reward) do
    reward
    |> Ecto.Changeset.change(%{is_active: false})
    |> Repo.update()
  end

  # ─── Redemption ──────────────────────────────────────────────────────────────

  @doc """
  Validates that a customer has enough points to redeem a reward.
  Returns {:ok, reward} or {:error, reason}.
  """
  def validate_redemption(restaurant_id, customer_email, reward_id) do
    account = get_account(restaurant_id, customer_email)
    reward = Repo.get(LoyaltyReward, reward_id)

    cond do
      is_nil(reward) ->
        {:error, "Reward not found"}

      !reward.is_active ->
        {:error, "Reward is no longer available"}

      is_nil(account) || account.points_balance < reward.points_cost ->
        {:error, "Insufficient points"}

      true ->
        {:ok, reward}
    end
  end

  @doc """
  Redeems a reward — deducts points from the account.
  """
  def redeem_reward(restaurant_id, customer_email, reward_id) do
    with {:ok, reward} <- validate_redemption(restaurant_id, customer_email, reward_id),
         {:ok, account} <- get_or_create_account(restaurant_id, customer_email) do
      account
      |> Ecto.Changeset.change(%{points_balance: account.points_balance - reward.points_cost})
      |> Repo.update()
      |> case do
        {:ok, _updated} -> {:ok, reward}
        err -> err
      end
    end
  end
end
