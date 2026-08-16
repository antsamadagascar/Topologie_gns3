FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN echo "snort snort/address_range string 192.168.0.0/16" | debconf-set-selections
RUN apt-get update && apt-get install -y \
    iproute2 \
    iptables \
    net-tools \
    iputils-ping \
    nano \
    tcpdump \
    curl \
    squid \
    snort \
    nginx \
    && apt-get clean
CMD ["/bin/bash"]
