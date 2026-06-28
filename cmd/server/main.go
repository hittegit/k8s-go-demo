// cmd/server/main.go
//
// Entry point for the k8s-go-demo HTTP server.
// Exposes a health endpoint for Kubernetes liveness and readiness probes,
// a root endpoint for smoke testing, and a /metrics endpoint for Prometheus
// scraping, with structured JSON logging to stdout.

package main

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// healthResponse is the JSON payload returned by the /health endpoint.
type healthResponse struct {
	Status string `json:"status"`
}

// httpRequestsTotal counts the total number of HTTP requests handled,
// partitioned by HTTP method and path. Prometheus will scrape this
// counter from the /metrics endpoint.
var httpRequestsTotal = promauto.NewCounterVec(
	prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Total number of HTTP requests handled, by method and path.",
	},
	[]string{"method", "path"},
)

// healthHandler responds with a 200 OK and a JSON body indicating
// the service is healthy. Kubernetes liveness and readiness probes
// will target this endpoint.
func healthHandler(w http.ResponseWriter, r *http.Request) {
	httpRequestsTotal.WithLabelValues(r.Method, "/health").Inc()
	slog.Info("health check", "method", r.Method, "path", r.URL.Path)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	if err := json.NewEncoder(w).Encode(healthResponse{Status: "ok"}); err != nil {
		slog.Error("failed to write health response", "error", err)
	}
}

// rootHandler responds to requests at the root path.
// Useful for quick smoke tests after deployment.
func rootHandler(w http.ResponseWriter, r *http.Request) {
	httpRequestsTotal.WithLabelValues(r.Method, "/").Inc()
	slog.Info("root request", "method", r.Method, "path", r.URL.Path)
	w.WriteHeader(http.StatusOK)
	if _, err := w.Write([]byte("k8s-go-demo is running\n")); err != nil {
		slog.Error("failed to write root response", "error", err)
	}
}

func main() {
	// Use structured logging (slog) to stdout, which is the standard
	// pattern for containerized applications. Log aggregators like
	// Grafana Loki or CloudWatch pick this up cleanly.
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	ctx := context.Background()

	shutdownTracing, err := setupTracing(ctx)
	if err != nil {
		slog.Error("failed to set up tracing", "error", err)
		os.Exit(1)
	}
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := shutdownTracing(shutdownCtx); err != nil {
			slog.Error("failed to shut down tracing", "error", err)
		}
	}()

	// PORT can be overridden via environment variable, making it easy
	// to configure in Kubernetes via a ConfigMap or Deployment env block.
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", rootHandler)
	mux.HandleFunc("/health", healthHandler)

	// /metrics is handled by the Prometheus client library. Kubernetes
	// and Prometheus will scrape this endpoint for runtime metrics.
	mux.Handle("/metrics", promhttp.Handler())

	handler := otelhttp.NewHandler(mux, serviceName)

	server := &http.Server{
		Addr:    ":" + port,
		Handler: handler,
	}

	go func() {
		slog.Info("server starting", "port", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server failed", "error", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	slog.Info("server shutting down")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		slog.Error("graceful shutdown failed", "error", err)
	}
}
