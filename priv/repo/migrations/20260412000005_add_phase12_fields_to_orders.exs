defmodule RestaurantDash.Repo.Migrations.AddPhase12FieldsToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :loyalty_points_earned, :integer, default: 0
      add :restaurant_rating, :integer
      add :restaurant_review, :text
      add :review_response, :text
    end
  end
end
