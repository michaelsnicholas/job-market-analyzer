defmodule JobMarketAnalyzer.Repo.Migrations.CreateJobs do
  use Ecto.Migration

  def change do
    create table(:jobs) do
      add :company, :string
      add :role, :string
      add :source_url, :string
      add :raw_description, :text, null: false

      timestamps()
    end
  end
end
