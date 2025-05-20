ARG TF_IMAGE=1.0.0

# Select Terraform base dynamically
FROM hashicorp/terraform:${TF_IMAGE} AS terraform_amd64
RUN cp /bin/terraform /usr/local/bin 
FROM ghcr.io/galleybytes/terraform-arm64:${TF_IMAGE} AS terraform_arm64

FROM docker.io/library/debian AS base
COPY --from=terraform_amd64 /usr/local/bin/terraform /usr/local/bin/terraform-amd64
COPY --from=terraform_arm64 /usr/local/bin/terraform /usr/local/bin/terraform-arm64
RUN ARCH="$(echo $TARGETPLATFORM | cut -d '/' -f2)" &&\
 if [ "$ARCH" == "amd64" ];\
 then mv /usr/local/bin/terraform-amd64 /usr/local/bin/terraform;\
 else mv /usr/local/bin/terraform-arm64 /usr/local/bin/terraform;\
 fi


# Base image for tool dependencies
RUN apt update -y && apt install curl wget -y

# Kubernetes CLI installation
FROM base AS k8s
ARG TARGETPLATFORM
RUN export ARCH=$(echo $TARGETPLATFORM | cut -d '/' -f2) 
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$(echo $TARGETPLATFORM | cut -d '/' -f2)/kubectl"
RUN curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$(echo $TARGETPLATFORM | cut -d '/' -f2)/kubectl.sha256"
RUN echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
RUN install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# IRSA Token Generator
FROM base AS irsa-tokengen
ARG TARGETPLATFORM
WORKDIR /workdir
RUN mkdir bin
RUN wget "https://github.com/isaaguilar/irsa-tokengen/releases/download/v1.0.0/irsa-tokengen-v1.0.0-linux-$(echo $TARGETPLATFORM | cut -d '/' -f2).tgz" 
RUN tar xzf "irsa-tokengen-v1.0.0-linux-$(echo $TARGETPLATFORM | cut -d '/' -f2).tgz" && mv irsa-tokengen bin/irsa-tokengen

# Compile entrypoint binary
FROM docker.io/library/alpine AS entrypoint
RUN apk add clang curl-dev build-base util-linux-dev
WORKDIR /workdir
COPY scripts/entrypoint /workdir
RUN clang++ -static-libgcc -static-libstdc++ -std=c++17 entrypoint.cpp -lcurl -o entrypoint

# Consolidating binaries
FROM base AS bin
WORKDIR /workdir
RUN mkdir bin
COPY --from=k8s /usr/local/bin/kubectl bin/kubectl
COPY --from=irsa-tokengen /workdir/bin/irsa-tokengen bin/irsa-tokengen
COPY --from=entrypoint /workdir/entrypoint bin/entrypoint
COPY --from=base /usr/local/bin/terraform bin/terraform

# Final runtime image
FROM docker.io/library/alpine:3.16.2
RUN apk add bash jq git openssh
COPY --from=bin /workdir/bin /usr/local/bin
ENV USER_UID=2000 \
    USER_NAME=i3-runner \
    HOME=/home/i3-runner
COPY scripts/usersetup /usersetup
RUN  /usersetup
USER 2000
ENTRYPOINT ["/usr/local/bin/entrypoint"]
LABEL org.opencontainers.image.source=https://github.com/galleybytes/infra3