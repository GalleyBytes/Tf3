#!/bin/bash -e
apt-get update
apt-get upgrade -y

apt-get install -y \
    software-properties-common \
    vim \
    wget \
    curl \
    sudo

wget https://packages.cloud.google.com/apt/doc/apt-key.gpg
sudo apt-key add apt-key.gpg
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

apt-get update
apt-cache policy docker-ce
apt-get install -y \
    git \
    zip \
    unzip \
    apt-transport-https \
    jq \
    python3-pip \
    mysql-client \
    postgresql-client \
    musl-dev \
    gcc \
    python3 \
    python3-dev \
    libffi-dev \
    python3-yaml \
    libssl-dev \
    gettext \
    dnsutils

pip3 install awscli cfn_flip ruamel.yaml
pip3 install urllib3[secure]

rm $0