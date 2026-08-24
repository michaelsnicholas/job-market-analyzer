defmodule JobMarketAnalyzer.JobMarket.SourceAcquisition.ExtractionError do
  @moduledoc """
  Stable application-owned failure returned by source extraction.
  """

  @enforce_keys [:reason, :stage, :message]
  defstruct @enforce_keys

  @type reason :: :inadequate_extraction | :ambiguous_job_postings | :unsupported_source
  @type t :: %__MODULE__{reason: reason(), stage: :extraction, message: String.t()}
end
