# Testing

This document explains how to test k8s-go-demo at every layer, from
fast automated unit tests to verifying the full observability stack in a
live cluster.

---

## Unit Tests

The fastest feedback loop. These tests check that each HTTP handler returns
the right status code, response body, and headers, and that the Prometheus
counter increments on every call. No live server, Docker, or cluster is
needed -- Go simulates HTTP calls in memory.

**Run all tests:**

    go test ./...

**Run with the race detector** (catches bugs that only appear under
concurrent load -- good practice before pushing):

    go test -race ./...

**Run a single test by name:**

    go test -run TestHealthHandler ./cmd/server

If all tests pass, the output ends with `ok`. If one fails, it shows
exactly what was expected and what the handler actually returned.

**What each test checks:**

| Test | What it verifies |
| ------ | ----------------- |
| `TestHealthHandler` | `/health` returns HTTP 200 and JSON body `{"status":"ok"}` |
| `TestHealthHandlerContentType` | `/health` sets `Content-Type: application/json` |
| `TestRootHandler` | `/` returns HTTP 200 and a non-empty body |
| `TestRootHandlerBody` | `/` returns the exact text `k8s-go-demo is running` |
| `TestHealthHandlerIncrementsCounter` | Calling `/health` adds 1 to the Prometheus request counter |
| `TestRootHandlerIncrementsCounter` | Calling `/` adds 1 to the Prometheus request counter |

---

## Manual Testing -- Local Server

Runs the Go server directly on your machine, no Docker or Kubernetes
involved. Good for a quick sanity check while making code changes.

**Start the server:**

    go run ./cmd/server

**In a second terminal, hit each endpoint:**

    # Smoke test -- should print: k8s-go-demo is running
    curl http://localhost:8080/

    # Health check -- should print: {"status":"ok"}
    curl http://localhost:8080/health

    # Prometheus metrics -- prints a page of metric names and values
    curl http://localhost:8080/metrics | head -20

Press `Ctrl+C` in the first terminal to stop the server.

---

## Container Testing

Builds and runs the Docker image locally. Catches problems that only show
up inside the container, such as missing files or an incorrect binary path.

**Build the image:**

    docker build -t k8s-go-demo:local .

**Run the container:**

    docker run --rm -p 8080:8080 k8s-go-demo:local

**Test the same endpoints** in a second terminal:

    curl http://localhost:8080/health

The `--rm` flag removes the container automatically when you stop it with
`Ctrl+C`. You should see the server start message in the first terminal
and a clean JSON response in the second.

---

## Kubernetes Testing

Deploys the service to a local minikube cluster and verifies it runs as
a real Kubernetes workload with liveness and readiness probes.

**Prerequisites:** minikube is running (`minikube status`).

**Build, load, and deploy:**

    docker build -t k8s-go-demo:local .
    minikube image load k8s-go-demo:local
    helm install go-demo charts/go-demo --namespace demo --create-namespace \
      --set serviceMonitor.enabled=false \
      --set grafanaDashboard.enabled=false

> Drop the `--set` flags if you have the full monitoring stack installed.

**Check the pod is running:**

    kubectl get pods -n demo

The pod should reach `Running` status with `1/1` under READY within a
few seconds.

**Port-forward and test:**

    kubectl port-forward svc/go-demo 8080:8080 -n demo &
    curl http://localhost:8080/health

**Verify liveness and readiness probes are passing:**

    kubectl describe pod -n demo -l app.kubernetes.io/name=go-demo

Under `Conditions:`, both `Ready` and `ContainersReady` should say `True`.
Kubernetes uses the `/health` endpoint for these probes -- if they fail,
the pod gets restarted.

**Tear down:**

    helm uninstall go-demo -n demo
    kill %1    # stops the port-forward

---

## Observability Testing

Verifies that metrics, dashboards, and traces are working end to end.
Requires the full monitoring stack (kube-prometheus-stack, Tempo, and
the OTel Collector) to be installed.

