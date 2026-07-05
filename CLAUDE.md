# CLAUDE.md

This file provides context for Claude Code sessions on the k8s-go-demo project.

## Project Overview

A Go HTTP service deployed to Kubernetes via Helm, with OpenTelemetry,
Prometheus, and Grafana observability. Built for local minikube development
and DevOps/SRE interview prep.

## Repository

<https://github.com/hittegit/k8s-go-demo>

## Owner

Erik Hitt - Platform and DevOps Engineer

## Tech Stack

- **Language:** Go 1.25
- **Container:** Docker, multi-stage build, scratch base image
- **Orchestration:** Kubernetes via minikube (local)
- **Packaging:** Helm 3
- **Observability:** Prometheus, Grafana (via kube-prometheus-stack), OpenTelemetry
- **CI:** GitHub Actions
- **Dependency updates:** Renovate
- **Repo hygiene:** Yardstick v0.4.0

## Development Workflow

All changes follow this pipeline:

```text
Issue -> Feature Branch -> Pull Request -> CI -> Merge -> Tag -> Release
```

### Global Safety Rules

1. No direct pushes to `main`
2. Every non-trivial change starts with a GitHub Issue
3. Branch names must include the issue number: `feat/<issue-number>-<short-slug>`
4. All integrations happen via Pull Request (squash merge, delete branch after)
5. Sync remotes before branch or release operations
6. Require explicit confirmation before merge or release tag push

### `/push_code start`

1. Create or confirm a GitHub Issue:

   ```bash
   gh issue create --title "<title>" --body "<body>"
   ```

2. Create and push an issue-numbered branch:

   ```bash
   git checkout -b feat/<issue-number>-<short-slug>
   git push -u origin feat/<issue-number>-<short-slug>
   ```

3. Open a draft PR linked to the issue:

   ```bash
   gh pr create --base main --head feat/<issue-number>-<short-slug> \
     --draft --title "<type>: <summary>" --body "Closes #<issue-number>"
   ```

### `/push_code update`

1. Abort if on `main`.
2. Show working changes (`git status --short`, `git diff --stat`).
3. Propose a Conventional Commit message and wait for explicit approval.
4. Commit and push only after approval.

### `/push_code ready`

Run all validations; hard abort on any failure:

```bash
go test -race ./...
go vet ./...
gofmt -l ./cmd/server
markdownlint '*.md'
yamllint .github/workflows/*.yml .markdownlint.yaml .yamllint.yaml monitoring/*.yaml charts/go-demo/values.yaml
helm lint charts/go-demo
```

If all pass, mark the PR ready for review:

```bash
gh pr ready
```

### `/push_code merge`

Confirmation gate - type `YES` to continue, otherwise abort.

1. Verify all PR checks are green:

   ```bash
   gh pr checks
   ```

2. Squash merge and delete branch:

   ```bash
   gh pr merge --squash --delete-branch
   ```

### `/push_code release`

Confirmation gate - type `YES` to continue, otherwise abort.

1. Update local `main`:

   ```bash
   git checkout main
   git pull --ff-only
   ```

2. Select next version (`vX.Y.Z`) based on merged scope (patch/minor/major).

3. Create and push an annotated tag:

   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin vX.Y.Z
   ```

4. Create the GitHub release (no release.yml workflow yet - manual step):

   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z" --notes "<release notes>"
   ```

5. Update CHANGELOG.md: promote `[Unreleased]` to the new version and date.

---

## Project Structure

```text
k8s-go-demo/
  cmd/
    server/
      main.go         - HTTP server, /health, /, /metrics endpoints
      main_test.go    - Unit tests using net/http/httptest
  charts/
    go-demo/
      Chart.yaml
      values.yaml
      dashboards/
        go-demo.json    - Grafana dashboard, provisioned via ConfigMap
      templates/
        deployment.yaml
        service.yaml
        servicemonitor.yaml          - Prometheus Operator scrape config
        grafana-dashboard-configmap.yaml
        _helpers.tpl
        NOTES.txt
  monitoring/
    kube-prometheus-stack-values.yaml - Prometheus + Grafana, sized for minikube
    otel-collector-values.yaml        - OTel Collector, forwards traces to Tempo
    tempo-values.yaml                 - Tempo (single-binary), sized for minikube
  .github/
    workflows/
      ci.yml          - Lint, vet, test, build, Docker build, Helm lint,
                        govulncheck, yardstick, syft SBOM
  scripts/
    demo-setup.sh   - brings up the full demo environment (minikube, Helm, port-forwards)
  Dockerfile
  go.mod
  go.sum
  CLAUDE.md
```

## Local Development

```bash
# Run server locally
go run ./cmd/server

# Run tests
go test ./...

# Build Docker image
docker build -t k8s-go-demo:local .

# Load image into minikube
minikube image load k8s-go-demo:local

# Deploy via Helm (requires kube-prometheus-stack installed first,
# see Observability below, or pass --set serviceMonitor.enabled=false
# --set grafanaDashboard.enabled=false)
helm install go-demo charts/go-demo --namespace demo --create-namespace

# Port forward and test
kubectl port-forward svc/go-demo 8080:8080 -n demo &
curl http://localhost:8080/health
curl http://localhost:8080/metrics

# Teardown
helm uninstall go-demo -n demo
```

## Observability Stack

```bash
# One-time: install Prometheus + Grafana via kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f monitoring/kube-prometheus-stack-values.yaml

# Grafana (admin/admin by default, see values file)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# One-time: install Tempo + OTel Collector for traces
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
helm install tempo grafana/tempo \
  --namespace monitoring --create-namespace \
  -f monitoring/tempo-values.yaml
helm install otel-collector open-telemetry/opentelemetry-collector \
  --namespace monitoring --create-namespace \
  -f monitoring/otel-collector-values.yaml

# go-demo's OTEL_EXPORTER_OTLP_ENDPOINT (values.yaml otel.endpoint)
# points at the in-cluster collector by default. Query traces directly:
kubectl port-forward -n monitoring svc/tempo 3200:3200
curl "http://localhost:3200/api/search?tags=service.name%3Dk8s-go-demo"
```

**Pitfall:** `minikube image load <tag>` is a no-op if a running container
already holds a reference to the old image under that tag. Scale the
deployment to 0 first, reload the image, then scale back up:

```bash
kubectl scale deployment go-demo -n demo --replicas=0
minikube image rm k8s-go-demo:local
minikube image load k8s-go-demo:local
kubectl scale deployment go-demo -n demo --replicas=1
```

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

## Local Validation

Run before committing or opening a PR:

```bash
go test -race ./...
go vet ./...
gofmt -l ./cmd/server
markdownlint '*.md'
yamllint .github/workflows/*.yml .markdownlint.yaml .yamllint.yaml monitoring/*.yaml charts/go-demo/values.yaml
helm lint charts/go-demo
```

## Coding Standards

- Format all Go code with gofmt before committing.
- All new handlers must increment httpRequestsTotal counter.
- All new endpoints must be covered by tests in main_test.go.
- No em dashes in any output or comments, use commas or hyphens.
- Follow markdownlint rules in all Markdown files.
- Follow yamllint rules (configured in .yamllint.yaml) in all YAML files.
- Never include git commit or git push commands unless explicitly asked.

## Upcoming Work

- Add GitHub Actions CD workflow
