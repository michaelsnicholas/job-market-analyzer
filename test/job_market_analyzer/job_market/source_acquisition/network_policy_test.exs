defmodule JobMarketAnalyzer.JobMarket.SourceAcquisition.NetworkPolicyTest do
  use ExUnit.Case, async: true

  alias JobMarketAnalyzer.JobMarket.SourceAcquisition.{FetchError, NetworkPolicy}

  describe "URL policy" do
    test "accepts HTTP and HTTPS on their standard ports" do
      assert {:ok, %URI{scheme: "http", port: 80}} =
               NetworkPolicy.validate_url("http://example.com/jobs/1")

      assert {:ok, %URI{scheme: "https", port: 443}} =
               NetworkPolicy.validate_url("https://example.com/jobs/1")
    end

    test "rejects unsupported schemes, credentials, invalid hosts, and disallowed ports" do
      assert_reason("ftp://example.com/job", :unsupported_scheme)
      assert_reason("https://user:secret@example.com/job", :credentials_not_allowed)
      assert_reason("https:///job", :invalid_url)
      assert_reason("https://-invalid.example/job", :invalid_url)
      assert_reason("https://example.com:8443/job", :port_not_allowed)
      assert_reason("http://example.com:8080/job", :port_not_allowed)
    end
  end

  describe "public-address policy" do
    test "accepts representative public IPv4 and IPv6 addresses" do
      assert NetworkPolicy.public_address?({8, 8, 8, 8})
      assert NetworkPolicy.public_address?({0x2606, 0x4700, 0x4700, 0, 0, 0, 0, 0x1111})
    end

    test "blocks private, loopback, link-local, CGNAT, multicast, and reserved IPv4" do
      refute NetworkPolicy.public_address?({0, 0, 0, 0})
      refute NetworkPolicy.public_address?({10, 1, 2, 3})
      refute NetworkPolicy.public_address?({100, 64, 1, 2})
      refute NetworkPolicy.public_address?({127, 0, 0, 1})
      refute NetworkPolicy.public_address?({169, 254, 169, 254})
      refute NetworkPolicy.public_address?({172, 20, 1, 2})
      refute NetworkPolicy.public_address?({192, 168, 1, 2})
      refute NetworkPolicy.public_address?({198, 18, 0, 1})
      refute NetworkPolicy.public_address?({203, 0, 113, 1})
      refute NetworkPolicy.public_address?({224, 0, 0, 1})
      refute NetworkPolicy.public_address?({255, 255, 255, 255})
    end

    test "blocks non-global and transition IPv6 addresses" do
      refute NetworkPolicy.public_address?({0, 0, 0, 0, 0, 0, 0, 0})
      refute NetworkPolicy.public_address?({0, 0, 0, 0, 0, 0, 0, 1})
      refute NetworkPolicy.public_address?({0xFC00, 0, 0, 0, 0, 0, 0, 1})
      refute NetworkPolicy.public_address?({0xFE80, 0, 0, 0, 0, 0, 0, 1})
      refute NetworkPolicy.public_address?({0xFF00, 0, 0, 0, 0, 0, 0, 1})
      refute NetworkPolicy.public_address?({0x2001, 0xDB8, 0, 0, 0, 0, 0, 1})
      refute NetworkPolicy.public_address?({0x2002, 0, 0, 0, 0, 0, 0, 1})
    end

    test "detects IPv4-mapped IPv6 and applies the IPv4 policy" do
      refute NetworkPolicy.public_address?({0, 0, 0, 0, 0, 0xFFFF, 0x0808, 0x0808})
      refute NetworkPolicy.public_address?({0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 0x0001})
    end
  end

  describe "DNS and transport preparation" do
    test "supports A-only, AAAA-only, and combined answers" do
      assert {:ok, destination} =
               NetworkPolicy.prepare("https://example.com/job",
                 resolver: resolver(%{inet: [{8, 8, 8, 8}], inet6: []})
               )

      assert destination.selected_address == {8, 8, 8, 8}
      assert destination.transport_url == "https://8.8.8.8/job"
      assert destination.host_header == "example.com"

      public_ipv6 = {0x2606, 0x4700, 0x4700, 0, 0, 0, 0, 0x1111}

      assert {:ok, destination} =
               NetworkPolicy.prepare("https://example.com/job",
                 resolver: resolver(%{inet: [], inet6: [public_ipv6]})
               )

      assert destination.selected_address == public_ipv6
      assert destination.transport_url == "https://[2606:4700:4700::1111]/job"

      assert {:ok, destination} =
               NetworkPolicy.prepare("https://example.com/job",
                 resolver: resolver(%{inet: [{8, 8, 4, 4}], inet6: [public_ipv6]})
               )

      assert destination.selected_address == {8, 8, 4, 4}
    end

    test "fails closed on DNS failures and no results" do
      assert {:error, %FetchError{reason: :dns_failure}} =
               NetworkPolicy.prepare("https://example.com",
                 resolver: fn _host, _family ->
                   {:error, :timeout}
                 end
               )

      assert {:error, %FetchError{reason: :dns_failure}} =
               NetworkPolicy.prepare("https://example.com",
                 resolver: resolver(%{inet: [], inet6: []})
               )
    end

    test "rejects mixed public and private answers" do
      assert {:error, %FetchError{reason: :blocked_destination}} =
               NetworkPolicy.prepare("https://example.com",
                 resolver: resolver(%{inet: [{8, 8, 8, 8}, {10, 0, 0, 1}], inet6: []})
               )
    end
  end

  defp assert_reason(url, reason) do
    assert {:error, %FetchError{reason: ^reason}} = NetworkPolicy.validate_url(url)
  end

  defp resolver(results) do
    fn _host, family -> {:ok, Map.fetch!(results, family)} end
  end
end
