FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    charon-systemd \
    strongswan-swanctl \
    strongswan-pki \
    libcharon-extra-plugins \
    libcharon-extauth-plugins \
    libstrongswan-standard-plugins \
    ca-certificates \
    curl \
    dnsmasq \
    dnsutils \
    iproute2 \
    iptables \
    iputils-ping \
    openssl \
    python3 \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/securewave-ikev2-lab-entrypoint
COPY egress_service.py /usr/local/libexec/securewave-ikev2-lab-egress

RUN chmod 0755 /usr/local/bin/securewave-ikev2-lab-entrypoint \
    /usr/local/libexec/securewave-ikev2-lab-egress

ENTRYPOINT ["securewave-ikev2-lab-entrypoint"]
CMD ["sleep", "infinity"]
