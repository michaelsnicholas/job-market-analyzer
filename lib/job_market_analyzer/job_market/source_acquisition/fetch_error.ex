defmodule JobMarketAnalyzer.JobMarket.SourceAcquisition.FetchError do
  @moduledoc """
  Stable application-owned failure returned by guarded public-source acquisition.
  """

  @enforce_keys [:reason, :stage, :message]
  defstruct [:reason, :stage, :message]

  @type reason ::
          :invalid_url
          | :unsupported_scheme
          | :credentials_not_allowed
          | :port_not_allowed
          | :dns_failure
          | :blocked_destination
          | :too_many_redirects
          | :invalid_redirect
          | :connection_timeout
          | :request_timeout
          | :network_failure
          | :unsupported_content_type
          | :unsupported_content_encoding
          | :response_too_large
          | :decompressed_response_too_large
          | :unexpected_status

  @type t :: %__MODULE__{
          reason: reason(),
          stage: atom(),
          message: String.t()
        }
end
