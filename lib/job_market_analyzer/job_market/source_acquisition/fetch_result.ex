defmodule JobMarketAnalyzer.JobMarket.SourceAcquisition.FetchResult do
  @moduledoc """
  Bounded, transient response returned by guarded public-source acquisition.
  """

  @enforce_keys [
    :requested_url,
    :final_url,
    :fetched_at,
    :status,
    :content_type,
    :content_encoding,
    :body,
    :network_bytes,
    :decompressed_bytes,
    :redirect_count
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          requested_url: String.t(),
          final_url: String.t(),
          fetched_at: DateTime.t(),
          status: pos_integer(),
          content_type: String.t(),
          content_encoding: :identity | :gzip,
          body: binary(),
          network_bytes: non_neg_integer(),
          decompressed_bytes: non_neg_integer(),
          redirect_count: non_neg_integer()
        }
end
