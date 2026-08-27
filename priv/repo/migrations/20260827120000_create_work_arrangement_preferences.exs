defmodule JobMarketAnalyzer.Repo.Migrations.CreateWorkArrangementPreferences do
  use Ecto.Migration

  def change do
    create table(:work_arrangement_preferences) do
      add :enabled, :boolean, null: false, default: false
      add :accept_fully_remote, :boolean, null: false, default: false
      add :accept_hybrid, :boolean, null: false, default: false
      add :accept_on_site, :boolean, null: false, default: false

      timestamps()
    end
  end
end
