# BugHunter-OS Architecture

BugHunter-OS is an enterprise-grade Bug Bounty Automation Framework for Kali Linux. This document is the master blueprint for the project and defines the target architecture, component boundaries, execution model, configuration model, and long-term evolution path.

The architecture is written for the production target, not the current scaffold. Some implementation files in the repository may lag behind this design during the build-out phase.

## 1. Project Vision

BugHunter-OS exists to automate the full authorized bug bounty workflow from a single command:

```bash
./bughunter scan target.com
```

The framework should take a validated target and drive a complete, low-friction security workflow that includes recon, enumeration, fingerprinting, WAF detection, adaptive rate limiting, JavaScript analysis, API discovery, secret discovery, vulnerability discovery, evidence collection, screenshot collection, and report generation.

### Purpose

The purpose of BugHunter-OS is to reduce the manual overhead of repeated bug bounty operations without reducing rigor. It should let an operator express intent at the target level and have the system coordinate the rest through deterministic workflows, guarded automation, and auditable artifacts.

### Design Goals

- Single entrypoint for the full scan lifecycle.
- Production-grade reliability on Kali Linux.
- Safe-by-default behavior with explicit active scanning controls.
- Modular execution with clear responsibility boundaries.
- Resume support for interrupted or long-running scans.
- Structured outputs that can feed both human reporting and downstream automation.
- Adaptive behavior based on target defenses, scan scope, and prior results.
- Clean separation between orchestration, plugins, state, reporting, and evidence.

### Problems It Solves

- Removes the need to manually chain dozens of command-line tools.
- Normalizes scan data across disparate recon and vulnerability tools.
- Reduces missed steps in the bug bounty workflow.
- Preserves evidence and run state automatically.
- Makes large target surfaces tractable through deterministic scheduling.
- Provides a consistent reporting surface across mixed tool outputs.

### Intended Users

- Bug bounty hunters working within explicit authorization and scope.
- Internal security teams performing sanctioned web application assessment.
- Red teams operating under approved rules of engagement.
- Security engineers maintaining recurring asset discovery and validation workflows.
- Platform teams that need reproducible scan orchestration across many targets.

### Operating Assumptions

- The user has authorization to test the target.
- The host is a Kali Linux-based environment or compatible Debian-based system.
- External tools may be missing and need installation or verification.
- Target scale may vary from a single domain to a large organization-owned estate.
- Long-running scans must be resumable.

## 2. High Level Architecture

The system is organized as an orchestration layer over a plugin-driven scan engine. The CLI delegates to the core engine, which resolves configuration, loads plugins, schedules work, manages state, and routes results to evidence and reporting systems.

```text
CLI
  |
  v
Core Engine
  |
  +--> Configuration Manager
  |
  +--> Logger
  |
  +--> Resume Manager
  |
  +--> Dependency Manager
  |
  +--> Auto Update Manager
  |
  v
Scheduler
  |
  +--> Queue
  |      |
  |      +--> Plugin Manager
  |      |       |
  |      |       +--> Recon Engine
  |      |       +--> Fingerprint Engine
  |      |       +--> Enumeration Engine
  |      |       +--> WAF Engine
  |      |       +--> JavaScript Engine
  |      |       +--> API Engine
  |      |       +--> Secrets Engine
  |      |       +--> Vulnerability Engine
  |      |       +--> Evidence Engine
  |      |       +--> Reporting Engine
  |      |
  |      +--> State Store
  |
  v
Adaptive Scan Engine
  |
  v
Evidence Store + Reports + Dashboard + Notifications
```

### Architectural Style

BugHunter-OS uses a layered, plugin-oriented architecture:

- The CLI validates intent and hands off execution.
- The core engine owns lifecycle, state, and policy enforcement.
- The scheduler orders and throttles work.
- Plugins execute domain-specific tasks.
- Shared utilities provide logging, configuration, locks, progress, caching, and validation.
- Output subsystems persist artifacts and reports.

### Key Constraint

No plugin should own orchestration policy. Plugins should do work; the core engine should decide when, how often, and in what order.

## 3. Folder Structure

The final repository should converge on the following structure. The tree below reflects the target architecture, not the current placeholder scaffold.

