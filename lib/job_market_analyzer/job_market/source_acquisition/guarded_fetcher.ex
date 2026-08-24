defmodule JobMarketAnalyzer.JobMarket.SourceAcquisition.GuardedFetcher do
  @moduledoc false

  alias JobMarketAnalyzer.JobMarket.SourceAcquisition.{FetchError, FetchResult, NetworkPolicy}

  @max_redirects 3
  @connect_timeout 5_000
  @receive_timeout 5_000
  @request_timeout 15_000
  @total_timeout 20_000
  @max_network_bytes 2 * 1024 * 1024
  @max_decompressed_bytes 8 * 1024 * 1024
  @redirect_statuses [301, 302, 303, 307, 308]
  @accepted_content_types MapSet.new([
                            "text/html",
                            "application/xhtml+xml",
                            "application/json",
                            "application/ld+json",
                            "text/plain"
                          ])

  defmodule BodyState do
    @moduledoc false
    defstruct chunks: [],
              network_bytes: 0,
              decompressed_bytes: 0,
              content_encoding: nil,
              error: nil
  end

  @spec fetch(String.t(), keyword()) :: {:ok, FetchResult.t()} | {:error, FetchError.t()}
  def fetch(url, opts \\ []) do
    monotonic_time = Keyword.get(opts, :monotonic_time, &System.monotonic_time/1)
    fetched_at = Keyword.get(opts, :fetched_at, &DateTime.utc_now/0)
    deadline = monotonic_time.(:millisecond) + @total_timeout

    do_fetch(url, url, 0, MapSet.new(), deadline, monotonic_time, fetched_at, opts)
  end

  defp do_fetch(
         requested_url,
         logical_url,
         redirect_count,
         visited,
         deadline,
         monotonic_time,
         fetched_at,
         opts
       ) do
    remaining = deadline - monotonic_time.(:millisecond)

    if remaining <= 0 do
      error(:request_timeout, :total_deadline)
    else
      network_opts = Keyword.take(opts, [:resolver])

      with {:ok, destination} <- NetworkPolicy.prepare(logical_url, network_opts),
           :ok <- reject_visited(destination.logical_url, visited),
           {:ok, response, body_state} <- request(destination, remaining, opts),
           {:ok, outcome} <- classify_response(response, body_state) do
        case outcome do
          {:success, content_type, content_encoding, body} ->
            {:ok,
             %FetchResult{
               requested_url: requested_url,
               final_url: destination.logical_url,
               fetched_at: fetched_at.(),
               status: response.status,
               content_type: content_type,
               content_encoding: content_encoding,
               body: body,
               network_bytes: body_state.network_bytes,
               decompressed_bytes: body_state.decompressed_bytes,
               redirect_count: redirect_count
             }}

          {:redirect, location} when redirect_count < @max_redirects ->
            with {:ok, next_url} <- redirect_url(destination.logical_uri, location) do
              do_fetch(
                requested_url,
                next_url,
                redirect_count + 1,
                MapSet.put(visited, destination.logical_url),
                deadline,
                monotonic_time,
                fetched_at,
                opts
              )
            end

          {:redirect, _location} ->
            error(:too_many_redirects, :redirect)
        end
      end
    end
  end

  defp request(destination, remaining, opts) do
    requester = Keyword.get(opts, :requester, &Req.request/1)
    gzip = :zlib.open()
    :ok = :zlib.inflateInit(gzip, 31)

    request_opts = [
      method: :get,
      url: destination.transport_url,
      headers: [
        {"host", destination.host_header},
        {"accept", Enum.join(@accepted_content_types, ", ")},
        {"accept-encoding", "gzip, identity"}
      ],
      connect_options: [
        hostname: destination.logical_uri.host,
        timeout: min(@connect_timeout, remaining),
        protocols: [:http1]
      ],
      redirect: false,
      retry: false,
      raw: true,
      decode_body: false,
      receive_timeout: min(@receive_timeout, remaining),
      request_timeout: min(@request_timeout, remaining),
      into: stream_callback(gzip)
    ]

    try do
      case requester.(request_opts) do
        {:ok, %Req.Response{} = response} ->
          with {:ok, body_state} <- initialize_stream(response, body_state(response.body)) do
            case body_state.error do
              nil -> finalize_request(response, body_state, gzip)
              :halt_redirect -> {:ok, response, body_state}
              reason -> error(reason, :response_body)
            end
          else
            {:error, reason} -> error(reason, :response_headers)
          end

        {:error, reason} ->
          map_request_error(reason)
      end
    rescue
      _exception -> error(:network_failure, :request)
    catch
      :exit, _reason -> error(:network_failure, :request)
    after
      :zlib.close(gzip)
    end
  end

  defp stream_callback(gzip) do
    fn {:data, data}, {request, response} ->
      state = body_state(response.body)

      case consume_chunk(response, state, data, gzip) do
        {:ok, state} -> {:cont, {request, %{response | body: state}}}
        {:error, state} -> {:halt, {request, %{response | body: state}}}
      end
    end
  end

  defp body_state(%BodyState{} = state), do: state
  defp body_state(_initial_body), do: %BodyState{}

  defp consume_chunk(response, state, data, gzip) do
    with {:ok, state} <- initialize_stream(response, state),
         :ok <- validate_streamable_status(response.status),
         network_bytes <- state.network_bytes + byte_size(data),
         :ok <- enforce_network_limit(network_bytes),
         {:ok, decoded_chunks} <- decode(data, state, gzip),
         decoded_bytes <- IO.iodata_length(decoded_chunks),
         decompressed_bytes <- state.decompressed_bytes + decoded_bytes,
         :ok <- enforce_decompressed_limit(decompressed_bytes) do
      {:ok,
       %{
         state
         | chunks: [decoded_chunks | state.chunks],
           network_bytes: network_bytes,
           decompressed_bytes: decompressed_bytes
       }}
    else
      {:error, reason} -> {:error, %{state | error: reason}}
    end
  rescue
    _exception -> {:error, %{state | error: :network_failure}}
  end

  defp initialize_stream(response, %BodyState{content_encoding: nil} = state) do
    with {:ok, encoding} <- content_encoding(response),
         :ok <- validate_content_type_for_status(response) do
      {:ok, %{state | content_encoding: encoding}}
    end
  end

  defp initialize_stream(_response, state), do: {:ok, state}

  defp validate_streamable_status(status) when status in 200..299, do: :ok

  defp validate_streamable_status(status) when status in @redirect_statuses,
    do: {:error, :halt_redirect}

  defp validate_streamable_status(_status), do: {:error, :unexpected_status}

  defp validate_content_type_for_status(%Req.Response{status: status})
       when status in @redirect_statuses,
       do: :ok

  defp validate_content_type_for_status(response) do
    case content_type(response) do
      {:ok, _content_type} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp enforce_network_limit(bytes) when bytes <= @max_network_bytes, do: :ok
  defp enforce_network_limit(_bytes), do: {:error, :response_too_large}

  defp enforce_decompressed_limit(bytes) when bytes <= @max_decompressed_bytes, do: :ok

  defp enforce_decompressed_limit(_bytes),
    do: {:error, :decompressed_response_too_large}

  defp decode(data, %BodyState{content_encoding: :identity}, _gzip),
    do: {:ok, data}

  defp decode(data, %BodyState{content_encoding: :gzip}, gzip) do
    drain_gzip(gzip, :zlib.safeInflate(gzip, data), [])
  end

  defp drain_gzip(_gzip, {:finished, output}, acc),
    do: {:ok, Enum.reverse([output | acc])}

  defp drain_gzip(_gzip, {:need_dictionary, _adler, _output}, _acc),
    do: {:error, :network_failure}

  defp drain_gzip(gzip, {:continue, output}, acc) do
    if IO.iodata_length(output) == 0 do
      {:ok, Enum.reverse(acc)}
    else
      drain_gzip(gzip, :zlib.safeInflate(gzip, []), [output | acc])
    end
  end

  defp finalize_request(response, body_state, gzip) do
    with :ok <- validate_stream_completion(body_state, gzip) do
      {:ok, response, body_state}
    end
  end

  defp validate_stream_completion(%BodyState{content_encoding: :gzip}, gzip) do
    :zlib.inflateEnd(gzip)
  rescue
    _exception -> {:error, :network_failure}
  end

  defp validate_stream_completion(_state, _gzip), do: :ok

  defp classify_response(response, %BodyState{error: :halt_redirect} = state)
       when response.status in @redirect_statuses do
    redirect_outcome(response, state)
  end

  defp classify_response(response, %BodyState{} = state)
       when response.status in @redirect_statuses,
       do: redirect_outcome(response, state)

  defp classify_response(%Req.Response{status: status}, _state) when status not in 200..299,
    do: error(:unexpected_status, :response_status)

  defp classify_response(response, %BodyState{} = state) do
    with {:ok, type} <- content_type(response),
         {:ok, encoding} <- content_encoding(response) do
      body = state.chunks |> Enum.reverse() |> IO.iodata_to_binary()
      {:ok, {:success, type, encoding, body}}
    else
      {:error, reason} -> error(reason, :response_headers)
    end
  end

  defp redirect_outcome(response, _state) do
    case Req.Response.get_header(response, "location") do
      [location] when is_binary(location) and location != "" -> {:ok, {:redirect, location}}
      _other -> error(:invalid_redirect, :redirect)
    end
  end

  defp content_type(response) do
    case Req.Response.get_header(response, "content-type") do
      [header] ->
        type = header |> String.split(";", parts: 2) |> hd() |> String.trim() |> String.downcase()

        if MapSet.member?(@accepted_content_types, type) do
          {:ok, type}
        else
          {:error, :unsupported_content_type}
        end

      _other ->
        {:error, :unsupported_content_type}
    end
  end

  defp content_encoding(response) do
    case Req.Response.get_header(response, "content-encoding") do
      [] -> {:ok, :identity}
      [encoding] -> normalize_encoding(encoding)
      _other -> {:error, :unsupported_content_encoding}
    end
  end

  defp normalize_encoding(encoding) do
    case encoding |> String.trim() |> String.downcase() do
      "identity" -> {:ok, :identity}
      "gzip" -> {:ok, :gzip}
      _other -> {:error, :unsupported_content_encoding}
    end
  end

  defp redirect_url(logical_uri, location) do
    with {:ok, location_uri} <- URI.new(location),
         %URI{} = merged <- URI.merge(logical_uri, location_uri) do
      {:ok, URI.to_string(merged)}
    else
      _other -> error(:invalid_redirect, :redirect)
    end
  rescue
    _exception -> error(:invalid_redirect, :redirect)
  end

  defp reject_visited(logical_url, visited) do
    if MapSet.member?(visited, logical_url) do
      error(:too_many_redirects, :redirect)
    else
      :ok
    end
  end

  defp map_request_error(:connection_timeout), do: error(:connection_timeout, :request)
  defp map_request_error(:request_timeout), do: error(:request_timeout, :request)

  defp map_request_error(%Req.TransportError{reason: :timeout}),
    do: error(:request_timeout, :request)

  defp map_request_error(_reason), do: error(:network_failure, :request)

  defp error(reason, stage) do
    {:error,
     %FetchError{
       reason: reason,
       stage: stage,
       message: error_message(reason)
     }}
  end

  defp error_message(:too_many_redirects), do: "The URL redirected too many times."
  defp error_message(:invalid_redirect), do: "The URL returned an invalid redirect."
  defp error_message(:connection_timeout), do: "The connection timed out."
  defp error_message(:request_timeout), do: "The source request timed out."
  defp error_message(:network_failure), do: "The source could not be retrieved."

  defp error_message(:unsupported_content_type),
    do: "The source returned an unsupported content type."

  defp error_message(:unsupported_content_encoding),
    do: "The source returned an unsupported content encoding."

  defp error_message(:response_too_large), do: "The source response is too large."

  defp error_message(:decompressed_response_too_large),
    do: "The expanded source response is too large."

  defp error_message(:unexpected_status), do: "The source returned an unsuccessful response."
end
