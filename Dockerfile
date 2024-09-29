# Use Ubuntu as the base image
FROM ubuntu:20.04

# Set environment variables to avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary dependencies
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    pkg-config \
    libcurl4-openssl-dev \
    zlib1g-dev \
    libdw-dev \
    libiberty-dev \
    libssl-dev \
    python3 \
    ca-certificates \
    xz-utils \
    --no-install-recommends && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Zig (you can modify the version if needed)
RUN wget https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz -O zig.tar.xz && \
    tar -xf zig.tar.xz && \
    mv zig-linux-x86_64-0.13.0 /opt/zig && \
    ln -s /opt/zig/zig /usr/local/bin/zig && \
    rm zig.tar.xz

# Build and install Kcov
RUN git clone https://github.com/SimonKagstrom/kcov.git /tmp/kcov && \
    cd /tmp/kcov && \
    mkdir build && cd build && \
    cmake .. && make && make install && \
    cd / && rm -rf /tmp/kcov

# Install ZLS (Zig Language Server)
RUN git clone https://github.com/zigtools/zls /tmp/zls && \
    cd /tmp/zls && \
    git checkout 0.13.0 && \
    zig build -Doptimize=ReleaseSafe && \
    mv ./zig-out/bin/zls /usr/local/bin/zls && \
    cd / && rm -rf /tmp/zls

# Set Zig as default
ENV PATH="/opt/zig:${PATH}"

# Display versions of installed tools for confirmation
RUN zig version && kcov --version

# Default command (can be customized)
CMD ["bash"]
