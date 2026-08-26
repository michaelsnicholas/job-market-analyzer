defmodule JobMarketAnalyzer.JobMarket.SourceAcquisition.Extractor do
  @moduledoc false

  alias JobMarketAnalyzer.JobMarket.SourceAcquisition.{
    Draft,
    ExtractionError,
    FetchResult,
    HTMLText,
    Suggestion
  }

  @extractor_version 2
  @minimum_useful_bytes 40
  @short_source_bytes 200
  @minimum_continuation_bytes 200
  @html_types ["text/html", "application/xhtml+xml"]
  @json_types ["application/json", "application/ld+json"]
  @preferred_generic_roots ["[class~='job__description']"]
  @generic_roots [
    "main",
    "article",
    "[role=main]",
    "[class*='job-description']",
    "[class*='job_description']",
    "[id*='job-description']",
    "[id*='job_description']"
  ]
  @noise_selectors [
    "script",
    "style",
    "form",
    "nav",
    "footer",
    "dialog",
    "template",
    "noscript",
    "iframe",
    "svg",
    "canvas",
    "[hidden]",
    "[aria-hidden='true']",
    "[role='dialog']",
    "[aria-modal='true']",
    "[class*='cookie']",
    "[id*='cookie']",
    "[class*='modal']",
    "[id*='modal']"
  ]
  @warning_order [
    :generic_extraction,
    :multiple_job_postings,
    :short_source,
    :metadata_conflict,
    :possible_boilerplate
  ]
  @authentication_signals [
    ~r/\bsign[ -]?in\b/iu,
    ~r/\blog[ -]?in\b/iu,
    ~r/\bjoin now\b/iu,
    ~r/\bcreate (?:an? )?account\b/iu,
    ~r/\bcontinue with (?:google|apple)\b/iu,
    ~r/\bpassword\b/iu,
    ~r/\bforgot (?:your )?password\b/iu,
    ~r/\bone[ -]?time (?:link|code)\b/iu,
    ~r/\bverification code\b/iu,
    ~r/\bcheck your (?:email|inbox)\b/iu,
    ~r/\bresend(?: email| code| link)?\b/iu,
    ~r/\bagree (?:&|and) join\b/iu,
    ~r/\baccount (?:is )?required\b/iu
  ]
  @job_content_signals [
    ~r/\b(?:job|position|role) (?:description|overview|summary)\b/iu,
    ~r/\b(?:responsibilities|qualifications|requirements)\b/iu,
    ~r/\bwhat you(?:'|’)ll do\b/iu,
    ~r/\b(?:required|preferred) (?:skills|experience|qualifications)\b/iu,
    ~r/\b(?:compensation|salary range|benefits)\b/iu,
    ~r/\bequal opportunity employer\b/iu
  ]
  @job_section_heading ~r/\b(?:responsibilit(?:y|ies)|qualifications?|requirements?|what you(?:'|’)ll do|about you|compensation|benefits?|dut(?:y|ies)|skills?|experience|the role)\b/iu

  @spec version() :: pos_integer()
  def version, do: @extractor_version

  @spec extract(FetchResult.t()) :: {:ok, Draft.t()} | {:error, ExtractionError.t()}
  def extract(%FetchResult{content_type: content_type} = result)
      when content_type in @html_types do
    extract_html(result)
  end

  def extract(%FetchResult{content_type: content_type} = result)
      when content_type in @json_types do
    extract_json(result)
  end

  def extract(%FetchResult{content_type: "text/plain"} = result) do
    text = normalize_plain_text(result.body)

    if useful?(text) do
      {:ok, draft(result, text, :plain_text, nil, nil, short_warning(text))}
    else
      inadequate()
    end
  end

  def extract(%FetchResult{}),
    do: error(:unsupported_source, "The fetched source cannot be extracted.")

  defp extract_html(result) do
    with {:ok, document} <- Floki.parse_document(result.body) do
      page_metadata = page_metadata(document)

      document
      |> json_ld_values()
      |> job_postings()
      |> select_job_posting(page_metadata)
      |> case do
        {:ok, posting, warnings} ->
          build_structured_draft(result, posting, warnings, document)

        :none ->
          build_generic_draft(result, document, page_metadata)

        {:error, :ambiguous_job_postings} ->
          error(:ambiguous_job_postings, "The source contains multiple ambiguous job postings.")
      end
    else
      _error -> inadequate()
    end
  end

  defp extract_json(result) do
    with {:ok, decoded} <- Jason.decode(result.body) do
      decoded
      |> job_postings()
      |> select_job_posting(%{})
      |> case do
        {:ok, posting, warnings} ->
          build_structured_draft(result, posting, warnings)

        :none ->
          inadequate()

        {:error, :ambiguous_job_postings} ->
          error(:ambiguous_job_postings, "The source contains multiple ambiguous job postings.")
      end
    else
      _error -> inadequate()
    end
  end

  defp json_ld_values(document) do
    document
    |> Floki.find("script[type='application/ld+json']")
    |> Enum.flat_map(fn script ->
      case script |> script_content() |> Jason.decode() do
        {:ok, value} -> [value]
        {:error, _reason} -> []
      end
    end)
  end

  defp script_content({"script", _attrs, children}) do
    children
    |> Enum.filter(&is_binary/1)
    |> IO.iodata_to_binary()
  end

  defp job_postings(value), do: collect_job_postings(value, []) |> Enum.reverse()

  defp collect_job_postings(values, acc) when is_list(values) do
    Enum.reduce(values, acc, &collect_job_postings/2)
  end

  defp collect_job_postings(value, acc) when is_map(value) do
    acc = if job_posting?(value), do: [value | acc], else: acc
    Enum.reduce(Map.values(value), acc, &collect_job_postings/2)
  end

  defp collect_job_postings(_value, acc), do: acc

  defp job_posting?(%{"@type" => type}) when is_binary(type),
    do: String.downcase(type) == "jobposting"

  defp job_posting?(%{"@type" => types}) when is_list(types),
    do: Enum.any?(types, &(is_binary(&1) and String.downcase(&1) == "jobposting"))

  defp job_posting?(_value), do: false

  defp select_job_posting(postings, metadata) do
    usable = Enum.filter(postings, &usable_posting?/1)

    case usable do
      [] -> :none
      [posting] -> {:ok, posting, []}
      postings -> disambiguate(postings, metadata)
    end
  end

  defp usable_posting?(posting) do
    with description when is_binary(description) <- posting["description"],
         {:ok, fragment} <- Floki.parse_fragment(description) do
      fragment |> HTMLText.extract() |> useful?()
    else
      _other -> false
    end
  end

  defp disambiguate(postings, metadata) do
    reference_titles =
      [metadata[:h1], metadata[:og_title], metadata[:title]]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&normalize_comparison/1)

    matches =
      Enum.filter(postings, fn posting ->
        title = normalize_comparison(posting["title"])
        title != "" and Enum.any?(reference_titles, &title_match?(title, &1))
      end)

    case matches do
      [posting] -> {:ok, posting, [:multiple_job_postings]}
      _other -> {:error, :ambiguous_job_postings}
    end
  end

  defp title_match?(title, metadata_title),
    do: title == metadata_title or String.contains?(metadata_title, title)

  defp build_structured_draft(result, posting, warnings, document \\ nil) do
    with {:ok, fragment} <- Floki.parse_fragment(posting["description"]),
         structured_text when is_binary(structured_text) <- HTMLText.extract(fragment),
         true <- useful?(structured_text) do
      company = suggestion(get_in(posting, ["hiringOrganization", "name"]), :job_posting_json_ld)
      role = suggestion(posting["title"], :job_posting_json_ld)
      {text, method} = reconcile_structured_description(document, structured_text)

      {:ok, draft(result, text, method, company, role, warnings ++ short_warning(text))}
    else
      _other -> inadequate()
    end
  end

  defp build_generic_draft(result, document, metadata) do
    cleaned = clean_document(document)
    {root, body_fallback?} = select_generic_root(cleaned)
    text = HTMLText.extract(root)

    if useful?(text) and not unusable_interstitial?(metadata, text) do
      {company, role, metadata_warnings} = metadata_suggestions(metadata)

      warnings =
        [:generic_extraction]
        |> maybe_add(body_fallback?, :possible_boilerplate)
        |> Kernel.++(metadata_warnings)
        |> Kernel.++(short_warning(text))

      {:ok, draft(result, text, :generic_html, company, role, warnings)}
    else
      inadequate()
    end
  end

  defp reconcile_structured_description(nil, structured_text),
    do: {structured_text, :job_posting_json_ld}

  defp reconcile_structured_description(document, structured_text) do
    case anchor_paths(clean_document(document), structured_text) do
      [path] ->
        case reconciled_region(path) do
          nil -> {structured_text, :job_posting_json_ld}
          text -> {text, :job_posting_json_ld_reconciled}
        end

      _other ->
        {structured_text, :job_posting_json_ld}
    end
  end

  defp anchor_paths(nodes, target) when is_list(nodes) do
    nodes
    |> Enum.with_index()
    |> Enum.flat_map(fn {node, index} -> anchor_paths(node, target, [{node, index}]) end)
  end

  defp anchor_paths({_, _, children} = node, target, path) do
    descendant_paths =
      children
      |> Enum.with_index()
      |> Enum.flat_map(fn {child, index} ->
        anchor_paths(child, target, path ++ [{child, index}])
      end)

    cond do
      descendant_paths != [] -> descendant_paths
      HTMLText.extract(node) == target -> [path]
      true -> []
    end
  end

  defp anchor_paths(_node, _target, _path), do: []

  defp reconciled_region(path) do
    path
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn
      {{segment, segment_index}, path_index} when path_index > 0 ->
        {parent, _parent_index} = Enum.at(path, path_index - 1)
        reconcile_with_following_siblings(segment, segment_index, parent)

      _root ->
        nil
    end)
  end

  defp reconcile_with_following_siblings(segment, segment_index, {_, _, children}) do
    {continuation, stats} =
      children
      |> Enum.drop(segment_index + 1)
      |> Enum.reduce_while({[], continuation_stats()}, fn node, {nodes, stats} ->
        case continuation_node(node) do
          :empty ->
            {:cont, {[node | nodes], stats}}

          {:content, kind, text} ->
            {:cont, {[node | nodes], update_continuation_stats(stats, kind, text)}}

          :boundary ->
            {:halt, {nodes, stats}}
        end
      end)

    if coherent_continuation?(stats) do
      continuation = continuation |> Enum.reverse() |> trim_trailing_empty()
      HTMLText.extract([segment | continuation])
    end
  end

  defp continuation_stats do
    %{bytes: 0, blocks: 0, headings: 0, recognized_headings: 0, supporting_blocks: 0}
  end

  defp continuation_node(text) when is_binary(text) do
    if String.trim(text) == "", do: :empty, else: :boundary
  end

  defp continuation_node({tag, _attrs, _children} = node)
       when tag in ["h2", "h3", "h4", "h5", "h6"] do
    case HTMLText.extract(node) do
      "" -> :empty
      text -> {:content, :heading, text}
    end
  end

  defp continuation_node({"p", _attrs, _children} = node) do
    case HTMLText.extract(node) do
      text when byte_size(text) >= 20 -> {:content, :supporting, text}
      "" -> :empty
      _short -> :boundary
    end
  end

  defp continuation_node({tag, _attrs, _children} = node) when tag in ["ul", "ol"] do
    text = HTMLText.extract(node)

    if byte_size(text) >= 40 and Floki.find(node, "li") != [] do
      {:content, :supporting, text}
    else
      :boundary
    end
  end

  defp continuation_node(node) do
    if HTMLText.extract(node) == "", do: :empty, else: :boundary
  end

  defp update_continuation_stats(stats, :heading, text) do
    stats
    |> Map.update!(:bytes, &(&1 + byte_size(text)))
    |> Map.update!(:blocks, &(&1 + 1))
    |> Map.update!(:headings, &(&1 + 1))
    |> Map.update!(
      :recognized_headings,
      &(&1 + if(Regex.match?(@job_section_heading, text), do: 1, else: 0))
    )
  end

  defp update_continuation_stats(stats, :supporting, text) do
    stats
    |> Map.update!(:bytes, &(&1 + byte_size(text)))
    |> Map.update!(:blocks, &(&1 + 1))
    |> Map.update!(:supporting_blocks, &(&1 + 1))
  end

  defp coherent_continuation?(stats) do
    stats.bytes >= @minimum_continuation_bytes and stats.blocks >= 3 and
      stats.supporting_blocks >= 1 and
      (stats.recognized_headings >= 1 or
         (stats.headings >= 2 and stats.supporting_blocks >= 2 and stats.bytes >= 500))
  end

  defp trim_trailing_empty(nodes) do
    nodes
    |> Enum.reverse()
    |> Enum.drop_while(&(HTMLText.extract(&1) == ""))
    |> Enum.reverse()
  end

  defp clean_document(document),
    do: Floki.filter_out(document, Enum.join(@noise_selectors, ","))

  defp select_generic_root(document) do
    candidates = generic_candidates(document, @preferred_generic_roots)

    candidates =
      if candidates == [], do: generic_candidates(document, @generic_roots), else: candidates

    case Enum.max_by(candidates, &elem(&1, 1), fn -> nil end) do
      {node, _score} -> {node, false}
      nil -> {Floki.find(document, "body"), true}
    end
  end

  defp generic_candidates(document, selectors) do
    selectors
    |> Enum.flat_map(&Floki.find(document, &1))
    |> Enum.uniq()
    |> Enum.map(&{&1, generic_score(&1)})
    |> Enum.filter(fn {_node, score} -> score >= @minimum_useful_bytes end)
  end

  defp generic_score(node) do
    text_bytes = node |> HTMLText.extract() |> byte_size()
    blocks = Floki.find(node, "h1,h2,h3,p,li") |> length()
    text_bytes + blocks * 40
  end

  defp page_metadata(document) do
    %{
      title: first_text(document, "title"),
      og_title: first_attribute(document, "meta[property='og:title']", "content"),
      h1: unique_text(document, "h1")
    }
  end

  defp metadata_suggestions(metadata) do
    case confirmed_job_application_title(metadata) do
      {role, company} ->
        {suggestion(company, :page_metadata), suggestion(role, :page_metadata), []}

      nil when not is_nil(metadata.title) ->
        if job_application_title?(metadata.title) do
          {nil, nil, [:metadata_conflict]}
        else
          metadata_suggestions_from_titles(metadata)
        end

      nil ->
        metadata_suggestions_from_titles(metadata)
    end
  end

  defp confirmed_job_application_title(%{title: title, h1: h1, og_title: og_title})
       when is_binary(title) and is_binary(h1) do
    with {role, company} <- parse_job_application_title(title),
         true <- normalize_comparison(role) == normalize_comparison(h1),
         true <- is_nil(og_title) or normalize_comparison(og_title) == normalize_comparison(role) do
      {String.trim(role), String.trim(company)}
    else
      _other -> nil
    end
  end

  defp confirmed_job_application_title(_metadata), do: nil

  defp job_application_title?(title), do: not is_nil(parse_job_application_title(title))

  defp parse_job_application_title(title) do
    case Regex.run(
           ~r/^Job Application for (.+) at (.+)$/iu,
           title,
           capture: :all_but_first
         ) do
      [role, company] -> {role, company}
      _other -> nil
    end
  end

  defp metadata_suggestions_from_titles(metadata) do
    parsed =
      [metadata[:og_title], metadata[:title]]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&split_role_company/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case parsed do
      [{role, company}] ->
        if metadata[:h1] && normalize_comparison(metadata[:h1]) != normalize_comparison(role) do
          {nil, nil, [:metadata_conflict]}
        else
          {suggestion(company, :page_metadata), suggestion(role, :page_metadata), []}
        end

      [] ->
        {nil, suggestion(metadata[:h1], :page_metadata), []}

      _conflicting ->
        {nil, nil, [:metadata_conflict]}
    end
  end

  defp split_role_company(value) do
    case Regex.run(~r/^(.+?)\s+(?:at|@)\s+(.+)$/iu, value, capture: :all_but_first) do
      [role, company] -> {String.trim(role), String.trim(company)}
      _other -> split_delimited_title(value)
    end
  end

  defp split_delimited_title(value) do
    case String.split(value, ~r/\s+[|·]\s+/u, parts: 2) do
      [role, company] -> {String.trim(role), String.trim(company)}
      _other -> nil
    end
  end

  defp unique_text(document, selector) do
    case document
         |> Floki.find(selector)
         |> Enum.map(&clean_text/1)
         |> Enum.reject(&(&1 == ""))
         |> Enum.uniq() do
      [value] -> value
      _other -> nil
    end
  end

  defp first_text(document, selector) do
    document |> Floki.find(selector) |> List.first() |> clean_text()
  end

  defp first_attribute(document, selector, attribute) do
    document
    |> Floki.find(selector)
    |> Floki.attribute(attribute)
    |> List.first()
    |> clean_string()
  end

  defp clean_text(nil), do: nil
  defp clean_text(node), do: node |> Floki.text() |> clean_string()

  defp suggestion(value, source) do
    case clean_string(value) do
      nil -> nil
      value -> %Suggestion{value: value, source: source}
    end
  end

  defp clean_string(value) when is_binary(value) do
    case value |> String.replace(~r/\s+/u, " ") |> String.trim() do
      "" -> nil
      value -> value
    end
  end

  defp clean_string(_value), do: nil

  defp normalize_comparison(value) do
    case clean_string(value) do
      nil -> ""
      value -> String.downcase(value)
    end
  end

  defp normalize_plain_text(text) do
    text
    |> String.replace(~r/[\t\f\v ]+/u, " ")
    |> String.replace(~r/ *\n */u, "\n")
    |> String.replace(~r/\n{3,}/u, "\n\n")
    |> String.trim()
  end

  defp unusable_interstitial?(metadata, text) do
    heading = normalize_comparison(Enum.join([metadata[:title], metadata[:h1]], " "))
    body = normalize_comparison(text)

    challenge_language?(heading) or
      (byte_size(text) < 500 and challenge_language?(body)) or
      authentication_page?(body)
  end

  defp challenge_language?(text) do
    String.contains?(text, [
      "verify you are human",
      "checking your browser before accessing",
      "enable javascript and cookies to continue",
      "complete the captcha to continue"
    ])
  end

  defp authentication_page?(text) do
    signal_count = Enum.count(@authentication_signals, &Regex.match?(&1, text))
    job_content? = Enum.any?(@job_content_signals, &Regex.match?(&1, text))

    signal_count >= 3 and not job_content? and
      (signal_count >= 4 or byte_size(text) < 1_200)
  end

  defp useful?(text), do: byte_size(text) >= @minimum_useful_bytes
  defp short_warning(text) when byte_size(text) < @short_source_bytes, do: [:short_source]
  defp short_warning(_text), do: []

  defp draft(result, text, method, company, role, warnings) do
    %Draft{
      company: company,
      role: role,
      raw_description: text,
      original_extracted_text: text,
      source_url: result.requested_url,
      final_source_url: result.final_url,
      source_acquired_at: result.fetched_at,
      source_acquisition_method: method,
      source_extractor_version: @extractor_version,
      warnings: canonical_warnings(warnings)
    }
  end

  defp canonical_warnings(warnings) do
    warnings
    |> Enum.uniq()
    |> Enum.sort_by(&Enum.find_index(@warning_order, fn known -> known == &1 end))
  end

  defp maybe_add(warnings, true, warning), do: warnings ++ [warning]
  defp maybe_add(warnings, false, _warning), do: warnings

  defp inadequate,
    do: error(:inadequate_extraction, "The source did not contain enough useful job text.")

  defp error(reason, message),
    do: {:error, %ExtractionError{reason: reason, stage: :extraction, message: message}}
end
