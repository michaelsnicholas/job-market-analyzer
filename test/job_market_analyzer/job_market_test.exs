defmodule JobMarketAnalyzer.JobMarketTest do
  use JobMarketAnalyzer.DataCase

  alias JobMarketAnalyzer.JobMarket
  alias JobMarketAnalyzer.JobMarket.Job

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
  end
end
