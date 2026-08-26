defmodule JobMarketAnalyzer.JobMarket.SourceAcquisition.ExtractorTest do
  use ExUnit.Case, async: true

  alias JobMarketAnalyzer.JobMarket.SourceAcquisition.{
    Draft,
    ExtractionError,
    Extractor,
    FetchResult,
    Suggestion
  }

  @fetched_at ~U[2026-08-24 12:00:00Z]

  describe "JobPosting JSON-LD" do
    test "extracts a single posting with suggestion provenance and structured text" do
      html = html_with_json_ld(job_posting())

      assert {:ok,
              %Draft{
                company: %Suggestion{value: "Example Company", source: :job_posting_json_ld},
                role: %Suggestion{value: "Director of Programs", source: :job_posting_json_ld},
                source_acquisition_method: :job_posting_json_ld,
                source_extractor_version: 2
              } = draft} = extract(html)

      assert draft.raw_description == draft.original_extracted_text
      assert draft.raw_description =~ "What you will do"
      assert draft.raw_description =~ "- Lead planning"
      assert draft.raw_description =~ "Benefits & compensation"
      assert draft.raw_description =~ "$120,000–$150,000"

      assert draft.raw_description ==
               """
               What you will do

               Build reliable programs across several teams.

               - Lead planning
               - Coach partners

               Benefits & compensation

               Salary range $120,000–$150,000.
               """
               |> String.trim()

      assert draft.source_url == "https://jobs.example/requested"
      assert draft.final_source_url == "https://careers.example/final"
      assert draft.source_acquired_at == @fetched_at
    end

    test "finds postings in @graph, top-level arrays, and nested structures" do
      containers = [
        %{"@context" => "https://schema.org", "@graph" => [job_posting()]},
        [%{"@type" => "Organization", "name" => "Ignore"}, job_posting()],
        %{"payload" => %{"items" => [job_posting()]}}
      ]

      for container <- containers do
        assert {:ok, %Draft{role: %Suggestion{value: "Director of Programs"}}} =
                 extract(html_with_json_ld(container))
      end
    end

    test "accepts @type arrays containing JobPosting" do
      posting = Map.put(job_posting(), "@type", ["Thing", "JobPosting"])

      assert {:ok, %Draft{source_acquisition_method: :job_posting_json_ld}} =
               extract(html_with_json_ld(posting))
    end

    test "ignores malformed and unrelated JSON-LD before using a valid posting" do
      html = """
      <html><head>
        <script type="application/ld+json">{invalid</script>
        <script type="application/ld+json">#{Jason.encode!(%{"@type" => "Organization"})}</script>
        <script type="application/ld+json">#{Jason.encode!(job_posting())}</script>
      </head><body></body></html>
      """

      assert {:ok, %Draft{role: %Suggestion{value: "Director of Programs"}}} = extract(html)
    end

    test "leaves missing company and role suggestions nil" do
      posting = job_posting() |> Map.delete("title") |> Map.delete("hiringOrganization")
      assert {:ok, %Draft{company: nil, role: nil}} = extract(html_with_json_ld(posting))
    end

    test "falls back to generic HTML when a posting has no usable description" do
      posting = Map.delete(job_posting(), "description")

      html = """
      <html><head><script type="application/ld+json">#{Jason.encode!(posting)}</script></head>
      <body><main><h1>Operations Lead</h1><p>Own planning and delivery for a growing product team.</p></main></body></html>
      """

      assert {:ok,
              %Draft{
                source_acquisition_method: :generic_html,
                warnings: warnings,
                role: %Suggestion{value: "Operations Lead", source: :page_metadata}
              }} = extract(html)

      assert :generic_extraction in warnings
    end

    test "uses narrow title metadata to select one of multiple postings" do
      first = job_posting(%{"title" => "Operations Lead"})

      second =
        job_posting(%{
          "title" => "Finance Lead",
          "description" =>
            "<p>Lead financial planning for the organization and advise senior leaders.</p>"
        })

      html = """
      <html><head><title>Finance Lead at Example Company</title>
      <script type="application/ld+json">#{Jason.encode!([first, second])}</script></head><body></body></html>
      """

      assert {:ok, %Draft{role: %Suggestion{value: "Finance Lead"}, warnings: warnings}} =
               extract(html)

      assert :multiple_job_postings in warnings
    end

    test "returns a stable ambiguity error for unrelated multiple postings" do
      postings = [
        job_posting(%{"title" => "Operations Lead"}),
        job_posting(%{"title" => "Finance Lead"})
      ]

      assert {:error, %ExtractionError{reason: :ambiguous_job_postings, stage: :extraction}} =
               extract(html_with_json_ld(postings))
    end

    test "extracts direct JSON objects, arrays, and @graph consistently" do
      for value <- [job_posting(), [job_posting()], %{"@graph" => [job_posting()]}] do
        assert {:ok, %Draft{source_acquisition_method: :job_posting_json_ld}} =
                 value |> Jason.encode!() |> extract("application/json")
      end
    end

    test "fails cleanly for malformed or unrelated direct JSON" do
      for body <- ["{bad", Jason.encode!(%{"@type" => "Organization"})] do
        assert {:error, %ExtractionError{reason: :inadequate_extraction}} =
                 extract(body, "application/ld+json")
      end
    end

    test "reconciles a uniquely anchored partial description with coherent DOM continuation" do
      partial =
        "Build products that help people communicate, create, and connect across the world."

      posting = job_posting(%{"description" => partial, "title" => "Product Director"})

      html = """
      <html><body>
        <header>Careers navigation and unrelated company promotion</header>
        <section class="opaque-layout-class">
          <p>#{partial}</p>
          <div aria-hidden="true">decorative spacer</div>
          <h2>Responsibilities</h2>
          <ul>
            <li>Set product strategy across several customer experiences.</li>
            <li>Lead teams through discovery, delivery, and iteration.</li>
          </ul>
          <h2>Qualifications</h2>
          <p>Extensive experience building consumer products with engineering and design teams.</p>
          <h2>Compensation</h2>
          <p>Competitive salary, bonus, equity, and comprehensive benefits.</p>
          <form>Application questions and private candidate information</form>
          <div>Apply</div>
        </section>
        <aside>Related jobs and unrelated editorial content</aside>
        <script type="application/ld+json">#{Jason.encode!(posting)}</script>
      </body></html>
      """

      assert {:ok,
              %Draft{
                company: %Suggestion{value: "Example Company", source: :job_posting_json_ld},
                role: %Suggestion{value: "Product Director", source: :job_posting_json_ld},
                source_acquisition_method: :job_posting_json_ld_reconciled,
                raw_description: text
              }} = extract(html)

      assert String.starts_with?(text, partial)
      assert text =~ "Responsibilities"
      assert text =~ "- Set product strategy"
      assert text =~ "Qualifications"
      assert text =~ "Extensive experience"
      assert text =~ "Compensation"
      refute text =~ "Careers navigation"
      refute text =~ "Application questions"
      refute text =~ "Apply"
      refute text =~ "Related jobs"
    end

    test "keeps complete structured descriptions on the ordinary JSON-LD path" do
      description =
        "Lead product strategy across engineering and design while delivering reliable customer experiences."

      html = """
      <html><body><article><p>#{description}</p></article>
      <script type="application/ld+json">#{Jason.encode!(job_posting(%{"description" => description}))}</script>
      </body></html>
      """

      assert {:ok,
              %Draft{
                raw_description: ^description,
                source_acquisition_method: :job_posting_json_ld
              }} = extract(html)
    end

    test "does not reconcile nonunique DOM anchors" do
      partial = "Lead a large product area with engineering, design, and research partners."
      posting = job_posting(%{"description" => partial})

      repeated_region = """
      <section><p>#{partial}</p><h2>Responsibilities</h2>
      <ul><li>Set strategy for a substantial portfolio of customer products.</li></ul>
      <h2>Qualifications</h2><p>Extensive experience leading cross-functional teams.</p></section>
      """

      html = """
      <html><body>#{repeated_region}#{repeated_region}
      <script type="application/ld+json">#{Jason.encode!(posting)}</script></body></html>
      """

      assert {:ok,
              %Draft{
                raw_description: ^partial,
                source_acquisition_method: :job_posting_json_ld
              }} = extract(html)
    end

    test "does not reconcile through a substantial unrelated sibling boundary" do
      partial = "Lead product development with engineering, design, and customer research teams."
      posting = job_posting(%{"description" => partial})

      html = """
      <html><body><section>
        <p>#{partial}</p>
        <aside><h2>Latest company news</h2><p>This unrelated editorial feature contains substantial content.</p></aside>
        <h2>Responsibilities</h2>
        <ul><li>Set strategy and guide delivery across several product teams.</li></ul>
        <h2>Qualifications</h2><p>Extensive relevant leadership experience.</p>
      </section><script type="application/ld+json">#{Jason.encode!(posting)}</script></body></html>
      """

      assert {:ok,
              %Draft{
                raw_description: ^partial,
                source_acquisition_method: :job_posting_json_ld
              }} = extract(html)
    end

    test "preserves structured text when adjacent DOM content is insufficient evidence" do
      partial = "Lead product development with engineering, design, and customer research teams."
      posting = job_posting(%{"description" => partial})

      html = """
      <html><body><section><p>#{partial}</p>
      <p>Read more about the company and its products.</p></section>
      <script type="application/ld+json">#{Jason.encode!(posting)}</script></body></html>
      """

      assert {:ok,
              %Draft{
                raw_description: ^partial,
                source_acquisition_method: :job_posting_json_ld
              }} = extract(html)
    end
  end

  describe "generic HTML" do
    test "extracts a clean main or article while preserving headings, bullets, and Unicode" do
      for tag <- ["main", "article"] do
        html = """
        <html><body><#{tag}><h1>Program Lead — Europe</h1><p>Build reliable systems.</p>
        <h2>Responsibilities</h2><ul><li>Lead planning</li><li>Coach teams</li></ul></#{tag}></body></html>
        """

        assert {:ok, %Draft{raw_description: text, warnings: warnings}} = extract(html)
        assert text =~ "Program Lead — Europe"
        assert text =~ "Responsibilities"
        assert text =~ "- Lead planning"
        assert text =~ "- Coach teams"
        assert text =~ "Program Lead — Europe\n\nBuild reliable systems."
        assert text =~ "Responsibilities\n\n- Lead planning\n- Coach teams"
        assert :generic_extraction in warnings
      end
    end

    test "removes navigation, footer, forms, scripts, styles, and modal or cookie noise" do
      html = """
      <html><body>
      <nav>Unwanted navigation links and account controls</nav>
      <main><h1>Product Operations Lead</h1><p>Own operating rhythms and cross-team delivery.</p>
      <section><h2>Benefits</h2><p>Health coverage and a salary range of $100,000–$130,000.</p></section></main>
      <form>Apply now with private information</form><script>secretState()</script><style>.x{}</style>
      <div class="cookie-banner">Accept every tracking cookie</div><dialog>Subscribe now</dialog>
      <footer>Generic careers links and social media</footer>
      </body></html>
      """

      assert {:ok, %Draft{raw_description: text}} = extract(html)
      assert text =~ "Benefits"
      assert text =~ "$100,000–$130,000"

      for removed <- [
            "navigation",
            "Apply now",
            "secretState",
            "tracking cookie",
            "Subscribe",
            "social media"
          ] do
        refute text =~ removed
      end
    end

    test "uses a plausible generic job-description container without ATS-specific rules" do
      html = """
      <html><body><header>Large careers masthead with unrelated promotional language</header>
      <div class="job-description-content"><h1>Research Program Manager</h1>
      <p>Coordinate research programs across engineering and design teams.</p></div>
      <aside>Recommended roles and newsletter promotions repeated many times.</aside></body></html>
      """

      assert {:ok, %Draft{raw_description: text}} = extract(html)
      assert text =~ "Coordinate research programs"
      refute text =~ "Recommended roles"
    end

    test "prefers a job__description root and confirms Greenhouse-shaped title metadata" do
      html = """
      <html>
        <head>
          <title>Job Application for Head of Product (Mail) at Proton</title>
          <meta property="og:title" content="Head of Product (Mail)">
        </head>
        <body>
          <main class="main font-secondary job-post">
            <a href="/jobs">Back to jobs</a>
            <div class="job__header">
              <h1>Head of Product (Mail)</h1>
              <div class="job__location">London; Paris; Geneva</div>
              <a href="#application">Apply</a>
            </div>
            <div class="job__description body">
              <h2>Join the product team</h2>
              <p>Lead the strategy and roadmap for a privacy-focused communications product used by people around the world.</p>
              <h2>What you will do</h2>
              <ul><li>Set a clear product vision.</li><li>Coach and support product managers.</li></ul>
              <form>Application fields must not become source text.</form>
              <script>untrustedPageState()</script>
            </div>
          </main>
        </body>
      </html>
      """

      assert {:ok,
              %Draft{
                company: %Suggestion{value: "Proton", source: :page_metadata},
                role: %Suggestion{value: "Head of Product (Mail)", source: :page_metadata},
                raw_description: text,
                source_acquisition_method: :generic_html,
                warnings: [:generic_extraction]
              }} = extract(html)

      assert String.starts_with?(text, "Join the product team")
      assert text =~ "Set a clear product vision."

      for excluded <- [
            "Back to jobs",
            "London; Paris; Geneva",
            "Apply",
            "Application fields",
            "untrustedPageState"
          ] do
        refute text =~ excluded
      end
    end

    test "does not trust a Job Application title when the unique h1 disagrees" do
      html = """
      <html>
        <head><title>Job Application for Product Director at Example Company</title></head>
        <body><main>
          <h1>Engineering Director</h1>
          <div class="job__description">
            <p>Lead a substantial engineering organization and its long-term technical strategy.</p>
          </div>
        </main></body>
      </html>
      """

      assert {:ok,
              %Draft{
                company: nil,
                role: nil,
                source_acquisition_method: :generic_html,
                warnings: warnings
              }} = extract(html)

      assert :metadata_conflict in warnings
    end

    test "does not trust a Job Application title without a unique h1" do
      html = """
      <html>
        <head><title>Job Application for Product Director at Example Company</title></head>
        <body><main>
          <div class="job__description">
            <p>Lead a substantial product organization and its long-term customer strategy.</p>
          </div>
        </main></body>
      </html>
      """

      assert {:ok, %Draft{company: nil, role: nil, warnings: warnings}} = extract(html)
      assert :metadata_conflict in warnings
    end

    test "marks body fallback as possible boilerplate" do
      html = """
      <html><body><h1>Technical Program Manager</h1>
      <p>Lead complex programs across infrastructure, security, and customer-facing teams.</p></body></html>
      """

      assert {:ok, %Draft{warnings: warnings}} = extract(html)
      assert warnings == [:generic_extraction, :short_source, :possible_boilerplate]
    end

    test "fails cleanly for a JS shell or blank page" do
      for html <- [
            "<html><body><div id='app'>Enable JavaScript</div></body></html>",
            "<html><body> </body></html>",
            "<html><head><title>Security check</title></head><body><main><h1>Verify you are human</h1><p>Complete the CAPTCHA to continue to the requested careers page.</p></main></body></html>"
          ] do
        assert {:error, %ExtractionError{reason: :inadequate_extraction}} = extract(html)
      end
    end

    test "rejects authentication and account-access interstitials" do
      pages = [
        """
        <html><head><title>Sign in</title></head><body><main><h1>Sign in</h1>
        <p>Continue with Google</p><p>Continue with Apple</p><p>Forgot your password?</p>
        </main></body></html>
        """,
        """
        <html><body><main><h1>Log in to continue</h1><p>Email address</p><p>Password</p>
        <p>Forgot password?</p><p>By continuing you agree to the Privacy Policy and Terms.</p>
        </main></body></html>
        """,
        """
        <html><body><main><h1>Check your inbox</h1><p>We sent you a one-time link.</p>
        <p>Enter the verification code or resend email, then sign in.</p></main></body></html>
        """,
        """
        <html><body><main><h1>Create an account</h1><p>Join now or continue with Google.</p>
        <p>Already registered? Log in.</p><p>Agree &amp; Join</p></main></body></html>
        """
      ]

      for html <- pages do
        assert {:error, %ExtractionError{reason: :inadequate_extraction}} = extract(html)
      end
    end

    test "does not reject substantive postings with incidental account language" do
      pages = [
        """
        <html><body><main><h1>Operations Lead</h1><h2>Responsibilities</h2>
        <p>Lead planning across product, engineering, and customer operations.</p>
        <p>You may need to sign in once to submit your application.</p></main></body></html>
        """,
        """
        <html><body><main><h1>Program Director</h1><h2>Qualifications</h2>
        <p>Bring extensive experience leading complex programs across several teams.</p>
        <p>To apply, create an account, log in, check your inbox for a one-time link, and enter the verification code.</p>
        </main></body></html>
        """,
        """
        <html><body><main><h1>Engineering Manager</h1><h2>What you’ll do</h2>
        <p>Build a supportive engineering organization and deliver reliable products for customers.</p>
        <h2>Benefits</h2><p>Competitive compensation and comprehensive health coverage.</p>
        <p>We are an equal opportunity employer. See our privacy policy before applying.</p>
        </main></body></html>
        """
      ]

      for html <- pages do
        assert {:ok, %Draft{source_acquisition_method: :generic_html}} = extract(html)
      end
    end

    test "keeps representative generic employer and aggregator pages usable" do
      pages = [
        """
        <html><head><title>Chief of Staff at Example Works</title></head><body><main>
        <h1>Chief of Staff</h1><h2>Role overview</h2>
        <p>Partner with company leadership to establish priorities and improve execution.</p>
        <h2>Requirements</h2><ul><li>Experience leading cross-functional programs</li></ul>
        </main></body></html>
        """,
        """
        <html><body><main><article><h1>Product Operations Director</h1>
        <h2>Job description</h2><p>Lead operating programs across product and engineering.</p>
        <h2>Qualifications</h2><ul><li>Seven years of relevant experience</li></ul>
        <h2>Benefits</h2><p>Health coverage and flexible paid time off.</p>
        </article></main></body></html>
        """
      ]

      for html <- pages do
        assert {:ok, %Draft{source_acquisition_method: :generic_html}} = extract(html)
      end
    end
  end

  describe "metadata suggestions and invariants" do
    test "JSON-LD suggestions outrank conflicting page metadata" do
      html = """
      <html><head><title>Different Role at Different Company</title>
      <script type="application/ld+json">#{Jason.encode!(job_posting())}</script></head>
      <body><h1>Another Role</h1></body></html>
      """

      assert {:ok,
              %Draft{
                company: %Suggestion{value: "Example Company"},
                role: %Suggestion{value: "Director of Programs"},
                warnings: warnings
              }} = extract(html)

      refute :metadata_conflict in warnings
    end

    test "usable JSON-LD takes precedence over authentication language in page chrome" do
      html = """
      <html><head><title>Sign in to continue</title>
      <script type="application/ld+json">#{Jason.encode!(job_posting())}</script></head>
      <body><main><h1>Sign in</h1><p>Continue with Google or Apple.</p>
      <p>Create an account or log in with your password.</p></main></body></html>
      """

      assert {:ok,
              %Draft{
                source_acquisition_method: :job_posting_json_ld,
                role: %Suggestion{value: "Director of Programs"}
              }} = extract(html)
    end

    test "derives conservative role and company suggestions from an aligned title and H1" do
      html = """
      <html><head><title>Platform Program Lead at Example Company</title></head>
      <body><main><h1>Platform Program Lead</h1><p>Lead platform programs across engineering teams and business partners.</p></main></body></html>
      """

      assert {:ok,
              %Draft{
                role: %Suggestion{value: "Platform Program Lead", source: :page_metadata},
                company: %Suggestion{value: "Example Company", source: :page_metadata}
              }} = extract(html)
    end

    test "returns nil suggestions and a warning when metadata conflicts" do
      html = """
      <html><head><title>Platform Lead at Example Company</title>
      <meta property="og:title" content="Finance Lead at Other Company"></head>
      <body><main><h1>Unrelated Heading</h1><p>Lead a substantial cross-functional program across several teams.</p></main></body></html>
      """

      assert {:ok, %Draft{company: nil, role: nil, warnings: warnings}} = extract(html)
      assert :metadata_conflict in warnings
    end

    test "leaves missing suggestions nil and canonicalizes warning order" do
      html = """
      <html><body><main><p>This posting contains useful source material but no reliable role or company metadata.</p></main></body></html>
      """

      assert {:ok, %Draft{company: nil, role: nil, warnings: warnings}} = extract(html)
      assert warnings == Enum.uniq(warnings)
      assert warnings == [:generic_extraction, :short_source]
      assert Extractor.version() == 2
    end

    test "accepts useful plain text without inventing metadata" do
      text =
        "Role overview\n\nLead complex programs across engineering, operations, and customer teams."

      assert {:ok, %Draft{company: nil, role: nil, source_acquisition_method: :plain_text}} =
               extract(text, "text/plain")
    end
  end

  defp extract(body, content_type \\ "text/html") do
    Extractor.extract(%FetchResult{
      requested_url: "https://jobs.example/requested",
      final_url: "https://careers.example/final",
      fetched_at: @fetched_at,
      status: 200,
      content_type: content_type,
      content_encoding: :identity,
      body: body,
      network_bytes: byte_size(body),
      decompressed_bytes: byte_size(body),
      redirect_count: 1
    })
  end

  defp html_with_json_ld(value) do
    """
    <html><head><script type="application/ld+json">#{Jason.encode!(value)}</script></head>
    <body><main><p>Generic fallback content that should not outrank usable structured data.</p></main></body></html>
    """
  end

  defp job_posting(overrides \\ %{}) do
    Map.merge(
      %{
        "@context" => "https://schema.org",
        "@type" => "JobPosting",
        "title" => "Director of Programs",
        "hiringOrganization" => %{"@type" => "Organization", "name" => "Example Company"},
        "description" => """
        <h2>What you will do</h2><p>Build reliable programs across several teams.</p>
        <ul><li>Lead planning</li><li>Coach partners</li></ul>
        <h2>Benefits &amp; compensation</h2><p>Salary range $120,000–$150,000.</p>
        """
      },
      overrides
    )
  end
end
