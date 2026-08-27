defmodule JobMarketAnalyzer.JobMarket do
  @moduledoc """
  The domain boundary for the local job-market corpus.
  """

  import Ecto.Query, warn: false

  alias JobMarketAnalyzer.JobMarket.{
    Job,
    SourceAcquisition.Draft,
    SourceAcquisition.Extractor,
    SourceAcquisition.GuardedFetcher,
    WorkArrangement,
    WorkArrangement.Evaluation,
    WorkArrangementPreference
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
  Gets the local Work Arrangement preference or returns its hidden, inactive default.
  """
  def get_work_arrangement_preference do
    Repo.get(WorkArrangementPreference, 1) || WorkArrangementPreference.default()
  end

  @doc """
  Returns a changeset for validating or editing the Work Arrangement preference.
  """
  def change_work_arrangement_preference(
        %WorkArrangementPreference{} = preference,
        attrs \\ %{}
      ) do
    WorkArrangementPreference.changeset(preference, attrs)
  end

  @doc """
  Saves the singleton local Work Arrangement preference.
  """
  def save_work_arrangement_preference(attrs) do
    get_work_arrangement_preference()
    |> WorkArrangementPreference.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  Recomputes and evaluates a saved job's deterministic Work Arrangement fact.
  """
  def evaluate_work_arrangement(%Job{} = job) do
    preference = get_work_arrangement_preference()

    evaluate_work_arrangement(job, preference)
  end

  @doc """
  Lists the current Saved jobs projection, excluding only deterministic Work Arrangement failures.
  """
  def list_jobs_for_work_arrangement(%WorkArrangementPreference{} = preference) do
    Enum.reject(list_jobs(), fn job ->
      evaluate_work_arrangement(job, preference).status == :fail
    end)
  end

  defp evaluate_work_arrangement(job, preference) do
    active_arrangements =
      if preference.enabled do
        WorkArrangementPreference.accepted_arrangements(preference)
      else
        []
      end

    job
    |> extract_work_arrangement()
    |> Evaluation.evaluate(active_arrangements)
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
  def create_job(attrs \\ %{}), do: create_manual_job(attrs)

  @doc """
  Creates a manually supplied job without acquisition provenance.

  A source URL remains optional and does not imply that the application fetched it.
  """
  def create_manual_job(attrs \\ %{}) do
    %Job{}
    |> Job.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a job from user-approved values and a trusted transient acquisition draft.
  """
  def create_acquired_job(attrs, %Draft{} = draft) do
    approved_raw_description = attr_value(attrs, :raw_description)

    provenance = %{
      source_url: draft.source_url,
      final_source_url: draft.final_source_url,
      source_acquired_at: draft.source_acquired_at,
      source_acquisition_method: draft.source_acquisition_method,
      source_extractor_version: draft.source_extractor_version,
      source_text_modified: approved_raw_description != draft.original_extracted_text
    }

    %Job{}
    |> Job.acquired_changeset(attrs, provenance)
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

  defp attr_value(attrs, key) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end
end
