# Build the manager binary for multiple architectures
FROM --platform=$BUILDPLATFORM golang:1.24 AS builder
WORKDIR /workspace

# Copy Go Modules manifests
COPY go.mod go.sum ./
RUN go mod download

# Copy the go source
COPY main.go ./
COPY cmd/ cmd/
COPY pkg/ pkg/

# Build for the target platform
ARG TARGETPLATFORM
RUN CGO_ENABLED=0 GOOS=linux GOARCH=$(echo $TARGETPLATFORM | cut -d '/' -f2) GO111MODULE=on go build -a -v -o manager main.go

# Final image
FROM registry.access.redhat.com/ubi8/ubi-minimal:latest
ENV OPERATOR=/usr/local/bin/infra3 \
    USER_UID=1001 \
    USER_NAME=infra3 \
    HOME=/home/infra3

# Install operator binary
COPY --from=builder /workspace/manager ${OPERATOR}
COPY build/bin /usr/local/bin
RUN /usr/local/bin/user_setup

ENTRYPOINT ["/usr/local/bin/entrypoint"]
USER ${USER_UID}
LABEL org.opencontainers.image.source=https://github.com/galleybytes/infrakube