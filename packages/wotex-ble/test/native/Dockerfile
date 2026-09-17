# Explicit native build lane: Debian 12, Elixir 1.18.4 and OTP 27.3.4.15.
# The multi-architecture index digest selects arm64 or amd64 by --platform.
FROM hexpm/elixir@sha256:473f77ee88977dc8cc5d05fb91080a308be86be3fc27d50aef9a837d07c8268b
RUN apt-get update \
 && apt-get install -y --no-install-recommends cmake ninja-build pkg-config g++ gcc binutils xz-utils libexpat1-dev ca-certificates git rsync \
 && rm -rf /var/lib/apt/lists/*
RUN mix local.hex --force && mix local.rebar --force
