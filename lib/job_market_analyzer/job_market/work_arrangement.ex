defmodule JobMarketAnalyzer.JobMarket.WorkArrangement do
  @moduledoc """
  Conservatively extracts explicitly offered work arrangements from job source text.

  Results are derived on demand and are not persisted. Evidence offsets are UTF-8
  byte offsets into the original source and use an exclusive end offset.
  """

  defmodule Evidence do
    @moduledoc """
    Exact source evidence for a deterministic work-arrangement rule.
    """

    @enforce_keys [:text, :start_byte, :end_byte, :rule]
    defstruct [:text, :start_byte, :end_byte, :rule]

    @type t :: %__MODULE__{
            text: String.t(),
            start_byte: non_neg_integer(),
            end_byte: non_neg_integer(),
            rule: atom()
          }
  end

  defmodule Result do
    @moduledoc """
    A known set of explicitly offered modes or a conservative unknown result.
    """

    @enforce_keys [
      :status,
      :arrangements,
      :evidence,
      :extractor_version,
      :unknown_reason
    ]
    defstruct [:status, :arrangements, :evidence, :extractor_version, :unknown_reason]

    @type arrangement :: :fully_remote | :hybrid | :on_site
    @type unknown_reason ::
            :no_explicit_evidence | :ambiguous_evidence | :contradictory_evidence

    @type t :: %__MODULE__{
            status: :known | :unknown,
            arrangements: [arrangement()],
            evidence: [Evidence.t()],
            extractor_version: pos_integer(),
            unknown_reason: unknown_reason() | nil
          }
  end

  alias __MODULE__.{Evidence, Result}

  @extractor_version 1
  @canonical_order [:fully_remote, :hybrid, :on_site]

  # Compound alternatives and hybrid definitions run first so their component
  # words cannot be misread as separately offered employment modes.
  @rules [
    {:explicit_hybrid_or_remote,
     ~r/\b(?:[A-Z]{2}\s+)?hybrid\s+or\s+(?:[A-Z]{2,4}\s+)?(?:fully\s+)?remote\b/iu,
     [:fully_remote, :hybrid]},
    {:explicit_hybrid_or_remote,
     ~r/\bhybrid\s+preferred\s*,\s*(?:fully\s+)?remote\s+considered\b/iu,
     [:fully_remote, :hybrid]},
    {:explicit_hybrid_definition, ~r/\bhybrid\s*\(\s*in[- ]person\s+and\s+remote\s*\)/iu,
     [:hybrid]},
    {:explicit_hybrid_definition, ~r/\bhybrid\s+on[- ]site\s*\/\s*remote\b/iu, [:hybrid]},
    {:explicit_hybrid_definition, ~r/\bhybrid\s+means\s+[^.\n;]*\boffice\b[^.\n;]*\bremote\b/iu,
     [:hybrid]},
    {:explicit_hybrid_split,
     ~r/\b(?:one|two|three|four|1|2|3|4)\s+days?\s+in\s+(?:the\s+)?office\s+and\s+(?:one|two|three|four|1|2|3|4)\s+(?:days?\s+)?(?:working\s+)?remotely\b/iu,
     [:hybrid]},
    {:explicit_hybrid_split,
     ~r/\bmostly\s+remote\b[^.\n;]*\b(?:office|on[- ]site|in[- ]person)\b/iu, [:hybrid]},
    {:explicit_hybrid, ~r/\bhybrid\s+remote\s*[\-–—]\s*[^\n.,;]+/iu, [:hybrid]},
    {:explicit_hybrid, ~r/\bhybrid\s+(?:role|position)\b/iu, [:hybrid]},
    {:explicit_hybrid, ~r/\b(?:this\s+)?(?:role|position)\s+(?:is|will\s+be)\s+hybrid\b/iu,
     [:hybrid]},
    {:explicit_on_site_metadata, ~r/\blocation\s+type\s*:\s*on[- ]site\b/iu, [:on_site]},
    {:explicit_on_site_all_days,
     ~r/\b(?:five|5)\s+days?\s+per\s+week\s+in\s+(?:the|our)\s+(?:[\p{L}-]+\s+){0,3}(?:office|hq)\b/iu,
     [:on_site]},
    {:explicit_on_site_all_days,
     ~r/\ball\s+(?:of\s+your\s+)?working\s+days?\s+in\s+(?:the|our)\s+(?:office|hq)\b/iu,
     [:on_site]},
    {:explicit_on_site,
     ~r/\b(?:you\s+will|this\s+(?:role|position)\s+(?:requires|will\s+require))\s+work\s+in[- ]person\s+at\s+(?:our|the)\s+(?:office|hq)\b/iu,
     [:on_site]},
    {:explicit_on_site, ~r/\bin[- ]person\s+work\s+at\s+(?:our|the)\s+(?:office|hq)\b/iu,
     [:on_site]},
    {:explicit_on_site,
     ~r/\b(?:this\s+)?(?:role|position)\s+(?:must|is\s+required\s+to)\s+be\s+on[- ]site\b/iu,
     [:on_site]},
    {:explicit_on_site,
     ~r/\bexpected\s+to\s+work\s+from\s+(?:our|the)\s+[^.\n;]*office\s+on\s+all\s+working\s+days\b/iu,
     [:on_site]},
    {:explicit_fully_remote,
     ~r/\bfully\s+remote\b(?!\s+(?:employees?|workers?|teams?|compan(?:y|ies)))/iu,
     [:fully_remote]},
    {:explicit_fully_remote, ~r/\b100\s*%\s+remote\b/iu, [:fully_remote]},
    {:explicit_fully_remote, ~r/\bremote\s+(?:role|position)\b/iu, [:fully_remote]},
    {:explicit_fully_remote, ~r/\b(?:this\s+)?(?:role|position)\s+(?:is|will\s+be)\s+remote\b/iu,
     [:fully_remote]},
    {:explicit_remote_with_qualifier, ~r/\bremote\s+from\s+anywhere\b/iu, [:fully_remote]},
    {:explicit_remote_with_qualifier, ~r/\bremote\s+(?:nationwide|worldwide)\b/iu,
     [:fully_remote]},
    {:explicit_remote_with_qualifier,
     ~r/\bremote\s+(?:in\s+)?(?:the\s+)?(?:U\.?S\.?(?:A\.?)?|United\s+States|New\s+York|NY)\b/iu,
     [:fully_remote]},
    {:explicit_remote_with_qualifier, ~r/\bremote\s+must\s+reside\s+in\s+[^.\n;,]+/iu,
     [:fully_remote]},
    {:explicit_remote_with_qualifier,
     ~r/\bremote\s*\(\s*(?:EST|CST|MST|PST|USA?\s+time\s+zones?|worldwide)(?:\s*\/\s*(?:EST|CST|MST|PST))*\s*\)/iu,
     [:fully_remote]},
    {:explicit_telecommute,
     ~r/\b(?:this\s+)?(?:role|position)\s+(?:is|will\s+be)\s+(?:fully\s+)?telecommut(?:e|ing)\b/iu,
     [:fully_remote]},
    {:explicit_work_from_home,
     ~r/\b(?:this\s+)?(?:role|position)\s+(?:is|will\s+be)\s+(?:a\s+)?work[- ]from[- ]home\b/iu,
     [:fully_remote]}
  ]

  @blocked_patterns [
    ~r/\bnot\s+(?:eligible\s+for\s+)?(?:fully\s+)?remote\b/iu,
    ~r/\bremote\s+work\s+is\s+not\s+available\b/iu,
    ~r/\bno\s+remote\s+option\b/iu,
    ~r/\btemporarily\s+(?:fully\s+)?remote\b/iu,
    ~r/\b(?:fully\s+)?remote\s+after\s+(?:probation|onboarding|training)\b/iu,
    ~r/\bhybrid\s+after\s+(?:probation|onboarding|training)\b/iu,
    ~r/\b(?:three|four|3|4)\s+days?\s+per\s+week\s+in\s+(?:the|our)\s+office\b/iu,
    ~r/\b(?:four|4)\s*(?:-|–|—)?\s*to\s*(?:-|–|—)?\s*(?:five|5)\s+days?\s+per\s+week\s+in\s+(?:the|our)\s+office\b/iu
  ]

  @ambiguous_patterns [
    ~r/\bnot\s+fully\s+remote\b/iu,
    ~r/\b(?:three|four|3|4)\s+days?\s+per\s+week\s+in\s+(?:the|our)\s+office\b/iu,
    ~r/\b(?:four|4)\s*(?:-|–|—)?\s*to\s*(?:-|–|—)?\s*(?:five|5)\s+days?\s+per\s+week\s+in\s+(?:the|our)\s+office\b/iu,
    ~r/\btemporarily\s+(?:fully\s+)?remote\b/iu,
    ~r/\b(?:fully\s+)?remote\s+after\s+(?:probation|onboarding|training)\b/iu,
    ~r/\bhybrid\s+after\s+(?:probation|onboarding|training)\b/iu,
    ~r/\bhome[- ]based\s+(?:role|position)\b/iu,
    ~r/\bfield[- ]based\s+(?:role|position)\b/iu
  ]

  @doc "Returns the current deterministic extractor version."
  def version, do: @extractor_version

  @doc "Extracts explicitly offered work arrangements from raw job source."
  @spec extract(String.t()) :: Result.t()
  def extract(source) when is_binary(source) do
    blocked_ranges = ranges_for(@blocked_patterns, source)

    candidates =
      @rules
      |> Enum.flat_map(&matches_for_rule(&1, source))
      |> Enum.reject(&overlaps_any?(&1.range, blocked_ranges))
      |> prefer_specific_matches()

    resolve(candidates, source)
  end

  defp matches_for_rule({rule, regex, arrangements}, source) do
    regex
    |> Regex.scan(source, return: :index, capture: :first)
    |> Enum.map(fn [{start_byte, length}] ->
      evidence = %Evidence{
        text: binary_part(source, start_byte, length),
        start_byte: start_byte,
        end_byte: start_byte + length,
        rule: rule
      }

      %{arrangements: arrangements, evidence: evidence, range: {start_byte, length}}
    end)
  end

  defp ranges_for(patterns, source) do
    Enum.flat_map(patterns, fn regex ->
      regex
      |> Regex.scan(source, return: :index, capture: :first)
      |> Enum.map(fn [{start_byte, length}] -> {start_byte, length} end)
    end)
  end

  defp prefer_specific_matches(candidates) do
    Enum.reduce(candidates, [], fn candidate, kept ->
      if overlaps_any?(candidate.range, Enum.map(kept, & &1.range)) do
        kept
      else
        kept ++ [candidate]
      end
    end)
  end

  defp overlaps_any?({start_byte, length}, ranges) do
    finish_byte = start_byte + length

    Enum.any?(ranges, fn {other_start, other_length} ->
      other_finish = other_start + other_length
      start_byte < other_finish and other_start < finish_byte
    end)
  end

  defp resolve([], source) do
    reason =
      if Enum.any?(@ambiguous_patterns, &Regex.match?(&1, source)) do
        :ambiguous_evidence
      else
        :no_explicit_evidence
      end

    unknown(reason)
  end

  defp resolve(candidates, _source) do
    arrangements =
      candidates
      |> Enum.flat_map(& &1.arrangements)
      |> canonicalize()

    explicitly_offered_sets =
      candidates
      |> Enum.map(&canonicalize(&1.arrangements))
      |> Enum.filter(&(length(&1) > 1))

    cond do
      length(arrangements) == 1 ->
        known(arrangements, candidates)

      arrangements in explicitly_offered_sets ->
        known(arrangements, candidates)

      true ->
        unknown(:contradictory_evidence)
    end
  end

  defp known(arrangements, candidates) do
    %Result{
      status: :known,
      arrangements: arrangements,
      evidence: Enum.map(candidates, & &1.evidence),
      extractor_version: @extractor_version,
      unknown_reason: nil
    }
  end

  defp unknown(reason) do
    %Result{
      status: :unknown,
      arrangements: [],
      evidence: [],
      extractor_version: @extractor_version,
      unknown_reason: reason
    }
  end

  defp canonicalize(arrangements) do
    Enum.filter(@canonical_order, &(&1 in arrangements))
  end
end
