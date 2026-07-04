// cmd/server/main_test.go
//
// Unit tests for the k8s-go-demo HTTP server handlers.
// Uses only the standard library net/http/httptest package.

package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/prometheus/client_golang/prometheus/testutil"
)

// TestHealthHandler verifies the /health endpoint returns 200 OK
// and a valid JSON body with status "ok".
func TestHealthHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()

	healthHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", rec.Code)
	}

	var body healthResponse
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}

	if body.Status != "ok" {
		t.Errorf("expected status 'ok', got '%s'", body.Status)
	}
}

// TestRootHandler verifies the root endpoint returns 200 OK
// and a non-empty body.
func TestRootHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()

	rootHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", rec.Code)
	}

	if rec.Body.Len() == 0 {
		t.Error("expected non-empty response body")
	}
}

// TestHealthHandlerContentType verifies the /health endpoint
// returns the correct Content-Type header.
func TestHealthHandlerContentType(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()

	healthHandler(rec, req)

	ct := rec.Header().Get("Content-Type")
	if ct != "application/json" {
		t.Errorf("expected Content-Type 'application/json', got '%s'", ct)
	}
}

// TestRootHandlerBody verifies the root handler returns the exact expected text.
func TestRootHandlerBody(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()

	rootHandler(rec, req)

	got := rec.Body.String()
	want := "k8s-go-demo is running\n"
	if got != want {
		t.Errorf("body = %q, want %q", got, want)
	}
}

// TestHealthHandlerIncrementsCounter verifies that /health increments
// the http_requests_total Prometheus counter on each call.
func TestHealthHandlerIncrementsCounter(t *testing.T) {
	before := testutil.ToFloat64(httpRequestsTotal.WithLabelValues("GET", "/health"))

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	healthHandler(httptest.NewRecorder(), req)

	after := testutil.ToFloat64(httpRequestsTotal.WithLabelValues("GET", "/health"))
	if after-before != 1 {
		t.Errorf("counter delta = %v, want 1", after-before)
	}
}

// TestRootHandlerIncrementsCounter verifies that / increments
// the http_requests_total Prometheus counter on each call.
func TestRootHandlerIncrementsCounter(t *testing.T) {
	before := testutil.ToFloat64(httpRequestsTotal.WithLabelValues("GET", "/"))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rootHandler(httptest.NewRecorder(), req)

	after := testutil.ToFloat64(httpRequestsTotal.WithLabelValues("GET", "/"))
	if after-before != 1 {
		t.Errorf("counter delta = %v, want 1", after-before)
	}
}
