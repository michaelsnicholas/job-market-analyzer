defmodule JobMarketAnalyzer.JobMarket.SourceAcquisition.HTMLText do
  @moduledoc false

  @block_tags ~w(address article aside blockquote dd div dl dt fieldset figcaption figure footer
                  h1 h2 h3 h4 h5 h6 header hr li main nav ol p pre section table tbody td
                  tfoot th thead tr ul)
  @discard_tags ~w(script style form nav footer dialog template noscript iframe svg canvas)

  @spec extract(Floki.html_tree() | [Floki.html_tree()]) :: String.t()
  def extract(tree) do
    tree
    |> render()
    |> IO.iodata_to_binary()
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.replace(~r/[\t\f ]+/u, " ")
    |> String.replace(~r/ *\n */u, "\n")
    |> String.replace(~r/\n{3,}/u, "\n\n")
    |> String.trim()
  end

  defp render(nodes) when is_list(nodes), do: Enum.map(nodes, &render/1)
  defp render(text) when is_binary(text), do: String.replace(text, ~r/\s+/u, " ")
  defp render({:comment, _text}), do: []
  defp render({:doctype, _name, _public, _system}), do: []

  defp render({tag, _attrs, _children}) when tag in @discard_tags, do: []

  defp render({"br", _attrs, _children}), do: "\n"

  defp render({"ol", attrs, children}) do
    if hidden?(attrs), do: [], else: ["\n\n", render_ordered(children), "\n\n"]
  end

  defp render({"li", attrs, children}),
    do: if(hidden?(attrs), do: [], else: ["\n", render_list_item("- ", children)])

  defp render({tag, attrs, children}) when tag in @block_tags do
    if hidden?(attrs), do: [], else: ["\n\n", render(children), "\n\n"]
  end

  defp render({_tag, attrs, children}) do
    if hidden?(attrs), do: [], else: render(children)
  end

  defp render(_other), do: []

  defp render_ordered(children) do
    {rendered, _next_number} =
      Enum.map_reduce(children, 1, fn
        {"li", attrs, item_children}, number ->
          item =
            if hidden?(attrs),
              do: [],
              else: ["\n", render_list_item("#{number}. ", item_children)]

          {item, number + 1}

        node, number ->
          {render(node), number}
      end)

    rendered
  end

  defp render_list_item(marker, children) do
    content = children |> render() |> IO.iodata_to_binary() |> String.trim()
    [marker, content]
  end

  defp hidden?(attrs) do
    Enum.any?(attrs, fn
      {"hidden", _value} ->
        true

      {"aria-hidden", value} ->
        String.downcase(value) == "true"

      {"style", value} ->
        String.match?(value, ~r/(?:display\s*:\s*none|visibility\s*:\s*hidden)/i)

      _other ->
        false
    end)
  end
end
