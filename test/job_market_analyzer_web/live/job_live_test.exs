defmodule JobMarketAnalyzerWeb.JobLiveTest do
  use JobMarketAnalyzerWeb.ConnCase

  import JobMarketAnalyzer.JobMarketFixtures
  import Phoenix.LiveViewTest

  alias JobMarketAnalyzer.JobMarket

  describe "index" do
    test "renders the intake form and empty corpus", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#job-intake")
      assert has_element?(view, "#job-form")
      assert has_element?(view, "#jobs-empty", "No jobs saved yet.")
    end

    test "validates a blank raw description", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> form("#job-form", job: %{raw_description: "  \n  "})
      |> render_change()

      assert has_element?(view, "#job-form p.text-error", "can't be blank")
    end

    test "saves and lists a job through the intake form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

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
      assert has_element?(view, "#jobs-#{job.id}", "Acme")
      assert has_element?(view, "#jobs-#{job.id}", "Systems Engineer")
      assert has_element?(view, "#jobs-#{job.id}", "Design dependable systems.")
      assert has_element?(view, "#jobs-#{job.id} a[href='https://example.com/jobs/systems']")
      assert has_element?(view, "#view-job-#{job.id}[href='/jobs/#{job.id}']")
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