```text
BugHunter-OS/
├── ARCHITECTURE.md
├── README.md
├── bughunter.sh
├── config/
│   ├── config.conf
│   └── profiles/
│       ├── safe.conf
│       ├── balanced.conf
│       └── deep.conf
├── core/
│   ├── cli.sh
│   ├── engine.sh
│   ├── loader.sh
│   ├── scheduler.sh
│   ├── queue.sh
│   ├── plugin-manager.sh
│   ├── dependency-manager.sh
│   ├── update-manager.sh
│   ├── resume-manager.sh
│   ├── policy.sh
│   └── scanner.sh
├── plugins/
│   ├── recon/
│   ├── fingerprint/
│   ├── waf/
│   ├── enumeration/
│   ├── rate-limit/
│   ├── javascript/
│   ├── api/
│   ├── secrets/
│   ├── wordpress/
│   ├── vulnerability/
│   ├── evidence/
│   └── reporting/
├── utils/
│   ├── colors.sh
│   ├── logger.sh
│   ├── config.sh
│   ├── helpers.sh
│   ├── progress.sh
│   ├── spinner.sh
│   ├── banner.sh
│   ├── cache.sh
│   ├── validator.sh
│   ├── output.sh
│   ├── cleanup.sh
│   ├── parallel.sh
│   ├── locks.sh
│   ├── signals.sh
│   └── version.sh
├── state/
│   ├── runs/
│   ├── checkpoints/
│   ├── manifests/
│   └── resume/
├── cache/
│   ├── dns/
│   ├── http/
│   ├── waf/
│   ├── templates/
│   └── plugins/
├── reports/
│   ├── html/
│   ├── markdown/
│   ├── json/
│   ├── csv/
│   └── pdf/
├── logs/
├── screenshots/
│   ├── raw/
│   ├── processed/
│   └── thumbnails/
├── templates/
│   ├── nuclei/
│   ├── report/
│   ├── dashboards/
│   └── exports/
├── wordlists/
│   ├── common/
│   ├── payloads/
│   ├── parameters/
│   ├── technologies/
│   └── signatures/
├── docs/
│   ├── operations/
│   ├── architecture/
│   └── runbooks/
├── tests/
│   ├── unit/
│   ├── integration/
│   └── fixtures/
├── output/
└── install/
    └── install.sh
```

### Directory Roles

- `core/` contains orchestration and policy logic.
- `plugins/` contains functional scanning capabilities.
- `utils/` contains shared shell utilities and cross-cutting support.
- `state/` persists run metadata, resume checkpoints, and manifests.
- `cache/` stores normalized reusable intelligence and temporary lookup artifacts.
- `reports/` stores final human and machine consumable reporting output.
- `logs/` stores run logs and lifecycle events.
- `screenshots/` stores visual evidence.
- `templates/` stores report and scan templates.
- `wordlists/` stores curated payloads and lookup data.
- `docs/` stores operator and maintenance documentation.
- `tests/` stores automated validation.

### Compatibility Note

The current repository uses `modules/` as a shell-script container. The target architecture treats that area as a transitional compatibility layer until plugin directories are fully adopted. The design goal is not to abandon existing work, but to organize it under clearer orchestration boundaries.

## 4. Core Components

### CLI

The CLI is the operator-facing entrypoint. It must:

- Parse commands and flags.
- Validate targets and scope inputs.
- Load the selected profile and overrides.
- Trigger dependency checks and updates.
- Launch scans or report generation.
- Route high-level errors to the logger.

The CLI should remain thin. It should not contain scan logic.

### Loader

The loader assembles the runtime environment:

- Reads configuration.
- Resolves workspace paths.
- Loads utility libraries.
- Loads plugins by discovery rules.
- Applies profile-specific defaults.

The loader must be deterministic so repeated runs under the same config behave the same way.

### Scheduler

The scheduler decides what runs next, in what order, and at what concurrency. It owns:

- Task ordering.
- Stage boundaries.
- Retry policy.
- Backpressure.
- Adaptive throttling hooks.

The scheduler is policy-aware. It should not call plugins randomly or in parallel without accounting for target sensitivity and scan phase.

