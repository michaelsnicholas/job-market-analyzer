defmodule JobMarketAnalyzer.Repo.Migrations.AddSourceProvenanceToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :final_source_url, :string
      add :source_acquired_at, :utc_datetime_usec
      add :source_acquisition_method, :string, null: false, default: "manual"
      add :source_extractor_version, :integer
      add :source_text_modified, :boolean, null: false, default: false
    end
  end
end
