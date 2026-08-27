defmodule JobMarketAnalyzer.JobMarket.WorkArrangementPreference do
  use Ecto.Schema
  import Ecto.Changeset

  @singleton_id 1

  schema "work_arrangement_preferences" do
    field :enabled, :boolean, default: false
    field :accept_fully_remote, :boolean, default: false
    field :accept_hybrid, :boolean, default: false
    field :accept_on_site, :boolean, default: false

    timestamps()
  end

  @doc false
  def default do
    %__MODULE__{id: @singleton_id}
  end

  @doc false
  def changeset(preference, attrs) do
    cast(preference, attrs, [:enabled, :accept_fully_remote, :accept_hybrid, :accept_on_site])
  end

  @doc "Returns accepted modes in canonical Work Arrangement order."
  def accepted_arrangements(%__MODULE__{} = preference) do
    [
      {:fully_remote, preference.accept_fully_remote},
      {:hybrid, preference.accept_hybrid},
      {:on_site, preference.accept_on_site}
    ]
    |> Enum.filter(fn {_arrangement, accepted?} -> accepted? end)
    |> Enum.map(&elem(&1, 0))
  end
end
