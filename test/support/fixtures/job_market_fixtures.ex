defmodule JobMarketAnalyzer.JobMarketFixtures do
  @moduledoc """
  Test helpers for creating job-market source records.
  """

  alias JobMarketAnalyzer.JobMarket

  def job_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          company: "Example Company",
          role: "Embedded Software Engineer",
          source_url: "https://example.com/jobs/embedded-engineer",
          raw_description: "Build reliable embedded systems."
        },
        attrs
      )

    {:ok, job} = JobMarket.create_job(attrs)
    job
  end
end