### Prometheus -- Is It Scraping the Service?

**Port-forward to Prometheus:**

    kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

**Open `http://localhost:9090` in a browser.**

- Go to **Status > Targets** and find the `go-demo` job. The State column
  should say **UP** in green. If it says DOWN, wait 30 seconds and refresh
  -- Prometheus polls on a 30-second interval.

- Go to the **Graph** tab and run this query to see raw counter values:

      http_requests_total{job="go-demo"}

  Generate some traffic first if the result is empty:

      for i in $(seq 1 5); do curl -s http://localhost:8080/health; done

  You should see entries for each combination of HTTP method and path.

### Grafana Dashboard -- Are the Panels Showing Data?

**Port-forward to Grafana (if not already running):**

    kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

**Open `http://localhost:3000` and log in** with `admin` / `admin`.

- Go to **Dashboards > Browse** and open the **go-demo** dashboard. If it
  is not listed, wait up to a minute for the Grafana sidecar to discover
  the ConfigMap, then refresh.

- Generate traffic and watch the panels update:

            for i in $(seq 1 20); do
                curl -s http://localhost:8080/health >/dev/null
            done

  The **HTTP Request Rate** panel should show activity during the burst.
  **Total Requests** should increment. **Goroutines** and **Resident Memory**
  reflect the Go runtime's internal state and update independently of traffic.

- While in Grafana, browse to **Dashboards > Browse** and also check the
  built-in Kubernetes dashboards that come with kube-prometheus-stack:
  - **Kubernetes / Compute Resources / Cluster** -- CPU and memory across
    all namespaces; look for the `demo` row.
  - **Kubernetes / Compute Resources / Namespace (Pods)** -- filter to
    the `demo` namespace to see go-demo's pod-level resource usage.
  - **Node Exporter / Nodes** -- host-level CPU, memory, disk, and network
    for the minikube node.

### Traces -- Are Spans Reaching Tempo?

**Generate a couple of fresh requests:**

    curl http://localhost:8080/
    curl http://localhost:8080/health

**In Grafana**, go to **Explore**, select **Tempo** from the datasource
dropdown, click the **Search** tab, set `service.name = k8s-go-demo`,
and click **Run query**. A trace should appear within a few seconds. Click
it to see the span name (for example `GET /health`) and its duration.

**Fallback -- query Tempo directly:**

    kubectl port-forward -n monitoring svc/tempo 3200:3200 &
    curl "http://localhost:3200/api/search?tags=service.name%3Dk8s-go-demo&limit=5"

A JSON response containing `"traces":[{...}]` confirms spans are arriving.
An empty `"traces":[]` means either no traffic has been sent recently or
the pipeline is not running.

**Confirm the collector is forwarding spans:**

    kubectl logs -n monitoring -l app.kubernetes.io/instance=otel-collector --tail=20

Lines mentioning `TracesExporter` with a non-zero span count confirm the
OTel Collector is receiving spans from the app and forwarding them to Tempo.

---

## CI Pipeline

Every push and pull request automatically runs all of the above code-level
checks via GitHub Actions. You do not need to run these manually -- they
run in the cloud on every change.

| Job | What it checks |
| ----- | --------------- |
| `lint-and-vet` | `golangci-lint`, `gofmt`, `go vet` -- code style and static analysis |
| `test` | `go test -race ./...` -- all unit tests with the race detector enabled |
| `vulnerability-scan` | `govulncheck` -- known CVEs in Go dependencies |
| `build` | `go build` and `docker build` -- binary and container build succeed |
| `helm-lint` | `helm lint` -- Helm chart templates are valid |
| `repo-hygiene` | `yardstick` -- repo structure and best-practice checks |
| `sbom` | `syft` -- generates a CycloneDX software bill of materials |

A green check mark on a pull request means all seven jobs passed. The CI
badge at the top of the README reflects the latest run on the `main` branch.