### Queue

The queue is the in-memory or persisted work list of pending jobs. It should support:

- FIFO behavior for predictable stages.
- Priority inserts for critical work.
- Deduplication.
- Replay from state.
- Checkpointed resume.

### Plugin Manager

The plugin manager:

- Discovers plugins.
- Verifies metadata and compatibility.
- Registers plugin capabilities.
- Resolves dependencies between plugins.
- Enforces plugin permissions and stage bindings.

### Updater

The updater is responsible for:

- Tool version verification.
- Go-based tool installation and refresh.
- Nuclei template updates.
- Wordlist updates.
- Optional project update checks.

Updates must be controlled, auditable, and never surprise the operator.

### Resume Manager

The resume manager:

- Stores checkpoints.
- Restores interrupted scan state.
- Detects partial stage completion.
- Reconciles outputs after a restart.

### Logger

The logger:

- Produces timestamped console output.
- Produces file logs.
- Supports debug and verbose modes.
- Handles log rotation.
- Avoids losing entries under concurrency.

### Configuration Manager

The configuration manager:

- Loads `config/config.conf`.
- Applies local overrides.
- Normalizes path and boolean types.
- Resolves profile-based settings.
- Exposes validated values to core and plugins.

## 5. Plugin System

The plugin system is the main extensibility mechanism. Every meaningful scan capability should be implemented as a plugin rather than as ad hoc code in the CLI.

### Discovery

Plugins are discovered through filesystem rules and metadata:

- Directory-based discovery under `plugins/`.
- Manifest files describing plugin name, stage, inputs, outputs, and dependencies.
- Optional compatibility metadata for current `modules/` implementations.

Discovery should be fast and cached between runs.

### Registration

Each plugin registers:

- Canonical name.
- Stage or stages where it can run.
- Input contract.
- Output contract.
- Required tools.
- Optional tools.
- Safe-mode support.
- Resume support.

### Communication

Plugins communicate through structured artifacts, not shell text parsing whenever possible:

- JSON manifests.
- NDJSON streams.
- Shared state records.
- Files in `state/`, `cache/`, and `output/`.
- Explicit return codes.

Plugins should not depend on each other through hidden side effects.

### Lifecycle

The expected lifecycle is:

1. Discover plugin.
2. Validate plugin metadata.
3. Load plugin.
4. Resolve dependencies.
5. Execute setup hook.
6. Run plugin work.
7. Persist outputs.
8. Emit status and metrics.
9. Execute cleanup hook.
10. Record completion or failure in state.

### Plugin Contract

Each plugin should define:

- `register`
- `prepare`
- `run`
- `checkpoint`
- `cleanup`

Plugins may expose additional hooks, but those are the baseline.

## 6. Scan Lifecycle

The scan lifecycle is a staged pipeline. A run should move through the stages below in a controlled way.

```text
Input
  |
  v
Validation
  |
  v
Configuration
  |
  v
Dependency Check
  |
  v
Auto Update
  |
  v
Recon
  |
  v
Fingerprint
  |
  v
Enumeration
  |
  v
Prioritization
  |
  v
Scanning
  |
  v
Evidence
  |
  v
Reporting
```

### Detailed Flow

1. Input: accept target, profile, scope file, or scan options.
2. Validation: reject empty targets, invalid URLs, and out-of-scope inputs.
3. Configuration: resolve profile, directories, secrets, and limits.
4. Dependency Check: verify local binaries and update eligibility.
5. Auto Update: refresh approved tools and templates when allowed.
6. Recon: enumerate domains, subdomains, URLs, and live services.
7. Fingerprint: determine technologies, frameworks, and edge protections.
8. Enumeration: collect endpoints, parameters, JS files, APIs, and assets.
9. Prioritization: rank candidates by attack surface and contextual risk.
10. Scanning: run vulnerability plugins and targeted checks.
11. Evidence: collect screenshots, request/response data, and reproductions.
12. Reporting: summarize findings in multiple formats.

### Stage Boundaries

Each stage must emit a checkpoint so a failed run can resume safely.

## 7. Module Responsibilities

This section defines canonical responsibilities for the major capability groups.

