// cmd/server/tracing.go
//
// OpenTelemetry tracing setup. Exports spans via OTLP/HTTP to a collector,
// configured through the standard OTEL_EXPORTER_OTLP_ENDPOINT environment
// variable (defaults to localhost:4318 when unset).

package main

import (
	"context"
	"errors"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

const serviceName = "k8s-go-demo"

// setupTracing configures a global TracerProvider that exports spans via
// OTLP/HTTP. It returns a shutdown function that flushes and closes the
// exporter; callers must invoke it before the process exits.
func setupTracing(ctx context.Context) (func(context.Context) error, error) {
	// WithInsecure defaults to plain HTTP, matching an in-cluster OTel
	// Collector ClusterIP service with no TLS termination. Setting
	// OTEL_EXPORTER_OTLP_ENDPOINT with an https:// scheme overrides this.
	exporter, err := otlptracehttp.New(ctx, otlptracehttp.WithInsecure())
	if err != nil {
		return nil, err
	}

	res, err := resource.Merge(
		resource.Default(),
		resource.NewWithAttributes(semconv.SchemaURL, semconv.ServiceName(serviceName)),
	)
	if err != nil {
		return nil, err
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)

	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	return func(shutdownCtx context.Context) error {
		return errors.Join(
			tp.ForceFlush(shutdownCtx),
			tp.Shutdown(shutdownCtx),
		)
	}, nil
}
