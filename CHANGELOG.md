# Changelog

## [1.0.2] - 2026-07-10

### Fixed

- Replaced `anchore/sbom-action/download-syft` JavaScript action with a
  direct `curl` install of the syft binary, eliminating the Node 20
  deprecation warning
- Switched syft flags from `--name`/`--version` (removed in v1.x) to
  `--source-name`/`--source-version`

### Added

- yamllint and markdownlint steps added to the `lint-and-vet` CI job,
  enforcing YAML and Markdown linting in every push and pull request

## [1.0.1] - 2026-07-09

### Fixed

- Removed `file_format: yaml` from `monitoring/otel-collector-values.yaml`;
  opentelemetry-collector chart v0.162.0 added strict JSON Schema validation
  that rejects the field as an unknown top-level property
- Upgraded Go toolchain to 1.26.5 and updated all Go module dependencies;
  resolves CVE GO-2026-5856 (ECH privacy leak in `crypto/tls`)

## [1.0.0] - 2026-07-05

### Added

- GitHub Actions CD workflow (`cd.yml`): triggers on version tags, builds and
  pushes the Docker image to GHCR (tagged with semver version and `latest`),
  and creates the GitHub Release with auto-generated notes
- `scripts/demo-setup.sh`: idempotent script that starts minikube, installs
  all Helm releases, builds and loads the Docker image, and starts port-forwards
- `scripts/demo-teardown.sh`: companion teardown script with `--delete-cluster`
  flag to stop or wipe the minikube environment

### Fixed

- Tempo OOMKill (`exit 137`): increased memory limit from 256Mi to 1Gi,
  resolving a CrashLoopBackOff caused by WAL block compaction at startup
- README and CLAUDE.md updated to reflect complete CI/CD loop; push_code
  release workflow updated to reflect automated release creation via CD

## [0.3.0] - 2026-07-02

### Added

- OpenTelemetry Collector, receiving OTLP traces from go-demo and
  forwarding them to Grafana Tempo
- Grafana Tempo (single-binary mode), wired into Grafana as a datasource
  so traces are queryable in the same UI as Prometheus metrics
- `OTEL_EXPORTER_OTLP_ENDPOINT` env var on the go-demo Deployment,
  pointing at the in-cluster collector by default
- `TESTING.md`: end-to-end testing guide covering unit tests, local
  server, container, Kubernetes, and full observability stack verification
- `.yamllint.yaml`: yamllint configuration with project-appropriate rules
  (no document-start requirement, 120-char line limit, GitHub Actions
  `on:` key allowed)
- Unit tests for exact root handler response body and Prometheus counter
  increments per handler, enforcing the coding standard that every
  handler must increment `httpRequestsTotal`

### Fixed

- README project structure section now accurately reflects the codebase,
  including `tracing.go`, `monitoring/`, and `charts/go-demo/dashboards/`
- README Helm Chart section now correctly describes the `ServiceMonitor`
  and Grafana dashboard `ConfigMap` resources and their opt-in flags
- `ci.yml` indentation normalized to consistent 2-space throughout;
  trailing spaces removed
- `markdownlint` configuration now exempts tables and code blocks from
  the 80-character line-length rule

## [0.2.0] - 2026-06-28

### Added

- Prometheus and Grafana via the kube-prometheus-stack Helm chart, installed
  into a dedicated `monitoring` namespace
- `ServiceMonitor` in the go-demo chart for Prometheus Operator scrape
  discovery
- Grafana dashboard for go-demo, auto-provisioned via a labeled ConfigMap

### Fixed

- Chart.yaml's leftover `helm create` placeholder `appVersion` (was
  `1.16.0`, unrelated to this project)

## [0.1.0] - 2026-06-28

### Added

- Initial Go HTTP server with `/health` and `/` endpoints
- Prometheus metrics exposed at `/metrics`
- OpenTelemetry tracing instrumentation, exporting spans via OTLP/HTTP with
  graceful shutdown on SIGTERM/SIGINT
- Multi-stage Docker build
- Helm chart for Kubernetes deployment
- GitHub Actions CI pipeline: lint, vet, test, vulnerability scan, build,
  Helm lint, repo hygiene, SBOM generation

### Fixed

- Unchecked error return from the root handler's response write
- Stdlib and OpenTelemetry exporter CVEs by bumping to Go 1.25
- Dockerfile build failure caused by copying a non-existent vendor
  directory
- Server crash on startup caused by a semconv schema URL mismatch between
  the tracing setup and the OpenTelemetry SDK's default resource
