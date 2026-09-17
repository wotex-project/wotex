# Explicit native build lane: Debian 12 with GCC 12.2.0, CMake 3.25.1 and Ninja.
# BEAM_LANE selects one pinned multi-architecture index digest: `lower` is
# Elixir 1.18.4 / OTP 27.3.4.15 (default) and `upper` is Elixir 1.20.2 /
# OTP 29.0.4. The index digest selects arm64 or amd64 by --platform. A build
# under binary translation may pass ERL_FLAGS="+JMsingle true" for the BEAM JIT.
ARG BEAM_LANE=lower
FROM hexpm/elixir@sha256:473f77ee88977dc8cc5d05fb91080a308be86be3fc27d50aef9a837d07c8268b AS lower
FROM hexpm/elixir@sha256:5858ed10da646c8d82a049d2c8c23ccb29c4ecedeb04e96414be3253609689da AS upper
FROM ${BEAM_LANE}
ARG ERL_FLAGS
RUN apt-get update \
 && apt-get install -y --no-install-recommends cmake ninja-build pkg-config g++ gcc binutils xz-utils libexpat1-dev ca-certificates git rsync \
 && rm -rf /var/lib/apt/lists/*
RUN mix local.hex --force && mix local.rebar --force
