defmodule JobMarketAnalyzerWeb.JobLive.Show do
  use JobMarketAnalyzerWeb, :live_view

  alias JobMarketAnalyzer.JobMarket

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    job = JobMarket.get_job!(id)
    evaluation = JobMarket.evaluate_work_arrangement(job)

    {:ok,
     socket
     |> assign(:page_title, job.role || "Saved job")
     |> assign(:job, job)
     |> assign(:work_arrangement_evaluation, evaluation)
     |> assign(:work_arrangement, evaluation.fact)}
  end

  defp arrangement_label(:fully_remote), do: "Fully remote"
  defp arrangement_label(:hybrid), do: "Hybrid"
  defp arrangement_label(:on_site), do: "On-site"

  defp evaluation_label(:pass), do: "Pass"
  defp evaluation_label(:fail), do: "Fail"
  defp evaluation_label(:unknown), do: "Unknown"
  defp evaluation_label(:not_applicable), do: "Not applicable"

  defp evaluation_explanation(:pass),
    do: "The explicit Work Arrangement matches an accepted mode."

  defp evaluation_explanation(:fail),
    do: "The explicit Work Arrangement does not match any accepted mode."

  defp evaluation_explanation(:unknown),
    do: "Deterministic evidence was insufficient. Semantic verification is not yet implemented."

  defp evaluation_explanation(:not_applicable),
    do: "No Work Arrangement modes are currently active."

  defp unknown_explanation(:no_explicit_evidence),
    do: "No sufficiently explicit work arrangement was found."

  defp unknown_explanation(:ambiguous_evidence),
    do: "The source mentions work arrangement, but not explicitly enough to classify it."

  defp unknown_explanation(:contradictory_evidence),
    do: "The source contains conflicting explicit work-arrangement evidence."

  defp captured_at(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %H:%M UTC")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <article id="job-detail" class="space-y-6">
        <.link navigate={~p"/"} class="link inline-flex items-center gap-1 text-sm">
          <.icon name="hero-arrow-left-micro" class="size-4" /> Back to saved jobs
        </.link>

        <header class="rounded-box border border-base-300 bg-base-100 p-6 shadow-sm">
          <p class="text-sm text-base-content/60">Captured {captured_at(@job.inserted_at)}</p>
          <h1 class="mt-2 text-3xl font-semibold tracking-tight">
            {@job.role || "Role not provided"}
          </h1>
          <p :if={@job.company not in [nil, ""]} class="mt-2 text-lg text-base-content/70">
            {@job.company}
          </p>
          <.link
            :if={@job.source_url not in [nil, ""]}
            id="job-source-url"
            href={@job.source_url}
            target="_blank"
            rel="noreferrer"
            class="link link-primary mt-4 inline-block break-all"
          >
            {@job.source_url}
          </.link>
        </header>

        <section
          id="work-arrangement"
          class="rounded-box border border-base-300 bg-base-100 p-6 shadow-sm"
        >
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="text-lg font-semibold">Work arrangement</h2>
            <p class="text-xs text-base-content/55">
              Deterministic extraction · v{@work_arrangement.extractor_version}
            </p>
          </div>

          <div id="work-arrangement-evaluation" class="mt-4 rounded-box bg-base-200 p-4">
            <p class="text-xs font-medium uppercase tracking-wide text-base-content/55">
              Deterministic evaluation
            </p>
            <p id="work-arrangement-evaluation-status" class="mt-1 text-lg font-semibold">
              {evaluation_label(@work_arrangement_evaluation.status)}
            </p>
            <p class="mt-1 text-sm leading-6 text-base-content/65">
              {evaluation_explanation(@work_arrangement_evaluation.status)}
            </p>

            <div
              :if={@work_arrangement_evaluation.status != :not_applicable}
              id="work-arrangement-accepted-modes"
              class="mt-3"
            >
              <p class="text-xs text-base-content/55">Accepted modes</p>
              <div class="mt-1 flex flex-wrap gap-2">
                <span
                  :for={arrangement <- @work_arrangement_evaluation.accepted_arrangements}
                  class="badge badge-outline"
                >
                  {arrangement_label(arrangement)}
                </span>
              </div>
            </div>
          </div>

          <div :if={@work_arrangement.status == :known} class="mt-4 space-y-4">
            <div id="work-arrangement-modes" class="flex flex-wrap gap-2">
              <span
                :for={arrangement <- @work_arrangement.arrangements}
                class="badge badge-primary badge-outline"
              >
                {arrangement_label(arrangement)}
              </span>
            </div>

            <div id="work-arrangement-evidence" class="space-y-3">
              <div
                :for={{evidence, index} <- Enum.with_index(@work_arrangement.evidence)}
                id={"work-arrangement-evidence-#{index}"}
                class="rounded-box bg-base-200 p-4"
              >
                <blockquote class="whitespace-pre-wrap text-sm leading-6">
                  “{evidence.text}”
                </blockquote>
                <p class="mt-2 font-mono text-xs text-base-content/55">
                  {evidence.rule} · bytes {evidence.start_byte}–{evidence.end_byte}
                </p>
              </div>
            </div>
          </div>

          <div :if={@work_arrangement.status == :unknown} class="mt-4">
            <p id="work-arrangement-status" class="font-medium">Unknown</p>
            <p class="mt-1 text-sm leading-6 text-base-content/65">
              {unknown_explanation(@work_arrangement.unknown_reason)}
            </p>
          </div>
        </section>

        <section class="rounded-box border border-base-300 bg-base-100 p-6 shadow-sm">
          <h2 class="text-lg font-semibold">Original job description</h2>
          <div
            id="raw-description"
            phx-no-format
            class="mt-4 whitespace-pre-wrap break-words text-sm leading-7 text-base-content/85"
          >{@job.raw_description}</div>
        </section>
      </article>
    </Layouts.app>
    """
  end
end
