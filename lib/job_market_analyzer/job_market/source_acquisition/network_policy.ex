defmodule JobMarketAnalyzer.JobMarket.SourceAcquisition.NetworkPolicy do
  @moduledoc false

  alias JobMarketAnalyzer.JobMarket.SourceAcquisition.FetchError

  defmodule Destination do
    @moduledoc false
    @enforce_keys [:logical_uri, :logical_url, :selected_address, :transport_url, :host_header]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            logical_uri: URI.t(),
            logical_url: String.t(),
            selected_address: :inet.ip_address(),
            transport_url: String.t(),
            host_header: String.t()
          }
  end

  @ipv4_blocked Enum.map(
                  [
                    "0.0.0.0/8",
                    "10.0.0.0/8",
                    "100.64.0.0/10",
                    "127.0.0.0/8",
                    "168.63.129.16/32",
                    "169.254.0.0/16",
                    "172.16.0.0/12",
                    "192.0.0.0/24",
                    "192.0.2.0/24",
                    "192.31.196.0/24",
                    "192.52.193.0/24",
                    "192.88.99.0/24",
                    "192.168.0.0/16",
                    "192.175.48.0/24",
                    "198.18.0.0/15",
                    "198.51.100.0/24",
                    "203.0.113.0/24",
                    "224.0.0.0/4",
                    "240.0.0.0/4"
                  ],
                  &InetCidr.parse_cidr!/1
                )

  @ipv6_global InetCidr.parse_cidr!("2000::/3")
  @ipv6_blocked Enum.map(
                  [
                    "::/128",
                    "::1/128",
                    "::ffff:0:0/96",
                    "64:ff9b::/96",
                    "64:ff9b:1::/48",
                    "100::/64",
                    "2001::/23",
                    "2001:db8::/32",
                    "2002::/16",
                    "fc00::/7",
                    "fe80::/10",
                    "fec0::/10",
                    "ff00::/8"
                  ],
                  &InetCidr.parse_cidr!/1
                )

  @spec prepare(String.t(), keyword()) :: {:ok, Destination.t()} | {:error, FetchError.t()}
  def prepare(url, opts \\ [])

  def prepare(url, opts) when is_binary(url) do
    resolver = Keyword.get(opts, :resolver, &default_resolver/2)

    with {:ok, uri} <- validate_url(url),
         {:ok, addresses} <- resolve_all(uri.host, resolver),
         :ok <- validate_all_public(addresses),
         selected_address <- hd(addresses),
         {:ok, transport_url} <- transport_url(uri, selected_address) do
      {:ok,
       %Destination{
         logical_uri: uri,
         logical_url: URI.to_string(uri),
         selected_address: selected_address,
         transport_url: transport_url,
         host_header: host_header(uri)
       }}
    end
  end

  def prepare(_url, _opts), do: error(:invalid_url, :url_validation)

  @spec validate_url(String.t()) :: {:ok, URI.t()} | {:error, FetchError.t()}
  def validate_url(url) do
    with true <- url != "" and url == String.trim(url),
         {:ok, uri} <- URI.new(url),
         :ok <- validate_scheme(uri),
         :ok <- validate_credentials(uri),
         :ok <- validate_host(uri),
         :ok <- validate_port(uri) do
      {:ok, %{uri | fragment: nil}}
    else
      false -> error(:invalid_url, :url_validation)
      {:error, %FetchError{} = fetch_error} -> {:error, fetch_error}
      {:error, _reason} -> error(:invalid_url, :url_validation)
    end
  end

  @spec public_address?(:inet.ip_address()) :: boolean()
  def public_address?({_, _, _, _} = address) do
    :inet.is_ip_address(address) and
      not Enum.any?(@ipv4_blocked, &InetCidr.contains?(&1, address))
  end

  def public_address?({0, 0, 0, 0, 0, 65_535, high, low}) do
    embedded_ipv4 = {
      Bitwise.bsr(high, 8),
      Bitwise.band(high, 0xFF),
      Bitwise.bsr(low, 8),
      Bitwise.band(low, 0xFF)
    }

    _embedded_address_is_public = public_address?(embedded_ipv4)
    false
  end

  def public_address?({_, _, _, _, _, _, _, _} = address) do
    :inet.is_ip_address(address) and
      InetCidr.contains?(@ipv6_global, address) and
      not Enum.any?(@ipv6_blocked, &InetCidr.contains?(&1, address))
  end

  def public_address?(_address), do: false

  defp validate_scheme(%URI{scheme: scheme}) when scheme in ["http", "https"], do: :ok
  defp validate_scheme(%URI{scheme: nil}), do: error(:invalid_url, :url_validation)
  defp validate_scheme(_uri), do: error(:unsupported_scheme, :url_validation)

  defp validate_credentials(%URI{userinfo: nil}), do: :ok
  defp validate_credentials(_uri), do: error(:credentials_not_allowed, :url_validation)

  defp validate_host(%URI{host: host}) when is_binary(host) and host != "" do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} ->
        if :inet.is_ip_address(address), do: :ok, else: error(:invalid_url, :url_validation)

      {:error, :einval} ->
        if valid_dns_name?(host), do: :ok, else: error(:invalid_url, :url_validation)
    end
  end

  defp validate_host(_uri), do: error(:invalid_url, :url_validation)

  defp valid_dns_name?(host) do
    normalized = String.trim_trailing(host, ".")

    byte_size(normalized) in 1..253 and
      String.match?(normalized, ~r/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*$/) and
      normalized
      |> String.split(".")
      |> Enum.all?(fn label ->
        byte_size(label) in 1..63 and not String.starts_with?(label, "-") and
          not String.ends_with?(label, "-")
      end)
  end

  defp validate_port(%URI{scheme: "https", port: 443}), do: :ok
  defp validate_port(%URI{scheme: "http", port: 80}), do: :ok
  defp validate_port(_uri), do: error(:port_not_allowed, :url_validation)

  defp resolve_all(host, resolver) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} ->
        {:ok, [address]}

      {:error, :einval} ->
        with {:ok, ipv4} <- resolve_family(resolver, host, :inet),
             {:ok, ipv6} <- resolve_family(resolver, host, :inet6),
             addresses <- Enum.uniq(ipv4 ++ ipv6),
             false <- addresses == [] do
          {:ok, addresses}
        else
          true -> error(:dns_failure, :dns_resolution)
          {:error, %FetchError{} = fetch_error} -> {:error, fetch_error}
        end
    end
  end

  defp resolve_family(resolver, host, family) do
    case resolver.(host, family) do
      {:ok, addresses} when is_list(addresses) ->
        if Enum.all?(addresses, &:inet.is_ip_address/1) do
          {:ok, addresses}
        else
          error(:dns_failure, :dns_resolution)
        end

      {:error, :nxdomain} ->
        {:ok, []}

      _other ->
        error(:dns_failure, :dns_resolution)
    end
  rescue
    _exception -> error(:dns_failure, :dns_resolution)
  end

  defp validate_all_public(addresses) do
    if Enum.all?(addresses, &public_address?/1) do
      :ok
    else
      error(:blocked_destination, :address_validation)
    end
  end

  defp transport_url(uri, address) do
    ip = address |> :inet.ntoa() |> List.to_string()
    {:ok, URI.to_string(%{uri | host: ip})}
  rescue
    _exception -> error(:invalid_url, :transport_uri)
  end

  defp host_header(%URI{host: host, scheme: scheme, port: port})
       when (scheme == "https" and port == 443) or (scheme == "http" and port == 80),
       do: bracket_ipv6(host)

  defp host_header(%URI{host: host, port: port}), do: "#{bracket_ipv6(host)}:#{port}"

  defp bracket_ipv6(host) do
    if String.contains?(host, ":"), do: "[#{host}]", else: host
  end

  defp default_resolver(host, family), do: :inet.getaddrs(String.to_charlist(host), family)

  defp error(reason, stage) do
    {:error,
     %FetchError{
       reason: reason,
       stage: stage,
       message: error_message(reason)
     }}
  end

  defp error_message(:invalid_url), do: "Enter a valid public URL."
  defp error_message(:unsupported_scheme), do: "Only HTTP and HTTPS URLs are supported."
  defp error_message(:credentials_not_allowed), do: "URLs containing credentials are not allowed."
  defp error_message(:port_not_allowed), do: "The URL uses a port that is not allowed."
  defp error_message(:dns_failure), do: "The URL's network destination could not be resolved."

  defp error_message(:blocked_destination),
    do: "The URL does not resolve exclusively to public network addresses."
end
