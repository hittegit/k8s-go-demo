# Changelog

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
