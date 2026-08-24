defmodule JobMarketAnalyzer.JobMarket.SourceAcquisition.Suggestion do
  @moduledoc """
  A transient metadata suggestion with deterministic provenance.
  """

  @enforce_keys [:value, :source]
  defstruct @enforce_keys

  @type source :: :job_posting_json_ld | :page_metadata
  @type t :: %__MODULE__{value: String.t(), source: source()}
end
