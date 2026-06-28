# CLAUDE.md

This file provides context for Claude Code sessions on the k8s-go-demo project.

## Project Overview

A Go HTTP service deployed to Kubernetes via Helm, with OpenTelemetry,
Prometheus, and Grafana observability. Built for local minikube development
and DevOps/SRE interview prep.

## Repository

<https://github.com/hittegit/k8s-go-demo>

## Owner

Erik Hitt - Platform and DevOps Engineer, Barrios Technology, NASA FOD, Houston TX.

## Tech Stack

- **Language:** Go 1.25
- **Container:** Docker, multi-stage build, scratch base image
- **Orchestration:** Kubernetes via minikube (local)
- **Packaging:** Helm 3
- **Observability:** Prometheus, Grafana, OpenTelemetry (in progress)
- **CI:** GitHub Actions
- **Dependency updates:** Renovate
- **Repo hygiene:** Yardstick v0.4.0

## Project Structure

    k8s-go-demo/
      cmd/
        server/
          main.go         - HTTP server, /health, /, /metrics endpoints
          main_test.go    - Unit tests using net/http/httptest
      charts/
        go-demo/
          Chart.yaml
          values.yaml
          templates/
            deployment.yaml
            service.yaml
            _helpers.tpl
            NOTES.txt
      .github/
        workflows/
          ci.yml          - Lint, vet, test, build, Docker build, Helm lint,
                            govulncheck, yardstick, syft SBOM
      Dockerfile
      go.mod
      go.sum
      CLAUDE.md

## Local Development

    # Run server locally
    go run ./cmd/server

    # Run tests
    go test ./...

    # Build Docker image
    docker build -t k8s-go-demo:local .

    # Load image into minikube
    minikube image load k8s-go-demo:local

    # Deploy via Helm
    helm install go-demo charts/go-demo --namespace demo --create-namespace

    # Port forward and test
    kubectl port-forward svc/go-demo 8080:8080 -n demo &
    curl http://localhost:8080/health
    curl http://localhost:8080/metrics

    # Teardown
    helm uninstall go-demo -n demo

## Key Endpoints

- `GET /` - smoke test, returns plain text
- `GET /health` - liveness and readiness probe target, returns JSON
- `GET /metrics` - Prometheus scrape target

## Environment Variables

- `PORT` - server listen port, defaults to 8080

## CI Pipeline Jobs

- lint-and-vet - golangci-lint, gofmt, go vet
- test - go test with race detector and coverage
- vulnerability-scan - govulncheck
- build - go build and Docker build
- helm-lint - helm lint
- repo-hygiene - yardstick v0.4.0 strict mode
- sbom - syft CycloneDX SBOM generation

## Coding Standards

- Format all Go code with gofmt before committing.
- All new handlers must increment httpRequestsTotal counter.
- All new endpoints must be covered by tests in main_test.go.
- No em dashes in any output or comments, use commas or hyphens.
- Follow markdownlint rules in all Markdown files.
- Never include git commit or git push commands unless explicitly asked.

## Upcoming Work

- Complete OpenTelemetry tracing instrumentation
- Install Prometheus and Grafana via Helm into minikube
- Wire Grafana dashboards to Prometheus datasource
- Add GitHub Actions CD workflow
