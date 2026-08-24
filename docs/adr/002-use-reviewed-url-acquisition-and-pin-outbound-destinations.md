# Use Reviewed URL Acquisition and Pin Outbound Destinations

- Status: Accepted

## Context

Manual source paste preserves exactly what the user supplies, but it can omit relevant material elsewhere on a posting page or include excessive navigation and boilerplate. Accepting a public job-posting URL can improve capture, but arbitrary pages vary widely: useful content may be exposed through structured data or ordinary HTML, require JavaScript, be blocked by anti-bot controls, or be unavailable later.

Retrieved content also cannot safely be treated as authoritative or complete. Extraction may omit evidence, and users need to correct proposed Company, Role, or source text before that material becomes part of the durable corpus.

Fetching a user-supplied URL creates an outbound security boundary. Merely validating a hostname and then making an ordinary hostname-based request is insufficient because DNS may resolve differently at connection time, and every redirect creates a new destination that requires the same scrutiny.

## Decision

URL-first intake will coexist with manual source capture. The durable flow is:

```text
source URL
→ guarded acquisition
→ extraction
→ reviewable intake draft
→ user review or correction
→ Job creation
→ deterministic extraction and later analysis
```

Retrieval never directly creates a Job. It produces a transient draft containing available metadata, extracted text, acquisition provenance, and warnings. The user may correct Company, Role, and source text before explicitly saving. If retrieval fails or is inadequate, manual paste remains immediately available.

`raw_description` is the exact textual evidence approved by the user when the Job is saved. It is canonical input to deterministic and future semantic analysis, but it is not necessarily a verbatim copy of an upstream webpage. Manual and URL-derived intake converge at this persistence boundary, and downstream analysis remains acquisition-agnostic.

V1 will preserve lightweight acquisition provenance directly on the Job, including the user-supplied URL, a distinct final URL after redirects, acquisition time and method, extraction version, and whether fetched text was modified before saving. Exact schema fields and types remain implementation decisions. V1 will not persist raw HTML or full HTTP response bodies, source history, arbitrary warning prose, generic provenance documents, or suggestion provenance for Company and Role.

Acquisition is source-agnostic from the user's perspective. A user may submit any public job-posting URL without locating a canonical employer or ATS source. V1 will inspect usable `JobPosting` structured data, fall back to conservative generic HTML extraction, and rely on human review. Dedicated ATS adapters will be added only if real-world evidence justifies them; no generic adapter or plugin framework is implied.

Each outbound hop must:

1. parse and validate the logical URL;
2. resolve all relevant destinations;
3. classify every returned IPv4 and IPv6 address;
4. reject the destination if any result violates the public-address policy;
5. select an approved public address;
6. connect to that exact address without an uncontrolled second DNS resolution; and
7. retain the original hostname only for TLS certificate verification, SNI, and HTTP identity.

Redirects are bounded and repeat the complete validation process. V1 permits HTTPS on port 443 and HTTP on port 80, preferring HTTPS. The guarded acquisition boundary also enforces connection and request timeouts, bounded network and decompressed response sizes, accepted content types, safe URL logging, and untrusted-content handling. It sends no browser credentials or cookies, fetches no subresources, executes no scripts, and never renders fetched HTML as active content.

The existing Req/Finch/Mint stack will support the application-owned acquisition policy. SafeURL does not provide the complete required guarantees and Paraxial does not provide this outbound fetching boundary, so neither is adopted for this purpose. Exact client configuration, address ranges, limits, and parser rules remain implementation and test concerns.

## Consequences

- URL intake can improve capture completeness without replacing the dependable manual workflow.
- Human review is the final completeness boundary; the application does not claim arbitrary web extraction is semantically complete.
- Existing deterministic and future semantic analysis continue to consume one canonical textual source without knowledge of its acquisition method.
- Direct Job provenance is intentionally simple while each Job has one source capture. Multiple sources, recapture, history, comparison, or monitoring may later justify a separate source-capture model.
- Not retaining raw responses reduces storage, privacy exposure, and active-content risk, but exact extraction cannot necessarily be replayed after a page changes or disappears. A disappeared posting is preserved only through approved text and lightweight provenance.
- JavaScript rendering, authenticated scraping, CAPTCHA or anti-bot circumvention, canonical-source discovery, source monitoring, post-save source editing, and initial ATS-specific adapters remain deferred.
- Automated tests will use sanitized fixtures and stubbed network behavior rather than live job sites. Separate real-world QA will evaluate usefulness and completeness across representative source types.
- Generic HTML parsing will likely use Floki, but dependency approval and installation remain part of a later implementation plan.
