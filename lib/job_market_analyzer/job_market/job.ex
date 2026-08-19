defmodule JobMarketAnalyzer.JobMarket.Job do
  use Ecto.Schema
  import Ecto.Changeset

  schema "jobs" do
    field :company, :string
    field :role, :string
    field :source_url, :string
    field :raw_description, :string

    timestamps()
  end

  @doc false
  def changeset(job, attrs) do
    job
    |> cast(attrs, [:company, :role, :source_url, :raw_description])
    |> validate_raw_description()
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
