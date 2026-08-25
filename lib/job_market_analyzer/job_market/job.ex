defmodule JobMarketAnalyzer.JobMarket.Job do
  use Ecto.Schema
  import Ecto.Changeset

  schema "jobs" do
    field :company, :string
    field :role, :string
    field :source_url, :string
    field :final_source_url, :string
    field :source_acquired_at, :utc_datetime_usec

    field :source_acquisition_method, Ecto.Enum,
      values: [
        manual: "manual",
        job_posting_json_ld: "job_posting_json_ld",
        generic_html: "generic_html",
        plain_text: "plain_text"
      ],
      default: :manual

    field :source_extractor_version, :integer
    field :source_text_modified, :boolean, default: false
    field :raw_description, :string

    timestamps()
  end

  @doc false
  def changeset(job, attrs) do
    job
    |> cast(attrs, [:company, :role, :source_url, :raw_description])
    |> validate_raw_description()
  end

  @doc false
  def acquired_changeset(job, attrs, provenance) do
    job
    |> changeset(attrs)
    |> cast(provenance, [
      :source_url,
      :final_source_url,
      :source_acquired_at,
      :source_acquisition_method,
      :source_extractor_version,
      :source_text_modified
    ])
    |> validate_required([
      :source_url,
      :final_source_url,
      :source_acquired_at,
      :source_acquisition_method,
      :source_extractor_version,
      :source_text_modified
    ])
    |> validate_acquired_method()
    |> validate_number(:source_extractor_version, greater_than: 0)
  end

  defp validate_acquired_method(changeset) do
    if get_field(changeset, :source_acquisition_method) in [
         :job_posting_json_ld,
         :generic_html,
         :plain_text
       ] do
      changeset
    else
      add_error(changeset, :source_acquisition_method, "is not a URL acquisition method")
    end
  end

  defp validate_raw_description(changeset) do
    case get_field(changeset, :raw_description) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          add_error(changeset, :raw_description, "can't be blank")
        else
          changeset
        end

      _value ->
        add_error(changeset, :raw_description, "can't be blank")
    end
  end
end