### Recon

Recon discovers the externally visible target surface:

- Root domains.
- Subdomains.
- Hosts.
- Live services.
- Associated URLs.
- Historical URLs.

Recon must normalize and deduplicate results before passing them forward.

### HTTPX

HTTPX or an equivalent probing engine should:

- Confirm liveness.
- Detect schemes and ports.
- Capture status, title, tech, and TLS metadata.
- Apply rate limits and retry policy.
- Feed downstream fingerprinting and prioritization.

### Naabu

Naabu or an equivalent port discovery plugin should:

- Detect exposed web-relevant ports.
- Integrate with host and service records.
- Respect conservative scanning defaults.

### Katana

Katana or equivalent crawling should:

- Crawl live web targets.
- Respect crawl depth and duration.
- Emit URLs, forms, and content paths.
- Filter duplicates and non-actionable noise.

### GAU

GAU or equivalent historical URL collection should:

- Aggregate archived URLs.
- Merge with crawler output.
- Provide discovery breadth before active checks.

### Wayback

Wayback acquisition should:

- Pull archived endpoint data from history sources.
- Normalize URL structures and deduplicate paths.

### JavaScript

JavaScript analysis should:

- Enumerate JS assets.
- Fetch and cache JS files.
- Extract endpoints, secrets, comments, and API usage.
- Identify source maps where available.

### Secrets

Secret discovery should:

- Scan text, code, and metadata for credential patterns.
- Assess confidence and false positive risk.
- Preserve evidence without exposing secrets beyond what is required for reporting.

### WordPress

WordPress detection and analysis should:

- Identify WordPress footprints.
- Enumerate version and plugin clues.
- Target known weak signals while respecting safe-mode behavior.

### API

API discovery should:

- Infer REST, GraphQL, and custom endpoints.
- Correlate JS-discovered paths with live traffic.
- Locate schema and documentation artifacts.

### Nuclei

Nuclei or template-based scanning should:

- Run template checks against validated targets.
- Respect severity filters and exclude tags.
- Record template hits and evidence.

### Dalfox

Dalfox-style XSS support should:

- Identify reflected, stored, and DOM-influenced vectors where allowed.
- Remain opt-in or profile-bound due to impact.

### SQLMap

SQL injection automation should:

- Remain tightly controlled and profile-gated.
- Avoid noisy or destructive defaults.
- Require explicit active mode or deep profile approval.

### IDOR

IDOR analysis should:

- Compare similar objects and parameterized requests.
- Identify probable object-level authorization issues.

### SSRF

SSRF analysis should:

- Look for controllable fetch behavior and callback surfaces.
- Use conservative request patterns and controlled egress validation.

### LFI

LFI analysis should:

- Test file inclusion patterns only when allowed by profile and scope.
- Avoid destructive payloads.

### Redirect

Open redirect analysis should:

- Identify redirect sinks.
- Validate exploitability with low-impact probes.

### Reporting

Reporting should:

- Merge findings.
- Deduplicate evidence.
- Normalize severity.
- Produce human and machine-readable output.

## 8. Configuration Design

Configuration is the control plane of the system.

### Layout

- `config/config.conf` stores global defaults.
- `config/profiles/*.conf` stores profile overlays.
- `config/local.conf` or an ignored equivalent stores private overrides.
- Environment variables can override selected runtime values.

### Categories

Configuration values should be grouped by concern:

- Profiles.
- Threads.
- Timeout values.
- Retries.
- Rate limits.
- Tool paths.
- API keys.
- Directories.
- User agents.
- Plugin toggles.
- Reporting formats.

### Profiles

Profiles are a first-class runtime concept:

- `safe` for passive or minimally invasive operation.
- `balanced` for normal bug bounty usage.
- `deep` for more exhaustive and higher-impact workflows.

Profile resolution should define:

- Which plugins are enabled.
- Which rate limits apply.
- Which retries and timeouts apply.
- Which evidence actions are enabled.

### Secrets

Sensitive values must never be committed. The system should support:

- Environment variables.
- Local override files.
- External secrets management in future enterprise mode.

### User Agents

The user agent must be configurable at global and adaptive levels. It should not be hardcoded in plugin logic.

