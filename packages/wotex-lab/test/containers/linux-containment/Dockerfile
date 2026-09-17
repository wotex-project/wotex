# Linux lane for the reviewed-local Bubblewrap containment profile. The Rust
# stage supplies the pinned toolchain with rustfmt and Clippy; the Elixir stage
# is the pinned Erlang/OTP 29 image. Debian package versions are recorded by
# bin/check_linux_containment.exs, not locked by this file.
FROM rust@sha256:0e2bcaef56d041a486784e54104a81aebe0da44bd03019bd70bc0401e42e4a97 AS rust
RUN rustup component add rustfmt clippy

FROM hexpm/elixir@sha256:5858ed10da646c8d82a049d2c8c23ccb29c4ecedeb04e96414be3253609689da
RUN apt-get update \
  && apt-get install -y --no-install-recommends bubblewrap build-essential ca-certificates git procps \
  && rm -rf /var/lib/apt/lists/*
COPY --from=rust /usr/local/rustup /usr/local/rustup
COPY --from=rust /usr/local/cargo/bin /usr/local/cargo/bin
ENV RUSTUP_HOME=/usr/local/rustup PATH=/usr/local/cargo/bin:$PATH
