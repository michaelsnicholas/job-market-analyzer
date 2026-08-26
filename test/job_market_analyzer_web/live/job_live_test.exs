defmodule JobMarketAnalyzerWeb.JobLiveTest do
  use JobMarketAnalyzerWeb.ConnCase

  import JobMarketAnalyzer.JobMarketFixtures
  import Phoenix.LiveViewTest

  alias JobMarketAnalyzer.JobMarket
  alias JobMarketAnalyzer.JobMarket.SourceAcquisition.{Draft, Suggestion}
  alias JobMarketAnalyzerWeb.JobLive.Index

  describe "index" do
    test "renders URL-first intake and the empty saved-jobs corpus", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#job-intake")
      assert has_element?(view, "#source-acquisition-form")
      assert has_element?(view, "#enter-manually", "Enter manually")
      refute has_element?(view, "#job-form")
      assert has_element?(view, "#saved-jobs")
      assert has_element?(view, "#jobs-empty", "No jobs saved yet.")
      assert has_element?(view, "#client-error:not([phx-hook])")
    end

    test "manual entry validates, cancels, and preserves manual provenance", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#enter-manually") |> render_click()

      assert has_element?(view, "#job-form")
      assert has_element?(view, "#saved-jobs")

      view
      |> form("#job-form", job: %{raw_description: "  \n  "})
      |> render_change()

      assert has_element?(view, "#job-form p.text-error", "can't be blank")

      view |> element("#reset-intake") |> render_click()
      assert has_element?(view, "#source-acquisition-form")
      refute has_element?(view, "#job-form")
    end

    test "saves and lists a manually entered job", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#enter-manually") |> render_click()

      view
      |> form("#job-form",
        job: %{
          company: "Acme",
          role: "Systems Engineer",
          source_url: "https://example.com/jobs/systems",
          raw_description: "Design dependable systems.\nWork across teams."
        }
      )
      |> render_submit()

      [job] = JobMarket.list_jobs()
      assert job.source_acquisition_method == :manual
      assert is_nil(job.final_source_url)
      assert is_nil(job.source_acquired_at)
      assert is_nil(job.source_extractor_version)
      assert job.source_text_modified == false
      assert has_element?(view, "#jobs-#{job.id}", "Acme")
      assert has_element?(view, "#jobs-#{job.id}", "Systems Engineer")
      assert has_element?(view, "#jobs-#{job.id}", "Design dependable systems.")
      assert has_element?(view, "#jobs-#{job.id} a[href='https://example.com/jobs/systems']")
      assert has_element?(view, "#jobs-#{job.id} a.whitespace-nowrap", "Open source")
      assert has_element?(view, "#view-job-#{job.id}[href='/jobs/#{job.id}']")

      assert has_element?(
               view,
               "#flash-info[phx-hook='AutoDismissFlash'][data-auto-dismiss-ms='4000']"
             )

      assert has_element?(view, "#flash-info button[aria-label='close']")
      assert has_element?(view, "#source-acquisition-form")
      refute has_element?(view, "#job-form")
    end

    test "shows loading without hiding saved jobs" do
      job = job_fixture()
      socket = mounted_socket()

      {:noreply, socket} =
        Index.handle_event(
          "fetch_source",
          %{"source" => %{"url" => "ftp://example.test/job"}},
          socket
        )

      html = render_socket(socket)
      assert html =~ ~s(id="source-acquisition-loading")
      assert html =~ ~s(id="saved-jobs")
      assert html =~ ~s(id="jobs-#{job.id}")
      refute html =~ ~s(id="source-acquisition-form")
      refute html =~ ~s(id="job-form")
    end

    test "failed acquisition opens manual entry without creating a job", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> form("#source-acquisition-form", source: %{url: "http://127.0.0.1/jobs/example"})
      |> render_submit()

      render_async(view)

      assert has_element?(
               view,
               "#source-acquisition-error",
               "Automatic reading failed. Please enter manually."
             )

      assert has_element?(
               view,
               "#job-form input[name='job[source_url]'][value='http://127.0.0.1/jobs/example']"
             )

      assert has_element?(view, "#saved-jobs")
      assert JobMarket.list_jobs() == []
    end

    test "successful acquisition review is populated, editable, and keeps provenance trusted" do
      draft = source_draft()
      socket = review_socket(draft)
      html = render_socket(socket)

      assert html =~ ~s(id="source-review")
      assert html =~ ~s(value="Suggested Company")
      assert html =~ ~s(value="Suggested Engineer")
      assert html =~ "Original extracted description."
      assert html =~ ~s(name="job[source_url]")
      assert html =~ "readonly"
      assert html =~ "Please review the description before saving."
      assert html =~ ~s(id="saved-jobs")
      refute html =~ "source_acquisition_method"
      refute html =~ "source_extractor_version"

      forged_attrs = %{
        "company" => "Corrected Company",
        "role" => "Corrected Role",
        "source_url" => "https://attacker.invalid/forged",
        "raw_description" => "Original extracted description.",
        "source_acquisition_method" => "manual",
        "final_source_url" => "https://attacker.invalid/final",
        "source_extractor_version" => "999",
        "source_text_modified" => "true"
      }

      {:noreply, socket} = Index.handle_event("save", %{"job" => forged_attrs}, socket)
      [job] = JobMarket.list_jobs()

      assert job.company == "Corrected Company"
      assert job.role == "Corrected Role"
      assert job.raw_description == "Original extracted description."
      assert job.source_url == draft.source_url
      assert job.final_source_url == draft.final_source_url
      assert DateTime.compare(job.source_acquired_at, draft.source_acquired_at) == :eq
      assert job.source_acquisition_method == :generic_html
      assert job.source_extractor_version == draft.source_extractor_version
      assert job.source_text_modified == false
      assert socket.assigns.intake_state == :idle
      assert socket.assigns.source_draft == nil
      assert render_socket(socket) =~ ~s(id="source-acquisition-form")

      {:noreply, socket} =
        Index.handle_async({:prepare_source_draft, 1}, {:ok, {:ok, draft}}, socket)

      assert socket.assigns.intake_state == :idle
      assert socket.assigns.source_draft == nil
    end

    test "acquired save records an edited approved source exactly" do
      draft = source_draft()
      socket = review_socket(draft)
      approved = "Edited source\n\nwith exact spacing."

      {:noreply, _socket} =
        Index.handle_event(
          "save",
          %{
            "job" => %{
              "company" => "Suggested Company",
              "role" => "Suggested Engineer",
              "source_url" => draft.source_url,
              "raw_description" => approved
            }
          },
          socket
        )

      [job] = JobMarket.list_jobs()
      assert job.raw_description == approved
      assert job.source_text_modified == true
    end

    test "validation failure preserves acquired review and trusted draft" do
      draft = source_draft()
      socket = review_socket(draft)

      {:noreply, socket} =
        Index.handle_event(
          "save",
          %{"job" => %{"source_url" => draft.source_url, "raw_description" => " \n "}},
          socket
        )

      assert socket.assigns.intake_state == :review
      assert socket.assigns.source_draft == draft
      assert render_socket(socket) =~ "can&#39;t be blank"
      assert JobMarket.list_jobs() == []
    end

    test "start over clears a trusted draft and stale async results are ignored" do
      draft = source_draft()
      socket = review_socket(draft)

      {:noreply, reset_socket} = Index.handle_event("reset_intake", %{}, socket)
      assert reset_socket.assigns.intake_state == :idle
      assert reset_socket.assigns.source_draft == nil

      stale_task = {:prepare_source_draft, 123}

      {:noreply, stale_socket} =
        Index.handle_async(stale_task, {:ok, {:ok, draft}}, reset_socket)

      assert stale_socket.assigns.intake_state == :idle
      assert stale_socket.assigns.source_draft == nil
      assert render_socket(stale_socket) =~ ~s(id="source-acquisition-form")
    end

    test "shows quiet fallbacks for omitted optional fields", %{conn: conn} do
      job = job_fixture(%{company: nil, role: nil, source_url: nil})
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#jobs-#{job.id}", "Company not provided")
      assert has_element?(view, "#jobs-#{job.id}", "Role not provided")
      assert has_element?(view, "#jobs-#{job.id}", "Not provided")
    end

    test "hard deletes a job and declares confirmation", %{conn: conn} do
      job = job_fixture()
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(
               view,
               "#delete-job-#{job.id}[data-confirm='Delete this saved job? This cannot be undone.']"
             )

      view
      |> element("#delete-job-#{job.id}")
      |> render_click()

      refute has_element?(view, "#jobs-#{job.id}")
      assert_raise Ecto.NoResultsError, fn -> JobMarket.get_job!(job.id) end
    end
  end

  defp mounted_socket do
    socket = %Phoenix.LiveView.Socket{
      endpoint: JobMarketAnalyzerWeb.Endpoint,
      router: JobMarketAnalyzerWeb.Router,
      view: Index,
      assigns: %{__changed__: %{}, flash: %{}},
      private: %{
        live_temp: %{},
        lifecycle: %Phoenix.LiveView.Lifecycle{}
      }
    }

    {:ok, socket} = Index.mount(%{}, %{}, socket)
    socket
  end

  defp review_socket(draft) do
    socket = mounted_socket()
    task = {:prepare_source_draft, 1}

    socket =
      Phoenix.Component.assign(socket,
        intake_state: :loading,
        acquisition_task: task,
        acquisition_url: draft.source_url
      )

    {:noreply, socket} = Index.handle_async(task, {:ok, {:ok, draft}}, socket)
    socket
  end

  defp render_socket(socket) do
    socket.assigns
    |> Index.render()
    |> rendered_to_string()
  end

  defp source_draft do
    %Draft{
      company: %Suggestion{value: "Suggested Company", source: :page_metadata},
      role: %Suggestion{value: "Suggested Engineer", source: :page_metadata},
      raw_description: "Original extracted description.",
      original_extracted_text: "Original extracted description.",
      source_url: "https://jobs.example.test/posting/123",
      final_source_url: "https://careers.example.test/posting/123",
      source_acquired_at: ~U[2026-08-26 15:30:00Z],
      source_acquisition_method: :generic_html,
      source_extractor_version: 2,
      warnings: [:generic_extraction]
    }
  end

  describe "show" do
    test "displays the complete original source and supplied metadata", %{conn: conn} do
      raw_description = "First line\n\n  Indented line\nFinal line"
      job = job_fixture(%{raw_description: raw_description})

      {:ok, view, _html} = live(conn, ~p"/jobs/#{job}")

      assert has_element?(view, "#job-detail", job.company)
      assert has_element?(view, "#job-detail", job.role)
      assert has_element?(view, "#job-source-url[href='#{job.source_url}']")

      rendered_source =
        view
        |> element("#raw-description")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.text()

      assert rendered_source == raw_description
    end

    test "omits optional metadata when it was not supplied", %{conn: conn} do
      job = job_fixture(%{company: nil, role: nil, source_url: nil})

      {:ok, view, _html} = live(conn, ~p"/jobs/#{job}")

      assert has_element?(view, "#job-detail", "Role not provided")
      refute has_element?(view, "#job-source-url")
    end

    test "displays a known Work Arrangement with evidence and diagnostics", %{conn: conn} do
      source = "Overview ☕\nHybrid preferred, remote considered\nDetails"
      job = job_fixture(%{raw_description: source})

      {:ok, view, _html} = live(conn, ~p"/jobs/#{job}")

      assert has_element?(view, "#work-arrangement", "Deterministic extraction · v1")
      assert has_element?(view, "#work-arrangement-modes", "Fully remote")
      assert has_element?(view, "#work-arrangement-modes", "Hybrid")

      assert has_element?(
               view,
               "#work-arrangement-evidence-0",
               "Hybrid preferred, remote considered"
             )

      assert has_element?(view, "#work-arrangement-evidence-0", "explicit_hybrid_or_remote")
      assert has_element?(view, "#work-arrangement-evidence-0", "bytes 13–48")

      rendered_source =
        view
        |> element("#raw-description")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.text()

      assert rendered_source == source
    end

    test "displays an unknown Work Arrangement", %{conn: conn} do
      job = job_fixture(%{raw_description: "Location: Central City."})

      {:ok, view, _html} = live(conn, ~p"/jobs/#{job}")

      assert has_element?(view, "#work-arrangement-status", "Unknown")
      assert has_element?(view, "#work-arrangement", "No sufficiently explicit")
      refute has_element?(view, "#work-arrangement-evidence")
    end
  end
end
