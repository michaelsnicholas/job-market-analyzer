defmodule JobMarketAnalyzer.JobMarket.SourceAcquisition.HTMLTextTest do
  use ExUnit.Case, async: true

  alias JobMarketAnalyzer.JobMarket.SourceAcquisition.HTMLText

  test "preserves headings, paragraphs, and unordered-list boundaries" do
    html = """
    <h2>The role</h2>
    <p>Design the organisational architecture and culture to scale.</p>
    <p>Improve information and data flow across the organisation.</p>
    <h2>Core skills</h2>
    <ul><li>First-principles thinking</li><li>Program strategy</li></ul>
    """

    assert extract(html) ==
             """
             The role

             Design the organisational architecture and culture to scale.

             Improve information and data flow across the organisation.

             Core skills

             - First-principles thinking
             - Program strategy
             """
             |> String.trim()
  end

  test "numbers ordered-list items without adding breaks inside inline markup" do
    html = """
    <p>Work with <strong>engineering</strong>, <em>design</em>, and <a href="/teams">operations teams</a>.</p>
    <ol><li>Assess the current system</li><li>Build a <strong>clear</strong> plan</li></ol>
    """

    assert extract(html) ==
             """
             Work with engineering, design, and operations teams.

             1. Assess the current system
             2. Build a clear plan
             """
             |> String.trim()
  end

  test "keeps markers attached when list text is wrapped in blocks or inline formatting" do
    html = """
    <h2>Requirements</h2>
    <ul>
      <li><p><strong>Remote work:</strong> Available throughout the <a href="/locations">United States</a></p></li>
      <li><p>Collaborate with <em>engineering</em> and operations.</p></li>
    </ul>
    <ol><li><p>Review the program</p></li><li><p>Publish the plan</p></li></ol>
    """

    text = extract(html)

    assert text =~ "Requirements\n\n- Remote work: Available throughout the United States"
    assert text =~ "- Collaborate with engineering and operations."
    assert text =~ "1. Review the program\n2. Publish the plan"
    refute text =~ ~r/(?:-|\d+\.)\s*\n\n/u
  end

  test "retains multiple blocks and nested-list content in source order" do
    html = """
    <ul>
      <li>
        <p>First paragraph of the item.</p>
        <p>Additional explanation.</p>
        <ul><li><span>Nested detail one</span></li><li>Nested detail two</li></ul>
      </li>
      <li>Following top-level item.</li>
    </ul>
    """

    assert extract(html) ==
             """
             - First paragraph of the item.

             Additional explanation.

             - Nested detail one
             - Nested detail two
             - Following top-level item.
             """
             |> String.trim()
  end

  test "preserves Unicode while normalizing insignificant whitespace and blank lines" do
    html = """
    <h2>Specifics — London</h2>


    <p>
      £80–100k   base salary with   meaningful share options.
    </p>



    <p>Office attendance: 2–3 days a week.</p>
    """

    assert extract(html) ==
             """
             Specifics — London

             £80–100k base salary with meaningful share options.

             Office attendance: 2–3 days a week.
             """
             |> String.trim()
  end

  defp extract(html) do
    {:ok, fragment} = Floki.parse_fragment(html)
    HTMLText.extract(fragment)
  end
end
