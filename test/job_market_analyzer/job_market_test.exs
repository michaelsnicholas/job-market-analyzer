defmodule JobMarketAnalyzer.JobMarketTest do
  use JobMarketAnalyzer.DataCase

  alias JobMarketAnalyzer.JobMarket
  alias JobMarketAnalyzer.JobMarket.Job
  alias JobMarketAnalyzer.JobMarket.SourceAcquisition.Draft
  alias JobMarketAnalyzer.Repo

  import JobMarketAnalyzer.JobMarketFixtures

  describe "jobs" do
    test "creates and retrieves a valid job while preserving the raw source exactly" do
      raw_description = "  First line\n\n    Indented requirement\nLast line  "

      assert {:ok, %Job{} = job} =
               JobMarket.create_job(%{
                 company: "Acme",
                 role: "Firmware Engineer",
                 source_url: "https://example.com/job/1",
                 raw_description: raw_description
               })

      persisted_job = JobMarket.get_job!(job.id)
      assert persisted_job.raw_description == raw_description
      assert persisted_job.company == "Acme"
      assert persisted_job.role == "Firmware Engineer"
      assert persisted_job.source_url == "https://example.com/job/1"
      assert persisted_job.source_acquisition_method == :manual
      assert persisted_job.final_source_url == nil
      assert persisted_job.source_acquired_at == nil
      assert persisted_job.source_extractor_version == nil
      assert persisted_job.source_text_modified == false
    end

    test "exposes the persisted provenance schema with manual defaults" do
      assert :final_source_url in Job.__schema__(:fields)
      assert Job.__schema__(:type, :final_source_url) == :string
      assert Job.__schema__(:type, :source_acquired_at) == :utc_datetime_usec
      assert Job.__schema__(:type, :source_extractor_version) == :integer
      assert Job.__schema__(:type, :source_text_modified) == :boolean

      assert %Job{}.source_acquisition_method == :manual
      assert %Job{}.source_text_modified == false
    end

    test "database defaults give rows without provenance manual semantics" do
      timestamp = ~N[2026-08-25 12:00:00]

      assert {1, nil} =
               Repo.insert_all("jobs", [
                 %{
                   raw_description: "Synthetic source inserted without provenance fields.",
                   inserted_at: timestamp,
                   updated_at: timestamp
                 }
               ])

      job =
        Repo.get_by!(Job,
          raw_description: "Synthetic source inserted without provenance fields."
        )

      assert job.source_acquisition_method == :manual
      assert job.final_source_url == nil
      assert job.source_acquired_at == nil
      assert job.source_extractor_version == nil
      assert job.source_text_modified == false
    end

    test "rejects missing, empty, and whitespace-only raw descriptions" do
      for raw_description <- [nil, "", "  \n\t  "] do
        assert {:error, changeset} =
                 JobMarket.create_job(%{raw_description: raw_description})

        assert "can't be blank" in errors_on(changeset).raw_description
      end
    end

    test "allows company, role, and source URL to be omitted" do
      assert {:ok, job} = JobMarket.create_job(%{raw_description: "Source text"})
      assert job.company == nil
      assert job.role == nil
      assert job.source_url == nil
    end

    test "creates manual jobs explicitly and ignores untrusted provenance attrs" do
      acquired_at = ~U[2026-08-25 12:00:00.000000Z]

      attrs = %{
        "company" => "Corrected Company",
        "source_url" => "https://jobs.example/manual-reference",
        "raw_description" => "  Exact manual source\nwith preserved spacing.  ",
        "final_source_url" => "https://forged.example/final",
        "source_acquired_at" => acquired_at,
        "source_acquisition_method" => "generic_html",
        "source_extractor_version" => 999,
        "source_text_modified" => true
      }

      assert {:ok, job} = JobMarket.create_manual_job(attrs)
      assert job.company == "Corrected Company"
      assert job.source_url == "https://jobs.example/manual-reference"
      assert job.raw_description == "  Exact manual source\nwith preserved spacing.  "
      assert job.source_acquisition_method == :manual
      assert job.final_source_url == nil
      assert job.source_acquired_at == nil
      assert job.source_extractor_version == nil
      assert job.source_text_modified == false
    end

    test "lists saved jobs newest first" do
      older = job_fixture(%{raw_description: "Older source"})
      newer = job_fixture(%{raw_description: "Newer source"})

      assert [newer, older] == JobMarket.list_jobs()
    end

    test "deletes a saved job" do
      job = job_fixture()

      assert {:ok, %Job{}} = JobMarket.delete_job(job)
      assert_raise Ecto.NoResultsError, fn -> JobMarket.get_job!(job.id) end
    end

    test "returns a changeset for a job" do
      assert %Ecto.Changeset{} = JobMarket.change_job(%Job{})
    end

    test "recomputes Work Arrangement from a job's raw source" do
      job = job_fixture(%{raw_description: "This role is fully remote."})

      assert %{status: :known, arrangements: [:fully_remote]} =
               JobMarket.extract_work_arrangement(job)
    end

    test "creates acquired jobs from every supported trusted Draft method" do
      for method <- [:job_posting_json_ld, :generic_html, :plain_text] do
        draft = acquired_draft(method)

        attrs = %{
          company: "User-approved Company",
          role: "User-approved Role",
          source_url: "https://forged.example/requested",
          raw_description: draft.original_extracted_text,
          final_source_url: "https://forged.example/final",
          source_acquired_at: ~U[2030-01-01 00:00:00.000000Z],
          source_acquisition_method: :manual,
          source_extractor_version: 999,
          source_text_modified: true
        }

        assert {:ok, job} = JobMarket.create_acquired_job(attrs, draft)
        assert job.company == "User-approved Company"
        assert job.role == "User-approved Role"
        assert job.raw_description == draft.original_extracted_text
        assert job.source_url == draft.source_url
        assert job.final_source_url == draft.final_source_url
        assert job.source_acquired_at == draft.source_acquired_at
        assert job.source_acquisition_method == method
        assert job.source_extractor_version == draft.source_extractor_version
        assert job.source_text_modified == false
      end
    end

    test "tracks exact approved-source differences without normalizing text" do
      original = "First line\nSecond line"
      draft = acquired_draft(:generic_html, original)

      assert {:ok, unchanged} =
               JobMarket.create_acquired_job(%{"raw_description" => original}, draft)

      assert unchanged.raw_description == original
      assert unchanged.source_text_modified == false

      for changed <- ["First line\nSecond linE", "First line\r\nSecond line", original <> " "] do
        assert {:ok, job} =
                 JobMarket.create_acquired_job(%{raw_description: changed}, draft)

        assert job.raw_description == changed
        assert job.source_text_modified == true
      end
    end

    test "does not force Draft company or role suggestions into acquired jobs" do
      assert {:ok, job} =
               JobMarket.create_acquired_job(
                 %{raw_description: "Approved source text remains sufficiently explicit."},
                 acquired_draft(:generic_html)
               )

      assert job.company == nil
      assert job.role == nil
    end

    test "rejects incoherent trusted acquired provenance" do
      invalid_drafts = [
        {%{acquired_draft(:generic_html) | source_acquisition_method: :manual},
         :source_acquisition_method},
        {%{acquired_draft(:generic_html) | final_source_url: nil}, :final_source_url},
        {%{acquired_draft(:generic_html) | source_acquired_at: nil}, :source_acquired_at},
        {%{acquired_draft(:generic_html) | source_url: nil}, :source_url},
        {%{acquired_draft(:generic_html) | source_extractor_version: 0},
         :source_extractor_version}
      ]

      for {draft, field} <- invalid_drafts do
        assert {:error, changeset} =
                 JobMarket.create_acquired_job(%{raw_description: draft.raw_description}, draft)

        assert Map.has_key?(errors_on(changeset), field)
      end
    end

    test "Work Arrangement analyzes the final approved acquired source" do
      draft = acquired_draft(:job_posting_json_ld, "This role is on-site.")
      approved = "This role is fully remote."

      assert {:ok, job} =
               JobMarket.create_acquired_job(%{raw_description: approved}, draft)

      assert job.source_text_modified == true

      assert %{status: :known, arrangements: [:fully_remote]} =
               JobMarket.extract_work_arrangement(job)
    end

    test "delegates public-source fetching without database interaction" do
      assert {:error, %{reason: :unsupported_scheme, stage: :url_validation}} =
               JobMarket.fetch_public_source("file:///etc/passwd")
    end

    test "prepares a transient source draft through guarded fetching without creating a job" do
      before_count = Repo.aggregate(Job, :count)

      body = """
      <html><body><main><h1>Program Director</h1>
      <p>Lead complex programs across product, engineering, and operations teams.</p></main></body></html>
      """

      requester = fn opts ->
        request = Req.new(method: :get, url: opts[:url])
        response = Req.Response.new(status: 200, headers: [{"content-type", "text/html"}])
        {:cont, {_request, response}} = opts[:into].({:data, body}, {request, response})
        {:ok, response}
      end

      assert {:ok, %{raw_description: description, source_acquisition_method: :generic_html}} =
               JobMarket.prepare_source_draft("https://jobs.example/role",
                 resolver: fn
                   _host, :inet -> {:ok, [{8, 8, 8, 8}]}
                   _host, :inet6 -> {:ok, []}
                 end,
                 requester: requester,
                 fetched_at: fn -> ~U[2026-08-24 12:00:00Z] end
               )

      assert description =~ "Lead complex programs"
      assert Repo.aggregate(Job, :count) == before_count
    end

    test "passes a guarded fetch error through source-draft preparation" do
      assert {:error, %{reason: :unsupported_scheme, stage: :url_validation}} =
               JobMarket.prepare_source_draft("file:///etc/passwd")
    end
  end

  defp acquired_draft(method, text \\ "Complete synthetic source for a reviewed job posting.") do
    %Draft{
      company: nil,
      role: nil,
      raw_description: text,
      original_extracted_text: text,
      source_url: "https://jobs.example/requested-role",
      final_source_url: "https://careers.example/final-role",
      source_acquired_at: ~U[2026-08-25 12:00:00.123456Z],
      source_acquisition_method: method,
      source_extractor_version: 1,
      warnings: []
    }
  end
end
