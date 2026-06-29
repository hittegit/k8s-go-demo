# k8s-go-demo

![CI](https://github.com/hittegit/k8s-go-demo/actions/workflows/ci.yml/badge.svg)
![CD](https://github.com/hittegit/k8s-go-demo/actions/workflows/cd.yml/badge.svg)

A Go HTTP service deployed to Kubernetes via Helm, with OpenTelemetry,
Prometheus, and Grafana observability.

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
  - [Run Locally](#run-locally)
  - [Build Docker Image](#build-docker-image)
  - [Deploy to Minikube](#deploy-to-minikube)
- [Helm Chart](#helm-chart)
- [Observability](#observability)
- [CI/CD Pipeline](#cicd-pipeline)
- [Testing](#testing)
- [Contributing](#contributing)

---

## Overview

This project demonstrates a production-style Kubernetes deployment workflow
using a minimal Go HTTP service as the application under deployment. It covers:

- Multi-stage Docker builds
- Helm chart authoring and deployment
- Kubernetes liveness and readiness probes
- Prometheus metrics scraping
- Grafana dashboards
- OpenTelemetry instrumentation
- GitHub Actions CI/CD pipelines

---

## Prerequisites

- [Go 1.25+](https://go.dev/dl/)
- [Docker](https://docs.docker.com/get-docker/)
- [minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm 3](https://helm.sh/docs/intro/install/)

---

## Project Structure

    k8s-go-demo/
      cmd/
        server/
          main.go         - HTTP server entry point
          main_test.go    - Unit tests
      charts/
        go-demo/
          Chart.yaml      - Helm chart metadata
          values.yaml     - Default chart values
          templates/      - Kubernetes manifest templates
      Dockerfile          - Multi-stage container build
      README.md

---

## Getting Started

### Run Locally

    go run ./cmd/server
    curl http://localhost:8080/health

### Build Docker Image

    docker build -t k8s-go-demo:local .
    docker run --rm -p 8080:8080 k8s-go-demo:local

### Deploy to Minikube

    minikube start --driver=docker --cpus=4 --memory=8192
    minikube image load k8s-go-demo:local
    helm install go-demo ./charts/go-demo --namespace demo --create-namespace
    kubectl get pods -n demo

---

## Helm Chart

The Helm chart lives in `charts/go-demo/` and manages the following
Kubernetes resources:

- `Deployment` - runs the Go service with configurable replicas
- `Service` - exposes the deployment within the cluster
- `ConfigMap` - injects environment configuration
- `Ingress` - routes external traffic (optional)

**Common Helm commands:**

    helm lint ./charts/go-demo
    helm install go-demo ./charts/go-demo --namespace demo --create-namespace
    helm upgrade go-demo ./charts/go-demo
    helm rollback go-demo 1
    helm uninstall go-demo -n demo

---

## Observability

Observability is implemented via three complementary tools:

- **OpenTelemetry** - instruments the Go service for traces and metrics
- **Prometheus** - scrapes and stores metrics exposed at `/metrics`
- **Grafana** - visualizes Prometheus metrics via dashboards

Prometheus and Grafana run in the cluster via the
[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
Helm chart, installed into a dedicated `monitoring` namespace:

    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    helm install kube-prometheus-stack \
      prometheus-community/kube-prometheus-stack \
      --namespace monitoring --create-namespace \
      -f monitoring/kube-prometheus-stack-values.yaml

The `go-demo` chart includes a `ServiceMonitor` (so Prometheus Operator
discovers and scrapes the `/metrics` endpoint) and a Grafana dashboard
ConfigMap (auto-discovered by the Grafana sidecar via the
`grafana_dashboard: "1"` label). Both are enabled by default and require
the monitoring stack above to already be installed; disable them with
`--set serviceMonitor.enabled=false --set grafanaDashboard.enabled=false`
when installing go-demo into a cluster without it.

**Access Grafana:**

    kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
    # http://localhost:3000, default login admin/admin (see values file)

**Access Prometheus:**

    kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
    # http://localhost:9090

---

## Testing

    go test ./...

Tests use only the standard library `net/http/httptest` package and cover:

- `/health` endpoint status code and JSON body
- `/health` Content-Type header
- `/` root endpoint status code and body

---

## CI/CD Pipeline

Pipelines are defined in `.github/workflows/` and run on every push and
pull request.

| Workflow | Trigger  | Steps                                       |
|----------|----------|---------------------------------------------|
| `ci.yml` | Push, PR | Lint, vet, test, build, Docker, Helm lint   |

> Pipeline status badges are shown at the top of this README. They will
> activate once the workflow files are committed and a pipeline run completes.

## License

MIT

## Contributing

This is a personal learning project. Contributions are
not expected, but feedback is welcome via GitHub Issues.

## Installation

See [Getting Started](#getting-started) for setup instructions.

## Usage

See [Getting Started](#getting-started) for usage examples.
