FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Use official Ubuntu mirrors (IMPORTANT)
RUN sed -i 's|http://archive.ubuntu.com/ubuntu|http://archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list

# Base tools first
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    gnupg \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Embedded toolchain + OpenOCD
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc-arm-none-eabi \
    binutils-arm-none-eabi \
    libnewlib-arm-none-eabi \
    libnewlib-dev \
    gdb-multiarch \
    openocd \
    make \
    git \
    python3 \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y udev

# J-Link install (optional)
COPY tools/JLink_Linux_V954_x86_64.deb /tmp/
RUN apt-get update && apt-get install -y /tmp/JLink_Linux_V954_x86_64.deb || true \
    && rm -f /tmp/JLink_Linux_V954_x86_64.deb

WORKDIR /workspace

CMD ["/bin/bash"]