## 9. Logging Strategy

Logging is mandatory and central to correctness.

### Console Logging

Console output is for operator awareness:

- Short, readable status lines.
- Progress indicators.
- Error visibility.
- Color when available.

### File Logging

File logging is the canonical audit trail:

- Timestamped entries.
- Stage and plugin identifiers.
- Errors and warnings.
- Update and dependency events.
- Resume checkpoints.

### Debug Mode

Debug mode should expose:

- Plugin decisions.
- Configuration resolution.
- Queue operations.
- Retry behavior.
- Adaptive policy changes.

### Verbose Mode

Verbose mode should expose:

- Stage transitions.
- More detailed status on work completion.
- Additional evidence paths and metrics.

### Error Logging

Errors should always include:

- Timestamp.
- Severity.
- Component.
- Action.
- Exit code or failure class.

### Log Rotation

Logs should rotate by:

- Date.
- Size threshold.
- Run identity.

Rotation must not lose entries. When rotation occurs, the system should atomically switch to a new file and preserve the old file.

### Logging Policy

- Console logging should be optional.
- File logging should default on.
- Silent mode suppresses console noise but never suppresses file logging for critical lifecycle events.
- Debug and verbose modes should not alter the meaning of logged events, only their visibility.

## 10. State Management

State is what makes BugHunter-OS resumable and reliable.

### Resume Support

Every run should produce a state manifest with:

- Run identifier.
- Target identity.
- Selected profile.
- Enabled plugins.
- Completed stages.
- Partial outputs.
- Failure markers.

If a scan is interrupted, the next run should detect the prior state and resume from the last safe checkpoint.

### Interrupted Scans

Interruptions may come from:

- User cancellation.
- Host shutdown.
- Network failure.
- Tool crash.
- Dependency failure.

The state manager should distinguish between:

- Clean stops.
- Hard failures.
- Incomplete output.
- Recoverable partial runs.

### Cached Scans

Cache should store reusable intelligence:

- DNS resolution.
- HTTP fingerprints.
- WAF behavior.
- Template results.
- Historical URL sets.
- Asset metadata.

Cache entries should be keyed by target, stage, and content hash where appropriate.

### Progress Tracking

Progress must exist at three levels:

- Run progress.
- Stage progress.
- Plugin progress.

Progress should be recorded in state, not only shown in the terminal.

## 11. Auto Update System

The update system keeps the framework and its external dependencies current without uncontrolled mutation.

### Go Tools

Go-based tools should be updated via:

- Version verification.
- `go install` when appropriate.
- Post-install verification.
- PATH-aware validation.

Updates must be explicit and logged. A failed update should not break the whole run unless the missing tool is required for the selected profile.

### Nuclei Templates

Template updates should:

- Be versioned or timestamped.
- Be cached.
- Support safe refreshes.
- Respect operator-defined update windows.

### Wordlists

Wordlist refresh should:

- Pull approved sources.
- Preserve local modifications.
- Record source and version.

### Project Updates

Project update checks may include:

- Framework version changes.
- Plugin manifest updates.
- Configuration schema changes.

The update manager must never silently alter behavior during a live scan.

## 12. Adaptive Scan Engine

The adaptive scan engine changes runtime posture based on target protection and feedback from scan stages.

### Goals

- Improve success rate on protected targets.
- Avoid unnecessary noise.
- Maintain throughput where safe.
- Prevent hard failures from cascading into run failure.

### Inputs

- WAF fingerprints.
- Response codes and challenge pages.
- Latency and timeout signals.
- Rate-limit responses.
- CDN and edge provider identity.
- Historical run outcomes.

### Adaptive Dimensions

The engine may adjust:

- Threads.
- Concurrency.
- Rate limits.
- Retries.
- Timeouts.
- User agent.
- Request jitter.
- Stage ordering.

### Provider-Aware Strategy

#### Cloudflare

- Start conservatively.
- Increase delays on challenge responses.
- Favor lower concurrency.
- Prefer cached discoveries before active testing.

#### Akamai

- Expect edge normalization and signature-based protection.
- Use moderate retries with caution.
- Reduce burst traffic.

