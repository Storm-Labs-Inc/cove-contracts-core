FROM node:20-bookworm

SHELL ["/bin/bash", "-lc"]

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
  git \
  curl \
  ca-certificates \
  build-essential \
  pkg-config \
  libssl-dev \
  python3 \
  && rm -rf /var/lib/apt/lists/*

# Removed root-level Rust/Foundry install; will install under non-root user

# Enable pnpm via Corepack
RUN corepack enable

# Create non-root user and switch
RUN useradd -m -s /bin/bash ubuntu
USER ubuntu

# Install Rust toolchain and Foundry for the ubuntu user
ENV CARGO_HOME=/home/ubuntu/.cargo
ENV RUSTUP_HOME=/home/ubuntu/.rustup
ENV PATH=/home/ubuntu/.cargo/bin:/home/ubuntu/.foundry/bin:${PATH}
RUN curl -sSf https://sh.rustup.rs | bash -s -- -y
RUN curl -L https://foundry.paradigm.xyz | bash && \
  foundryup -b v1.3.6 && \
  forge --version && anvil --version

WORKDIR /home/ubuntu
CMD ["bash"]

