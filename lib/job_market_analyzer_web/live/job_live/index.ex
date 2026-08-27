defmodule JobMarketAnalyzerWeb.JobLive.Index do
  use JobMarketAnalyzerWeb, :live_view

  alias JobMarketAnalyzer.JobMarket
  alias JobMarketAnalyzer.JobMarket.Job
  alias JobMarketAnalyzer.JobMarket.SourceAcquisition.{Draft, Suggestion}

  @impl true
  def mount(_params, _session, socket) do
    preference = JobMarket.get_work_arrangement_preference()

    {:ok,
     socket
     |> assign(:page_title, "Saved jobs")
     |> assign_work_arrangement_preference_form(
       JobMarket.change_work_arrangement_preference(preference)
     )
     |> reset_intake()
     |> stream(:jobs, JobMarket.list_jobs_for_work_arrangement(preference))}
  end

  @impl true
  def handle_event(
        "update_work_arrangement_preference",
        %{"work_arrangement_preference" => preference_params},
        socket
      ) do
    case JobMarket.save_work_arrangement_preference(preference_params) do
      {:ok, preference} ->
        {:noreply,
         socket
         |> assign_work_arrangement_preference_form(
           JobMarket.change_work_arrangement_preference(preference)
         )
         |> stream(:jobs, JobMarket.list_jobs_for_work_arrangement(preference), reset: true)}

      {:error, _changeset} ->
        preference = socket.assigns.work_arrangement_preference

        {:noreply,
         socket
         |> put_flash(:error, "Work Arrangement preference could not be saved.")
         |> assign_work_arrangement_preference_form(
           JobMarket.change_work_arrangement_preference(preference)
         )}
    end
  end

  @impl true
  def handle_event("enter_manual", _params, %{assigns: %{intake_state: :idle}} = socket) do
    {:noreply,
     socket
     |> assign(:intake_state, :manual)
     |> assign_job_form(JobMarket.change_job(%Job{}))}
  end

  def handle_event("enter_manual", _params, socket), do: {:noreply, socket}

  def handle_event(
        "fetch_source",
        %{"source" => %{"url" => url}},
        %{assigns: %{intake_state: :idle}} = socket
      ) do
    url = String.trim(url)
    task = {:prepare_source_draft, System.unique_integer([:positive])}

    {:noreply,
     socket
     |> assign(:intake_state, :loading)
     |> assign(:acquisition_url, url)
     |> assign(:acquisition_error, nil)
     |> assign(:acquisition_task, task)
     |> assign_source_form(url)
     |> start_async(task, fn -> JobMarket.prepare_source_draft(url) end)}
  end

  def handle_event("fetch_source", _params, socket), do: {:noreply, socket}

  def handle_event("validate", %{"job" => job_params}, socket)
      when socket.assigns.intake_state in [:manual, :review] do
    changeset =
      %Job{}
      |> JobMarket.change_job(job_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_job_form(socket, changeset)}
  end

  def handle_event("save", %{"job" => job_params}, %{assigns: %{intake_state: :manual}} = socket) do
    save_job(socket, JobMarket.create_manual_job(job_params))
  end

  def handle_event(
        "save",
        %{"job" => job_params},
        %{assigns: %{intake_state: :review, source_draft: %Draft{} = draft}} = socket
      ) do
    save_job(socket, JobMarket.create_acquired_job(job_params, draft))
  end

  def handle_event("reset_intake", _params, socket) do
    {:noreply, reset_intake(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    job = JobMarket.get_job!(id)
    {:ok, _job} = JobMarket.delete_job(job)

    {:noreply,
     socket
     |> put_flash(:info, "Job deleted.")
     |> stream_delete(:jobs, job)}
  end

  defp save_job(socket, result) do
    case result do
      {:ok, _job} ->
        preference = socket.assigns.work_arrangement_preference

        {:noreply,
         socket
         |> put_flash(:info, "Job saved.")
         |> reset_intake()
         |> stream(:jobs, JobMarket.list_jobs_for_work_arrangement(preference), reset: true)}

      {:error, changeset} ->
        {:noreply, assign_job_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  @impl true
  def handle_async(
        {:prepare_source_draft, _request_id} = task,
        {:ok, {:ok, %Draft{} = draft}},
        socket
      ) do
    if current_acquisition?(socket, task) do
      {:noreply,
       socket
       |> assign(:intake_state, :review)
       |> assign(:source_draft, draft)
       |> assign(:acquisition_task, nil)
       |> assign(:acquisition_error, nil)
       |> assign_job_form(review_changeset(draft))}
    else
      {:noreply, socket}
    end
  end

  def handle_async(
        {:prepare_source_draft, _request_id} = task,
        {:ok, {:error, _error}},
        socket
      ) do
    {:noreply, maybe_fail_acquisition(socket, task)}
  end

  def handle_async({:prepare_source_draft, _request_id} = task, {:exit, _reason}, socket) do
    {:noreply, maybe_fail_acquisition(socket, task)}
  end

  defp assign_job_form(socket, changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp assign_work_arrangement_preference_form(socket, changeset) do
    socket
    |> assign(:work_arrangement_preference, changeset.data)
    |> assign(:work_arrangement_preference_form, to_form(changeset))
  end

  defp work_arrangement_enabled?(form) do
    Phoenix.HTML.Form.normalize_value("checkbox", form[:enabled].value)
  end

  defp work_arrangement_modes_selected?(form) do
    Enum.any?(
      [:accept_fully_remote, :accept_hybrid, :accept_on_site],
      &Phoenix.HTML.Form.normalize_value("checkbox", form[&1].value)
    )
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true

  defp work_arrangement_switch(assigns) do
    assigns =
      assign(
        assigns,
        :checked,
        Phoenix.HTML.Form.normalize_value("checkbox", assigns.field.value)
      )

    ~H"""
    <label for={@field.id} class="inline-flex cursor-pointer items-center gap-2">
      <span class="text-sm font-medium">{@label}</span>
      <span class="inline-flex">
        <input type="hidden" name={@field.name} value="false" />
        <input
          type="checkbox"
          role="switch"
          id={@field.id}
          name={@field.name}
          value="true"
          checked={@checked}
          class="toggle toggle-primary toggle-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        />
      </span>
    </label>
    """
  end

  defp assign_source_form(socket, url) do
    assign(socket, :source_form, to_form(%{"url" => url}, as: :source))
  end

  defp reset_intake(socket) do
    socket
    |> cancel_active_acquisition()
    |> assign(:intake_state, :idle)
    |> assign(:source_draft, nil)
    |> assign(:acquisition_url, "")
    |> assign(:acquisition_error, nil)
    |> assign(:acquisition_task, nil)
    |> assign_source_form("")
    |> assign_job_form(JobMarket.change_job(%Job{}))
  end

  defp cancel_active_acquisition(%{assigns: %{acquisition_task: task}} = socket)
       when not is_nil(task) do
    cancel_async(socket, task)
  end

  defp cancel_active_acquisition(socket), do: socket

  defp current_acquisition?(socket, task) do
    socket.assigns.intake_state == :loading and socket.assigns.acquisition_task == task
  end

  defp maybe_fail_acquisition(socket, task) do
    if current_acquisition?(socket, task) do
      socket
      |> assign(:intake_state, :manual)
      |> assign(:source_draft, nil)
      |> assign(:acquisition_task, nil)
      |> assign(:acquisition_error, "Automatic reading failed. Please enter manually.")
      |> assign_job_form(
        JobMarket.change_job(%Job{}, %{source_url: socket.assigns.acquisition_url})
      )
    else
      socket
    end
  end

  defp review_changeset(draft) do
    JobMarket.change_job(%Job{}, %{
      company: suggestion_value(draft.company),
      role: suggestion_value(draft.role),
      source_url: draft.source_url,
      raw_description: draft.raw_description
    })
  end

  defp suggestion_value(%Suggestion{value: value}), do: value
  defp suggestion_value(nil), do: nil

  defp warning_messages(warnings) do
    warnings
    |> Enum.map(&warning_message/1)
    |> Enum.uniq()
  end

  defp warning_message(:generic_extraction),
    do:
      "Please review the description before saving. Some unrelated page content may have been included."

  defp warning_message(:possible_boilerplate),
    do:
      "The page did not expose a clear job-description section, so extra page content may remain."

  defp warning_message(:short_source),
    do:
      "The extracted description is unusually short. Check that the complete posting is present."

  defp warning_message(:metadata_conflict),
    do: "Company and role could not be suggested reliably. Please enter or confirm them."

  defp warning_message(:multiple_job_postings),
    do: "The page described multiple jobs. Confirm that this is the posting you intended."

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
              Fetch a public posting for review, or enter the source manually.
            </p>
          </div>

          <div :if={@intake_state == :idle} id="url-acquisition" class="space-y-4">
            <.form
              for={@source_form}
              id="source-acquisition-form"
              phx-submit="fetch_source"
              class="space-y-4"
            >
              <.input
                field={@source_form[:url]}
                type="url"
                label="Source URL"
                placeholder="https://…"
                required
              />
              <div class="flex flex-wrap justify-end gap-2">
                <button
                  id="enter-manually"
                  type="button"
                  phx-click="enter_manual"
                  class="btn btn-ghost"
                >
                  Enter manually
                </button>
                <button
                  id="fetch-source"
                  type="submit"
                  phx-disable-with="Fetching…"
                  class="btn btn-primary"
                >
                  Fetch posting
                </button>
              </div>
            </.form>
          </div>

          <div
            :if={@intake_state == :loading}
            id="source-acquisition-loading"
            class="flex items-center gap-3 rounded-box bg-base-200 p-4"
          >
            <span class="loading loading-spinner loading-sm" aria-hidden="true"></span>
            <div>
              <p class="font-medium">Reading the posting…</p>
              <p class="mt-1 break-all text-sm text-base-content/60">{@acquisition_url}</p>
            </div>
          </div>

          <div :if={@intake_state in [:manual, :review]} class="space-y-5">
            <div
              :if={@acquisition_error}
              id="source-acquisition-error"
              role="alert"
              class="alert alert-error"
            >
              <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
              <span>{@acquisition_error}</span>
            </div>

            <div :if={@intake_state == :review} id="source-review" class="space-y-4">
              <div>
                <p class="font-medium">Review the fetched posting before saving</p>
                <p class="mt-1 text-sm leading-6 text-base-content/65">
                  Company, role, and description are suggestions. Correct anything that is incomplete.
                </p>
              </div>

              <div
                :if={@source_draft.final_source_url != @source_draft.source_url}
                id="source-redirect-notice"
                class="rounded-box bg-base-200 p-4 text-sm"
              >
                <p class="font-medium">The posting redirected to:</p>
                <p class="mt-1 break-all text-base-content/65">{@source_draft.final_source_url}</p>
              </div>

              <div
                :if={warning_messages(@source_draft.warnings) != []}
                id="source-warnings"
                class="alert alert-warning items-start"
              >
                <.icon name="hero-exclamation-triangle" class="mt-0.5 size-5 shrink-0" />
                <div class="space-y-1 text-sm">
                  <p :for={message <- warning_messages(@source_draft.warnings)}>{message}</p>
                </div>
              </div>
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
                label={
                  if @intake_state == :review,
                    do: "Source URL",
                    else: "Source URL — optional reference"
                }
                placeholder="https://… (optional)"
                readonly={@intake_state == :review}
              />
              <.input
                field={@form[:raw_description]}
                type="textarea"
                label="Raw job description"
                rows="14"
                required
                placeholder="Paste the complete job description"
              />
              <div class="flex flex-wrap justify-end gap-2">
                <button
                  id="reset-intake"
                  type="button"
                  phx-click="reset_intake"
                  class="btn btn-ghost"
                >
                  {if @intake_state == :review, do: "Start over", else: "Cancel"}
                </button>
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
          </div>
        </section>

        <section id="saved-jobs" aria-labelledby="saved-jobs-heading" class="space-y-4">
          <div>
            <p class="text-sm font-medium text-primary">Local corpus</p>
            <h2 id="saved-jobs-heading" class="mt-1 text-2xl font-semibold tracking-tight">
              Saved jobs
            </h2>
          </div>

          <div
            id="work-arrangement-filter"
            class="rounded-box border border-base-300 bg-base-100 px-5 py-4 shadow-sm"
          >
            <.form
              for={@work_arrangement_preference_form}
              id="work-arrangement-preference-form"
              phx-change="update_work_arrangement_preference"
            >
              <.work_arrangement_switch
                field={@work_arrangement_preference_form[:enabled]}
                label="Work Arrangement"
              />

              <div
                id="work-arrangement-mode-options"
                hidden={!work_arrangement_enabled?(@work_arrangement_preference_form)}
                class="ml-6 border-l border-base-300 pl-4"
              >
                <p
                  :if={!work_arrangement_modes_selected?(@work_arrangement_preference_form)}
                  id="work-arrangement-instruction"
                  class="mb-3 text-sm text-base-content/65"
                >
                  Please select your preferred Work Arrangement(s).
                </p>
                <div class="flex flex-col items-start gap-3">
                  <.work_arrangement_switch
                    field={@work_arrangement_preference_form[:accept_fully_remote]}
                    label="Fully remote"
                  />
                  <.work_arrangement_switch
                    field={@work_arrangement_preference_form[:accept_hybrid]}
                    label="Hybrid"
                  />
                  <.work_arrangement_switch
                    field={@work_arrangement_preference_form[:accept_on_site]}
                    label="On-site"
                  />
                </div>
              </div>
            </.form>
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
