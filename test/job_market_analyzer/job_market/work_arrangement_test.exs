defmodule JobMarketAnalyzer.JobMarket.WorkArrangementTest do
  use ExUnit.Case, async: true

  alias JobMarketAnalyzer.JobMarket.WorkArrangement

  describe "explicit fully remote arrangements" do
    test "recognizes direct remote language and geographic or time-zone qualifiers" do
      cases = [
        {"Fully Remote ML/AI Engineer", [:fully_remote]},
        {"Fully Remote/West Coast Hours", [:fully_remote]},
        {"Remote from anywhere", [:fully_remote]},
        {"Remote Nationwide", [:fully_remote]},
        {"remote U.S.", [:fully_remote]},
        {"Remote in New York", [:fully_remote]},
        {"Remote must reside in NY", [:fully_remote]},
        {"Remote (EST/CST)", [:fully_remote]},
        {"Remote (USA time zones)", [:fully_remote]},
        {"Remote (Worldwide)", [:fully_remote]},
        {"This role is fully telecommute", [:fully_remote]},
        {"This position is work-from-home", [:fully_remote]}
      ]

      for {source, arrangements} <- cases do
        assert_known(source, arrangements)
      end
    end
  end

  describe "explicit hybrid arrangements" do
    test "treats hybrid as its own mode even when remote and on-site words occur" do
      cases = [
        "Hybrid role",
        "This position is hybrid.",
        "Hybrid Remote – Massachusetts",
        "Hybrid Remote - Massachusetts",
        "Hybrid (In-person and Remote)",
        "Hybrid On-Site/Remote",
        "Hybrid means three days in the office and two remote"
      ]

      for source <- cases do
        assert_known(source, [:hybrid])
      end
    end

    test "recognizes an explicit office and remote split" do
      assert_known("Three days in the office and two working remotely", [:hybrid])
      assert_known("Mostly remote with one required office day each month", [:hybrid])
    end
  end

  describe "explicit on-site arrangements" do
    test "recognizes structured, role-directed, and all-days evidence" do
      cases = [
        "Location Type: On-site",
        "You will work in person at our HQ",
        "In-person work at our office",
        "This role must be on-site",
        "five days per week in the office",
        "all working days in our office"
      ]

      for source <- cases do
        assert_known(source, [:on_site])
      end
    end
  end

  describe "explicitly offered alternatives" do
    test "preserves distinct hybrid and fully remote options in canonical order" do
      cases = [
        "NY hybrid or EST remote",
        "Hybrid or fully remote",
        "Hybrid preferred, remote considered"
      ]

      for source <- cases do
        assert_known(source, [:fully_remote, :hybrid])
      end
    end
  end

  describe "negation and conservative unknowns" do
    test "does not treat a negated remote mention as a positive fact" do
      assert_known(
        "This role is not remote and requires five days per week in our London office.",
        [:on_site]
      )
    end

    test "returns ambiguous for insufficient, partial-week, and conditional evidence" do
      cases = [
        "This role is not fully remote.",
        "three days per week in the office",
        "four days per week in our office",
        "four-to-five days per week in the office",
        "2–3 days a week in the office",
        "2-3 days per week in office",
        "2—3 days each week at our office",
        "three days a week at the office",
        "This role is based in our London office and will require you to be in the office 2–3 days a week.",
        "temporarily remote",
        "temporarily fully remote",
        "remote after probation",
        "fully remote after probation",
        "remote after onboarding",
        "hybrid after training",
        "This is a home-based role.",
        "This is a field-based position."
      ]

      for source <- cases do
        assert_unknown(source, :ambiguous_evidence)
      end
    end

    test "returns no explicit evidence for contextual clues and boilerplate" do
      cases = [
        "Position based in London.",
        "Location: Amsterdam.",
        "You'll join our New York team.",
        "We value face-to-face collaboration.",
        "We're a distributed team.",
        "We're a remote-first company.",
        "Our remote employees receive an equipment allowance.",
        "Flexible working available.",
        "We support flexible work."
      ]

      for source <- cases do
        assert_unknown(source, :no_explicit_evidence)
      end
    end

    test "returns contradictory when separate explicit statements conflict" do
      assert_unknown(
        "This role is fully remote. Location Type: On-site.",
        :contradictory_evidence
      )
    end
  end

  describe "result contract" do
    test "uses canonical order and deduplicates arrangements" do
      result =
        WorkArrangement.extract(
          "Hybrid or fully remote. This role is fully remote. This position is hybrid."
        )

      assert result.status == :known
      assert result.arrangements == [:fully_remote, :hybrid]
    end

    test "reports extractor version one" do
      assert WorkArrangement.version() == 1
      assert WorkArrangement.extract("Location Type: On-site").extractor_version == 1
      assert WorkArrangement.extract("Location: Central City").extractor_version == 1
    end

    test "preserves exact Unicode source evidence with UTF-8 byte offsets" do
      source = "Intro ☕\nHybrid Remote — Massachusetts\nClosing"
      result = WorkArrangement.extract(source)

      assert result.status == :known
      assert result.arrangements == [:hybrid]

      for evidence <- result.evidence do
        assert evidence.text ==
                 binary_part(
                   source,
                   evidence.start_byte,
                   evidence.end_byte - evidence.start_byte
                 )
      end
    end

    test "matches capitalization and Unicode dash variants" do
      assert_known("HYBRID REMOTE — MASSACHUSETTS", [:hybrid])
      assert_known("hybrid remote – massachusetts", [:hybrid])
    end
  end

  defp assert_known(source, expected_arrangements) do
    result = WorkArrangement.extract(source)

    assert result.status == :known, "expected known result for #{inspect(source)}"
    assert result.arrangements == expected_arrangements
    assert result.unknown_reason == nil
    assert result.evidence != []
    assert result.extractor_version == 1

    for evidence <- result.evidence do
      assert is_atom(evidence.rule)

      assert evidence.text ==
               binary_part(source, evidence.start_byte, evidence.end_byte - evidence.start_byte)
    end
  end

  defp assert_unknown(source, expected_reason) do
    result = WorkArrangement.extract(source)

    assert result.status == :unknown, "expected unknown result for #{inspect(source)}"
    assert result.arrangements == []
    assert result.evidence == []

    assert result.unknown_reason == expected_reason,
           "unexpected unknown reason for #{inspect(source)}"

    assert result.extractor_version == 1
  end
end
