defmodule JobMarketAnalyzerWeb.JobLive.Show do
  use JobMarketAnalyzerWeb, :live_view

  alias JobMarketAnalyzer.JobMarket

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    job = JobMarket.get_job!(id)

    {:ok,
     socket
     |> assign(:page_title, job.role || "Saved job")
     |> assign(:job, job)
     |> assign(:work_arrangement, JobMarket.extract_work_arrangement(job))}
  end

  defp arrangement_label(:fully_remote), do: "Fully remote"
  defp arrangement_label(:hybrid), do: "Hybrid"
  defp arrangement_label(:on_site), do: "On-site"

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
