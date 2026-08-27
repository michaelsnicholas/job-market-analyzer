defmodule JobMarketAnalyzer.JobMarket.WorkArrangement.EvaluationTest do
  use ExUnit.Case, async: true

  alias JobMarketAnalyzer.JobMarket.WorkArrangement
  alias JobMarketAnalyzer.JobMarket.WorkArrangement.Evaluation

  test "no active accepted modes is not applicable regardless of the fact" do
    fact = WorkArrangement.extract("This role is fully remote.")

    assert %{status: :not_applicable, fact: ^fact} =
             Evaluation.evaluate(fact, [])
  end

  test "an explicit fact passes when any offered mode is accepted" do
    fact = WorkArrangement.extract("Hybrid preferred, remote considered")

    assert %{status: :pass, accepted_arrangements: [:fully_remote, :on_site]} =
             Evaluation.evaluate(fact, [:on_site, :fully_remote])
  end

  test "an explicit fact fails when no offered mode is accepted" do
    fact = WorkArrangement.extract("This role is fully remote.")

    assert %{status: :fail} = Evaluation.evaluate(fact, [:hybrid, :on_site])
  end

  test "insufficient or ambiguous deterministic evidence remains unknown" do
    for source <- [
          "Location: Central City.",
          "This role is based in our office three days a week."
        ] do
      fact = WorkArrangement.extract(source)

      assert fact.status == :unknown
      assert %{status: :unknown, fact: ^fact} = Evaluation.evaluate(fact, [:hybrid])
    end
  end
end
