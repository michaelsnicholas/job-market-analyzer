defmodule JobMarketAnalyzer.JobMarket.SourceAcquisition.Draft do
  @moduledoc """
  A transient, reviewable source proposal. It is never persisted directly.
  """

  alias JobMarketAnalyzer.JobMarket.SourceAcquisition.Suggestion

  @enforce_keys [
    :company,
    :role,
    :raw_description,
    :original_extracted_text,
    :source_url,
    :final_source_url,
    :source_acquired_at,
    :source_acquisition_method,
    :source_extractor_version,
    :warnings
  ]
  defstruct @enforce_keys

  @type method ::
          :job_posting_json_ld
          | :job_posting_json_ld_reconciled
          | :generic_html
          | :plain_text
  @type warning ::
          :generic_extraction
          | :multiple_job_postings
          | :short_source
          | :metadata_conflict
          | :possible_boilerplate

  @type t :: %__MODULE__{
          company: Suggestion.t() | nil,
          role: Suggestion.t() | nil,
          raw_description: String.t(),
          original_extracted_text: String.t(),
          source_url: String.t(),
          final_source_url: String.t(),
          source_acquired_at: DateTime.t(),
          source_acquisition_method: method(),
          source_extractor_version: pos_integer(),
          warnings: [warning()]
        }
end
