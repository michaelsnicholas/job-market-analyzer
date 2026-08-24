defmodule JobMarketAnalyzer.JobMarket do
  @moduledoc """
  The domain boundary for the local job-market corpus.
  """

  import Ecto.Query, warn: false

  alias JobMarketAnalyzer.JobMarket.{
    Job,
    SourceAcquisition.Extractor,
    SourceAcquisition.GuardedFetcher,
    WorkArrangement
  }

  alias JobMarketAnalyzer.Repo

  @doc """
  Lists saved jobs from newest to oldest.
  """
  def list_jobs do
    Job
    |> order_by([job], desc: job.inserted_at, desc: job.id)
    |> Repo.all()
  end

  @doc """
  Gets a single job.

  Raises `Ecto.NoResultsError` if the job does not exist.
  """
  def get_job!(id), do: Repo.get!(Job, id)

  @doc """
  Recomputes the deterministic Work Arrangement fact for a saved job.
  """
  def extract_work_arrangement(%Job{raw_description: raw_description}) do
    WorkArrangement.extract(raw_description)
  end

  @doc """
  Fetches a public URL through the guarded source-acquisition boundary.

  The bounded response is transient and does not create or update a job.
  """
  def fetch_public_source(url), do: GuardedFetcher.fetch(url)

  @doc """
  Fetches a public source and constructs a transient reviewable draft.

  Nothing is persisted and no job is created.
  """
  def prepare_source_draft(url), do: prepare_source_draft(url, [])

  @doc false
  def prepare_source_draft(url, fetch_opts) do
    with {:ok, fetch_result} <- GuardedFetcher.fetch(url, fetch_opts) do
      Extractor.extract(fetch_result)
    end
  end

  @doc """
  Creates a job from source data supplied by the user.
  """
  def create_job(attrs \\ %{}) do
    %Job{}
    |> Job.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes a job.
  """
  def delete_job(%Job{} = job), do: Repo.delete(job)

  @doc """
  Returns a changeset for creating or validating a job.
  """
  def change_job(%Job{} = job, attrs \\ %{}) do
    Job.changeset(job, attrs)
  end
end