#### Fastly

- Watch for fast edge responses and inconsistent caching.
- Adjust retry and timeout policy if origin behavior differs.

#### Imperva

- Assume aggressive filtering and challenge behavior.
- Slow down immediately on challenge indicators.

#### AWS

- Consider load balancers, API gateways, and WAF-integrated front ends.
- Adjust endpoint probing based on response consistency.

#### Azure

- Watch for application gateways, front-door behavior, and region-based variations.
- Tune scanning to avoid noisy repeated requests.

### Policy

Adaptation should be bounded and explainable. The engine must record why it changed settings and what changed.

## 13. AI Decision Engine

The AI layer is future-facing and should augment, not replace, deterministic scanning.

### Future Scope

- Prioritize targets and findings.
- Correlate related outputs from multiple plugins.
- Score risk and confidence.
- Remove duplicates.
- Suggest next-step validations.
- Assist report drafting.

### Guardrails

- AI must not fabricate findings.
- AI must not override deterministic evidence.
- AI must preserve provenance for every suggestion.
- AI outputs should be reviewable and auditable.

### Human-in-the-Loop Model

The AI engine should provide:

- Ranked recommendations.
- Correlation summaries.
- Confidence annotations.
- Suggested remediation text.

Operators retain authority over what gets reported and what gets escalated.

## 14. Report Engine

The report engine transforms raw scan output into consumable deliverables.

### Output Formats

- HTML.
- Markdown.
- JSON.
- CSV.
- PDF.

### Required Content

- Target identity and scope notes.
- Scan profile and plugin list.
- Timestamps and duration.
- Evidence references.
- Severity summary.
- Finding details.
- Reproduction steps.
- Remediation guidance.
- False-positive notes.

### Screenshots

Screenshots should be tied to findings and run identity. They must be referenced from report records and stored in the evidence structure.

### Evidence

Evidence can include:

- Request and response excerpts.
- Headers.
- Screenshots.
- JS snippets.
- Template matches.
- Port and service metadata.

### Deduplication

The report engine must merge duplicate signals before finalization. The final report should prefer the highest-confidence, best-evidenced version of any issue.

## 15. Dashboard

The dashboard is the operator control surface for live visibility.

### Purpose

- Show scan progress in real time.
- Surface stage completion and current task.
- Provide charts, counts, and timeline information.
- Expose recent findings and evidence quickly.

### Expected Views

- Overview.
- Targets.
- Stage progress.
- Findings.
- Evidence.
- Logs.
- Run history.

### Data Source

The dashboard should read from state and log artifacts rather than parsing ad hoc terminal text.

### Interaction Model

- Live refresh.
- Filter by target and stage.
- Drill-down into evidence.
- Quick access to report export.

## 16. Cloud Mode

Cloud mode is a future distributed execution model for large authorized programs.

### Purpose

- Run scans across fleets or worker pools.
- Distribute long-running tasks.
- Consolidate reporting centrally.
- Support notification and scheduling.

### Components

- Remote scheduler.
- Worker agent.
- Central state store.
- Evidence sync.
- Notification hub.

### Non-Goals for Early Versions

- Cloud mode should not be required for local scanning.
- It should not replace the local CLI.
- It should not reduce auditability.

### Security Requirements

- Strong identity and access control.
- Signed task payloads.
- Encrypted state transport.
- Immutable logs where possible.

## 17. Security Model

Security policy is part of the architecture.

### Safe Mode

Safe mode emphasizes passive or low-impact behavior:

- Lower concurrency.
- Lower rate limits.
- Fewer active plugins.
- More conservative retries.
- Limited evidence generation overhead.

### Passive Mode

Passive mode should avoid active probing that could affect target behavior. It is useful for early discovery and scope validation.

### Active Mode

Active mode enables higher-impact validation plugins. It must remain explicit and profile-bound.

### Confirmation Requirements

The framework should require confirmation or explicit flagging before:

- Running high-impact plugins.
- Increasing scan intensity.
- Exporting sensitive evidence.
- Updating tools in a way that modifies runtime behavior.

### Authorization Enforcement

The architecture assumes authorized use, but it should still enforce:

