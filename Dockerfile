FROM ubuntu:22.10

RUN adduser tools && \
    apt update && \
    apt install -y postgresql-client curl gettext

RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    mv ./kubectl /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

RUN curl -LO https://github.com/mikefarah/yq/releases/download/v4.27.5/yq_linux_arm64 && \
    mv yq_linux_arm64 /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

USER tools
WORKDIR /tools

COPY --chown=tools:tools *.sql .
COPY --chown=tools:tools program.sh .
