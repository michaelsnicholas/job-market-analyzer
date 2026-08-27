defmodule JobMarketAnalyzer.JobMarket.WorkArrangement.Evaluation do
  @moduledoc """
  Deterministically evaluates an extracted Work Arrangement fact against accepted modes.

  Evaluation is derived on demand and is not persisted.
  """

  alias JobMarketAnalyzer.JobMarket.WorkArrangement.Result

  @enforce_keys [:status, :fact, :accepted_arrangements]
  defstruct [:status, :fact, :accepted_arrangements]

  @type status :: :pass | :fail | :unknown | :not_applicable

  @type t :: %__MODULE__{
          status: status(),
          fact: Result.t(),
          accepted_arrangements: [Result.arrangement()]
        }

  @canonical_order [:fully_remote, :hybrid, :on_site]

  @doc "Evaluates a deterministic fact against the currently active accepted modes."
  @spec evaluate(Result.t(), [Result.arrangement()]) :: t()
  def evaluate(%Result{} = fact, accepted_arrangements) do
    accepted_arrangements = canonicalize(accepted_arrangements)

    status =
      case {accepted_arrangements, fact} do
        {[], _fact} ->
          :not_applicable

        {_, %Result{status: :unknown}} ->
          :unknown

        {_, %Result{status: :known, arrangements: arrangements}} ->
          if Enum.any?(arrangements, &(&1 in accepted_arrangements)), do: :pass, else: :fail
      end

    result(status, fact, accepted_arrangements)
  end

  defp result(status, fact, accepted_arrangements) do
    %__MODULE__{
      status: status,
      fact: fact,
      accepted_arrangements: canonicalize(accepted_arrangements)
    }
  end

  defp canonicalize(arrangements) do
    Enum.filter(@canonical_order, &(&1 in arrangements))
  end
end
