# Contributing

This is a personal learning and interview prep project. External contributions
are not expected, but feedback is welcome via GitHub Issues.

## Setup

1. Install Go 1.24+, Docker, minikube, and Helm 3.
2. Clone the repo and run `go mod download`.
3. Run tests with `go test ./...`.

## Standards

- Format code with `gofmt` before committing.
- All new code should include tests.
- Run `helm lint charts/go-demo` before submitting chart changes.
