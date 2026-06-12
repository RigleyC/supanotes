# ---- Build stage ----
FROM golang:1.25-alpine AS builder

WORKDIR /app

COPY go.mod ./
RUN go mod download

COPY . .
COPY db/migrations ./db/migrations

RUN CGO_ENABLED=0 GOOS=linux go build -o supanotes-server ./cmd/server

# ---- Run stage ----
FROM alpine:3.20

WORKDIR /app

COPY --from=builder /app/supanotes-server .
COPY --from=builder /app/db/migrations ./db/migrations

EXPOSE 8080

ENTRYPOINT ["./supanotes-server"]
