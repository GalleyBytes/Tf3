FROM alpine/k8s:1.20.7 AS k8s

FROM ubuntu:20.04 AS irsa-tokengen
ARG TARGETPLATFORM
WORKDIR /workdir
RUN mkdir bin
RUN apt update && apt install wget -y
RUN wget https://github.com/isaaguilar/irsa-tokengen/releases/download/v1.0.0/irsa-tokengen-v1.0.0-linux-$(echo $TARGETPLATFORM | cut -d '/' -f2).tgz &&\
 tar xzf irsa-tokengen-v1.0.0-linux-$(echo $TARGETPLATFORM | cut -d '/' -f2).tgz && mv irsa-tokengen bin/irsa-tokengen

FROM ubuntu:latest AS bin
WORKDIR /workdir
RUN mkdir bin
COPY --from=k8s /usr/bin/kubectl bin/kubectl
COPY --from=irsa-tokengen /workdir/bin/irsa-tokengen bin/irsa-tokengen

FROM docker.io/ubuntu:latest AS entrypoint
RUN apt update && apt install clang libcurl4-gnutls-dev uuid-dev -y
WORKDIR /workdir
COPY scripts/entrypoint /workdir
RUN clang++ -static-libgcc -static-libstdc++ -std=c++17 entrypoint.cpp -lcurl -o entrypoint

FROM docker.io/ubuntu:latest
ENV USER_UID=2000 \
    USER_NAME=i3-runner \
    HOME=/home/i3-runner
COPY scripts/usersetup scripts/debug-toolset.sh /
RUN  bash debug-toolset.sh && /usersetup
COPY --from=bin /workdir/bin /usr/local/bin
COPY --from=entrypoint /workdir/entrypoint /usr/local/bin/entrypoint
USER 2000
ENTRYPOINT ["/usr/local/bin/entrypoint"]
LABEL org.opencontainers.image.source=https://github.com/galleybytes/infrakube