- Target validation.
- Scope file support.
- Empty target rejection.
- Dangerous wildcard rejection.

## 18. Performance Goals

The system should scale from small targets to large estates without architectural change.

### Memory

- Avoid keeping large raw datasets in memory.
- Stream intermediate outputs to disk.
- Cache only what is reusable.

### CPU

- Use bounded concurrency.
- Avoid busy loops.
- Prefer structured parallelism over uncontrolled background jobs.

### Concurrency

- Concurrency should be stage-aware.
- Rate-sensitive stages should run below aggressive default levels.
- Parallelism should be configurable and capped.

### Scalability

- Support many domains, many subdomains, and many URLs.
- Support repeated scan resumes.
- Support incremental re-runs with cache reuse.

### Large Targets

For large estates, the scheduler should:

- Split work into chunks.
- Cache aggressively.
- Persist checkpoints often.
- Delay expensive active plugins until prioritization.

## 19. Future Roadmap

### v1

The first production release should include:

- CLI orchestration.
- Core config and logging.
- Plugin loading.
- Recon and enumeration pipeline.
- Evidence capture.
- Markdown and JSON reporting.
- Resume support.

### v2

The second release should include:

- Dashboard.
- Advanced adaptive rate limiting.
- Expanded plugin catalog.
- Better report exports.
- Stronger state persistence.
- Distributed execution primitives.

### v3

The third release should include:

- Multi-target campaign management.
- AI-assisted prioritization.
- More mature cache strategies.
- Enterprise policy controls.
- Remote worker orchestration.

### Enterprise Edition

Enterprise Edition should add:

- Multi-user support.
- Role-based access control.
- Shared policy management.
- Central logging.
- Audit retention.
- Approval workflows.

### AI Edition

AI Edition should add:

- Assisted triage.
- Correlation and deduplication.
- Risk summarization.
- Natural language report drafting.
- Findings ranking with provenance.

## 20. Development Rules

All contributors must follow these rules.

### Coding Standards

- Use Bash strict mode in shell code.
- Quote variables and paths.
- Keep functions short and composable.
- Prefer explicit return codes.
- Avoid hidden global side effects.

### ShellCheck

- ShellCheck compliance is mandatory for shell files.
- Any suppression must be justified and localized.
- ShellCheck warnings should be treated as implementation debt unless explicitly accepted.

### Modularity

- Keep orchestration in `core/`.
- Keep reusable support in `utils/`.
- Keep scan behavior in `plugins/`.
- Avoid duplication across modules.

### Logging

- Every stage and plugin must write logs.
- Errors must include context.
- Debug output must be actionable.

### Configuration

- Do not hardcode values that belong in config.
- Keep private data out of the repository.
- Profile-specific values should remain profile-specific.

### Testing

- Add tests for orchestration logic, state handling, and configuration parsing.
- Use fixtures for plugin outputs.
- Treat resume, deduplication, and logging as high-risk areas.

### Git Workflow

- Keep changes scoped.
- Avoid unrelated churn.
- Use small, reviewable commits.
- Preserve architectural consistency across the tree.

## Architecture Principles

The design is guided by a few non-negotiable principles:

- Determinism over improvisation.
- Auditability over convenience.
- Safe defaults over aggressive automation.
- Structured data over fragile text parsing.
- Clear ownership over shared ambiguity.
- Explicit policy over hidden heuristics.

## Operational Summary

In the target architecture, BugHunter-OS should run a campaign as follows:

1. Accept `./bughunter scan target.com`.
2. Validate the target, configuration, and scope.
3. Check dependencies and refresh approved assets.
4. Load the profile, plugin set, and policy.
5. Build a run manifest and state records.
6. Execute recon and enumeration.
7. Fingerprint and prioritize exposed assets.
8. Run targeted discovery and validation plugins.
9. Collect evidence and screenshots.
10. Generate final reports.
11. Preserve everything needed to resume or audit the run later.

## Closing Note

This architecture is intentionally opinionated. BugHunter-OS should feel like a serious execution framework, not a pile of scripts. The right shape is a core engine coordinating a disciplined plugin system with durable state, conservative defaults, and rich evidence output.
