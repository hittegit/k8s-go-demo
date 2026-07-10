# Dockerfile
#
# Multi-stage build to keep the final image small and secure.
# Stage 1 compiles the binary; Stage 2 runs it on a minimal base.

# ---- Build Stage ----
FROM golang:1.26-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download
COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o bin/server ./cmd/server

# ---- Run Stage ----
FROM scratch

COPY --from=builder /app/bin/server /server

EXPOSE 8080

ENTRYPOINT ["/server"]
