defmodule JobMarketAnalyzer.JobMarket.SourceAcquisition.GuardedFetcherTest do
  use ExUnit.Case, async: true

  alias JobMarketAnalyzer.JobMarket.SourceAcquisition.{FetchError, FetchResult, GuardedFetcher}

  @fetched_at ~U[2026-08-24 12:00:00Z]
  @public_ipv4 {8, 8, 8, 8}

  test "returns an identity response and pins transport to the selected IP" do
    requester =
      requester(
        [response(200, [{"content-type", "text/html; charset=utf-8"}], ["<h1>", "Job</h1>"])],
        self()
      )

    assert {:ok,
            %FetchResult{
              requested_url: "https://jobs.example/role#details",
              final_url: "https://jobs.example/role",
              status: 200,
              content_type: "text/html",
              content_encoding: :identity,
              body: "<h1>Job</h1>",
              network_bytes: 12,
              decompressed_bytes: 12,
              redirect_count: 0,
              fetched_at: @fetched_at
            }} = fetch("https://jobs.example/role#details", requester)

    assert_receive {:request, opts}
    assert URI.parse(opts[:url]).host == "8.8.8.8"
    refute opts[:url] =~ "jobs.example"
    assert opts[:connect_options][:hostname] == "jobs.example"
    assert {"host", "jobs.example"} in opts[:headers]
    assert opts[:redirect] == false
    assert opts[:retry] == false
    assert is_function(opts[:into], 2)
  end

  test "incrementally expands a gzip response" do
    body = String.duplicate("expanded source ", 200)
    gzip = :zlib.gzip(body)
    midpoint = div(byte_size(gzip), 2)

    chunks = [
      binary_part(gzip, 0, midpoint),
      binary_part(gzip, midpoint, byte_size(gzip) - midpoint)
    ]

    requester =
      requester(
        [response(200, [{"content-type", "text/plain"}, {"content-encoding", "gzip"}], chunks)],
        self()
      )

    assert {:ok, result} = fetch("https://jobs.example/role", requester)
    assert result.body == body
    assert result.content_encoding == :gzip
    assert result.network_bytes == byte_size(gzip)
    assert result.decompressed_bytes == byte_size(body)
  end

  test "resolves relative and cross-host redirects against logical URLs" do
    resolver = fn
      "jobs.example", :inet -> {:ok, [{8, 8, 8, 8}]}
      "other.example", :inet -> {:ok, [{1, 1, 1, 1}]}
      _host, :inet6 -> {:ok, []}
    end

    requester =
      requester(
        [
          response(302, [{"location", "/jobs/next"}], []),
          response(307, [{"location", "https://other.example/final"}], []),
          response(200, [{"content-type", "application/json"}], ["{}"])
        ],
        self()
      )

    assert {:ok, result} =
             GuardedFetcher.fetch("https://jobs.example/start",
               resolver: resolver,
               requester: requester,
               fetched_at: fn -> @fetched_at end
             )

    assert result.final_url == "https://other.example/final"
    assert result.redirect_count == 2
    assert result.body == "{}"

    assert_receive {:request, first}
    assert_receive {:request, second}
    assert_receive {:request, third}
    assert URI.parse(first[:url]).host == "8.8.8.8"
    assert URI.parse(second[:url]).path == "/jobs/next"
    assert URI.parse(third[:url]).host == "1.1.1.1"
    assert {"host", "other.example"} in third[:headers]
  end

  test "blocks a redirect whose new host resolves to a private address" do
    resolver = fn
      "jobs.example", :inet -> {:ok, [@public_ipv4]}
      "private.example", :inet -> {:ok, [{10, 0, 0, 1}]}
      _host, :inet6 -> {:ok, []}
    end

    requester =
      requester([response(302, [{"location", "https://private.example/job"}], [])], self())

    assert {:error, %FetchError{reason: :blocked_destination}} =
             GuardedFetcher.fetch("https://jobs.example/start",
               resolver: resolver,
               requester: requester
             )

    assert_receive {:request, _opts}
    refute_receive {:request, _opts}
  end

  test "rejects redirect loops and redirects beyond the budget" do
    looping = requester(List.duplicate(response(302, [{"location", "/again"}], []), 4), self())

    assert {:error, %FetchError{reason: :too_many_redirects}} =
             fetch("https://jobs.example/start", looping)

    excessive =
      requester(
        for index <- 1..4 do
          response(302, [{"location", "/hop/#{index}"}], [])
        end,
        self()
      )

    assert {:error, %FetchError{reason: :too_many_redirects}} =
             fetch("https://jobs.example/start", excessive)
  end

  test "rejects missing and malformed redirect locations" do
    for location_headers <- [[], [{"location", "http://[invalid"}]] do
      requester = requester([response(302, location_headers, [])], self())

      assert {:error, %FetchError{reason: :invalid_redirect}} =
               fetch("https://jobs.example/start", requester)
    end
  end

  test "accepts only the approved media types" do
    for content_type <- [
          "text/html",
          "application/xhtml+xml",
          "application/json",
          "application/ld+json",
          "text/plain; charset=UTF-8"
        ] do
      requester = requester([response(200, [{"content-type", content_type}], ["ok"])], self())
      assert {:ok, %FetchResult{body: "ok"}} = fetch("https://jobs.example/source", requester)
    end

    requester = requester([response(200, [{"content-type", "application/pdf"}], ["pdf"])], self())

    assert {:error, %FetchError{reason: :unsupported_content_type}} =
             fetch("https://jobs.example/source", requester)
  end

  test "rejects unsupported and stacked content encodings" do
    for encoding <- ["br", "gzip, br"] do
      requester =
        requester(
          [
            response(200, [{"content-type", "text/plain"}, {"content-encoding", encoding}], [
              "body"
            ])
          ],
          self()
        )

      assert {:error, %FetchError{reason: :unsupported_content_encoding}} =
               fetch("https://jobs.example/source", requester)
    end
  end

  test "halts identity bodies above the network-byte limit" do
    oversized = String.duplicate("x", 2 * 1024 * 1024 + 1)
    requester = requester([response(200, [{"content-type", "text/plain"}], [oversized])], self())

    assert {:error, %FetchError{reason: :response_too_large}} =
             fetch("https://jobs.example/source", requester)
  end

  test "halts gzip bodies above the decompressed-byte limit" do
    gzip = :zlib.gzip(String.duplicate("x", 8 * 1024 * 1024 + 1))

    requester =
      requester(
        [response(200, [{"content-type", "text/plain"}, {"content-encoding", "gzip"}], [gzip])],
        self()
      )

    assert {:error, %FetchError{reason: :decompressed_response_too_large}} =
             fetch("https://jobs.example/source", requester)
  end

  test "maps transport errors to stable application reasons" do
    cases = [
      {:connection_timeout, :connection_timeout},
      {:request_timeout, :request_timeout},
      {%Req.TransportError{reason: :timeout}, :request_timeout},
      {:econnrefused, :network_failure}
    ]

    for {transport_reason, expected_reason} <- cases do
      requester = requester([{:error, transport_reason}], self())

      assert {:error, %FetchError{reason: ^expected_reason}} =
               fetch("https://jobs.example/source", requester)
    end
  end

  test "rejects unsuccessful non-redirect status codes" do
    requester =
      requester([response(404, [{"content-type", "text/plain"}], ["not found"])], self())

    assert {:error, %FetchError{reason: :unexpected_status}} =
             fetch("https://jobs.example/source", requester)
  end

  defp fetch(url, requester) do
    GuardedFetcher.fetch(url,
      resolver: fn
        _host, :inet -> {:ok, [@public_ipv4]}
        _host, :inet6 -> {:ok, []}
      end,
      requester: requester,
      fetched_at: fn -> @fetched_at end
    )
  end

  defp response(status, headers, chunks), do: {:response, status, headers, chunks}

  defp requester(responses, test_pid) do
    {:ok, queue} = Agent.start_link(fn -> responses end)

    fn opts ->
      send(test_pid, {:request, opts})

      case Agent.get_and_update(queue, fn [response | rest] -> {response, rest} end) do
        {:error, reason} -> {:error, reason}
        {:response, status, headers, chunks} -> simulate_response(opts, status, headers, chunks)
      end
    end
  end

  defp simulate_response(opts, status, headers, chunks) do
    request = Req.new(method: :get, url: opts[:url])
    response = Req.Response.new(status: status, headers: headers)

    {_request, response} =
      Enum.reduce_while(chunks, {request, response}, fn chunk, accumulator ->
        case opts[:into].({:data, chunk}, accumulator) do
          {:cont, next} -> {:cont, next}
          {:halt, next} -> {:halt, next}
        end
      end)

    {:ok, response}
  end
end
