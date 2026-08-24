defmodule JobMarketAnalyzerWeb.JobLive.Index do
  use JobMarketAnalyzerWeb, :live_view

  alias JobMarketAnalyzer.JobMarket
  alias JobMarketAnalyzer.JobMarket.Job

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Saved jobs")
     |> assign_job_form(JobMarket.change_job(%Job{}))
     |> stream(:jobs, JobMarket.list_jobs())}
  end

  @impl true
  def handle_event("validate", %{"job" => job_params}, socket) do
    changeset =
      %Job{}
      |> JobMarket.change_job(job_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_job_form(socket, changeset)}
  end

  def handle_event("save", %{"job" => job_params}, socket) do
    case JobMarket.create_job(job_params) do
      {:ok, job} ->
        {:noreply,
         socket
         |> put_flash(:info, "Job saved.")
         |> assign_job_form(JobMarket.change_job(%Job{}))
         |> stream_insert(:jobs, job, at: 0)}

      {:error, changeset} ->
        {:noreply, assign_job_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    job = JobMarket.get_job!(id)
    {:ok, _job} = JobMarket.delete_job(job)

    {:noreply,
     socket
     |> put_flash(:info, "Job deleted.")
     |> stream_delete(:jobs, job)}
  end

  defp assign_job_form(socket, changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp display_value(value, fallback) when value in [nil, ""], do: fallback
  defp display_value(value, _fallback), do: value

  defp description_preview(description) do
    description
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 180)
  end

  defp captured_at(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %H:%M UTC")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-10">
        <section id="job-intake" class="rounded-box border border-base-300 bg-base-100 p-6 shadow-sm">
          <div class="mb-6">
            <p class="text-sm font-medium text-primary">Add source evidence</p>
            <h1 class="mt-1 text-2xl font-semibold tracking-tight">Capture a job description</h1>
            <p class="mt-2 max-w-3xl text-sm leading-6 text-base-content/70">
              Save the original posting now. Analysis will remain separate and comes later.
            </p>
          </div>

          <.form
            for={@form}
            id="job-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-4"
          >
            <div class="grid gap-4 md:grid-cols-2">
              <.input field={@form[:company]} label="Company" placeholder="Optional" />
              <.input field={@form[:role]} label="Role" placeholder="Optional" />
            </div>
            <.input
              field={@form[:source_url]}
              type="url"
              label="Source URL"
              placeholder="https://… (optional)"
            />
            <.input
              field={@form[:raw_description]}
              type="textarea"
              label="Raw job description"
              rows="14"
              required
              placeholder="Paste the complete job description"
            />
            <div class="flex justify-end">
              <button
                id="save-job"
                type="submit"
                phx-disable-with="Saving…"
                class="btn btn-primary"
              >
                Save job
              </button>
            </div>
          </.form>
        </section>

        <section id="saved-jobs" aria-labelledby="saved-jobs-heading" class="space-y-4">
          <div>
            <p class="text-sm font-medium text-primary">Local corpus</p>
            <h2 id="saved-jobs-heading" class="mt-1 text-2xl font-semibold tracking-tight">
              Saved jobs
            </h2>
          </div>

          <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100 shadow-sm">
            <table class="table">
              <thead>
                <tr>
                  <th>Company / role</th>
                  <th>Description preview</th>
                  <th>Captured</th>
                  <th>Source</th>
                  <th class="text-right"><span class="sr-only">Actions</span></th>
                </tr>
              </thead>
              <tbody id="jobs" phx-update="stream">
                <tr id="jobs-empty" class="hidden only:table-row">
                  <td colspan="5" class="py-10 text-center text-base-content/60">
                    No jobs saved yet.
                  </td>
                </tr>
                <tr :for={{dom_id, job} <- @streams.jobs} id={dom_id}>
                  <td class="min-w-44 align-top">
                    <p class="font-medium">{display_value(job.company, "Company not provided")}</p>
                    <p class="mt-1 text-sm text-base-content/60">
                      {display_value(job.role, "Role not provided")}
                    </p>
                  </td>
                  <td class="min-w-72 max-w-md align-top text-sm leading-6 text-base-content/75">
                    {description_preview(job.raw_description)}
                  </td>
                  <td class="min-w-48 align-top text-sm text-base-content/70">
                    {captured_at(job.inserted_at)}
                  </td>
                  <td class="max-w-56 align-top text-sm">
                    <.link
                      :if={job.source_url not in [nil, ""]}
                      href={job.source_url}
                      target="_blank"
                      rel="noreferrer"
                      class="link link-primary whitespace-nowrap"
                    >
                      Open source
                    </.link>
                    <span :if={job.source_url in [nil, ""]} class="text-base-content/45">
                      Not provided
                    </span>
                  </td>
                  <td class="align-top">
                    <div class="flex justify-end gap-2">
                      <.link
                        id={"view-job-#{job.id}"}
                        navigate={~p"/jobs/#{job}"}
                        class="btn btn-sm btn-ghost"
                      >
                        View
                      </.link>
                      <button
                        id={"delete-job-#{job.id}"}
                        type="button"
                        phx-click="delete"
                        phx-value-id={job.id}
                        data-confirm="Delete this saved job? This cannot be undone."
                        class="btn btn-sm btn-ghost text-error"
                      >
                        Delete
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
