# BugHunter-OS

BugHunter-OS is a modular Bash-based framework for authorized bug bounty and web application security testing. It is designed to coordinate recon, crawling, asset discovery, vulnerability checks, evidence collection, and reporting from one predictable workspace.

This repository is being built file by file. The current README defines the production target, operating rules, directory contract, and expected module responsibilities before implementation begins.

## Legal Use

Use BugHunter-OS only against systems you own or have explicit written permission to test. You are responsible for following program scope, rate limits, data handling rules, and local law. The framework should default to conservative behavior, avoid destructive payloads, and keep enough logs to support auditability.

## Goals

- Provide a single command-line workflow for authorized web security testing.
- Keep modules small, composable, and easy to audit.
- Store all generated data in predictable `output/`, `logs/`, `screenshots/`, and `reports/` paths.
- Support repeatable scans through a central configuration file.
- Prefer proven external tools while keeping framework glue simple and inspectable.
- Produce professional reports with findings, evidence, affected assets, severity, and reproduction notes.

## Non-Goals

- This project is not malware, an exploit pack, or an evasion framework.
- This project should not include destructive exploitation by default.
- This project should not bypass authorization, authentication, rate limits, or access controls outside a valid test scope.
- This project should not hide activity from target owners or monitoring systems.

## Repository Layout

```text
BugHunter-OS/
├── bughunter.sh              # Main CLI entrypoint
├── config/
│   └── config.conf           # Runtime configuration and defaults
├── install/
│   └── install.sh            # Dependency installation and environment checks
├── logs/                     # Runtime logs
├── modules/                  # Independent scan and reporting modules
│   ├── api.sh                # API discovery and checks
│   ├── gau.sh                # Historical URL collection
│   ├── httpx.sh              # HTTP probing and enrichment
│   ├── idor.sh               # IDOR-oriented checks
│   ├── js.sh                 # JavaScript discovery and analysis
│   ├── katana.sh             # Crawling
│   ├── lfi.sh                # Local file inclusion checks
│   ├── nuclei.sh             # Template-based vulnerability scanning
│   ├── openredirect.sh       # Open redirect checks
│   ├── recon.sh              # Target normalization and recon orchestration
│   ├── report.sh             # Report generation
│   ├── secrets.sh            # Secret exposure checks
│   ├── sqli.sh               # SQL injection checks
│   ├── ssrf.sh               # SSRF checks
│   ├── wordpress.sh          # WordPress checks
│   └── xss.sh                # Cross-site scripting checks
├── output/                   # Raw and normalized scan output
├── reports/                  # Human-readable reports
├── screenshots/              # Evidence screenshots
├── templates/                # Custom scanner/report templates
├── utils/                    # Shared helper functions
└── wordlists/                # Project wordlists and payload lists
```

## Expected Workflow

The production CLI should support a workflow similar to:

```bash
./install/install.sh
./bughunter.sh --target example.com --profile safe
./bughunter.sh --target example.com --modules recon,httpx,katana,nuclei
./bughunter.sh --target example.com --report
```

Target input should support domains, URLs, and scoped target files. Every scan should create a run directory under `output/` and write a matching log under `logs/`.

## Module Contract

Each module should:

- Be executable as a standalone Bash file.
- Accept normalized input from the main CLI.
- Read shared settings from `config/config.conf`.
- Write machine-readable output where practical.
- Write human-readable status to logs.
- Fail clearly with actionable errors.
- Avoid modifying files outside the project workspace.
- Respect configured rate limits, timeouts, and scan profiles.

## Configuration Contract

`config/config.conf` should become the single source of truth for:

- Default scan profile.
- Output and report directories.
- Tool paths.
- Thread and rate-limit values.
- Timeout values.
- User agent.
- Nuclei template paths.
- Wordlist paths.
- Screenshot settings.
- Safe-mode behavior.

Secrets and private API tokens should not be committed to this repository. Use environment variables or a local ignored file for sensitive values.

## Scan Profiles

Production builds should support at least these profiles:

- `safe`: passive and low-impact checks for broad use.
- `balanced`: controlled active checks suitable for most bug bounty scopes.
- `deep`: slower, more comprehensive checks requiring explicit user selection.

The default should be `safe`.

## Dependencies

BugHunter-OS is expected to integrate with common security tools where available:

- `subfinder` or equivalent asset discovery tooling.
- `httpx` for HTTP probing.
- `katana` for crawling.
- `gau` or equivalent historical URL collection.
- `nuclei` for template-based checks.
- `jq` for JSON processing.
- `curl` for HTTP requests.
- `gowitness` or another screenshot tool where configured.

The installer should verify dependencies, print missing tools, and avoid silently changing the user's shell environment.

## Output Standards

Generated output should be grouped by target and scan timestamp:

```text
output/<target>/<run-id>/
├── raw/
├── normalized/
├── findings/
└── metadata.json
```

Reports should include:

- Target and authorization scope.
- Scan profile and modules used.
- Start and end timestamps.
- Tool versions where available.
- Findings grouped by severity.
- Evidence paths.
- Reproduction steps.
- Remediation guidance.
- False-positive notes.

## Safety Defaults

The framework should:

- Require explicit target input.
- Refuse empty or wildcard target values.
- Avoid destructive payloads.
- Rate-limit active checks.
- Keep active modules opt-in when risk is higher.
- Record the selected profile and module list for every run.
- Make it easy to stop a scan cleanly.

## Development Standards

- Use Bash with strict mode where practical.
- Quote variables and paths.
- Validate all user input.
- Keep shared helpers in `utils/`.
- Keep module-specific logic inside `modules/`.
- Prefer structured output over parsing terminal text.
- Keep dependency checks separate from scan execution.
- Add tests or dry-run modes for high-risk orchestration behavior.

## Current Status

Initial scaffold exists, but implementation files are currently placeholders. The next step is to implement the framework one file at a time, starting with the main CLI or shared configuration after approval.

## License

License has not been selected yet. Add a license before distributing or accepting external contributions.
