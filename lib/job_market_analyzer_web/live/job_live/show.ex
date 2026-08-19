defmodule JobMarketAnalyzerWeb.JobLive.Show do
  use JobMarketAnalyzerWeb, :live_view

  alias JobMarketAnalyzer.JobMarket

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    job = JobMarket.get_job!(id)

    {:ok,
     socket
     |> assign(:page_title, job.role || "Saved job")
     |> assign(:job, job)}
  end

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
