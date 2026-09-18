# The Linux image of the native checks. On a host that is not Linux,
# `mix native.lint --tidy` and `mix native.test` run each native_check suite
# that requires Linux (tooling/packages.yaml) in a container built from this
# file, and `mix native.bench` each native_bench benchmark that requires
# Linux, with the repository mounted read-only at its host path and the
# native cache writable (Wotex.Workspace.NativeContainer, suite.sh, bin/mix).
#
# Pins: the base image by digest (a multi-architecture index, so the image
# is native on arm64 and amd64 hosts) with the Elixir and OTP of
# lanes.current in tooling/packages.yaml; Ubuntu 24.04's GCC 13; LLVM 23
# from apt.llvm.org, the major version CI installs (LLVM_MAJOR in
# .github/workflows/ci.yml): clang-format and clang-tidy, and clang, which
# compiles the nanobench benchmarks. The image tag is a digest of this file,
# so a change here builds a new image.
FROM hexpm/elixir:1.20.2-erlang-29.0.4-ubuntu-noble-20260730.1@sha256:e9301bad4a5e7238674db45a8cc00cb3a80310a037294fc6f8616d1ed9c0b796

ARG LLVM_MAJOR=23
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      binutils build-essential ca-certificates cmake curl file g++-13 gcc-13 git \
      libexpat1-dev libssl-dev ninja-build patch perl pkg-config python3 xz-utils \
 && curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key -o /etc/apt/trusted.gpg.d/apt.llvm.org.asc \
 && echo "deb http://apt.llvm.org/noble/ llvm-toolchain-noble-${LLVM_MAJOR} main" \
      > /etc/apt/sources.list.d/llvm.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      "clang-${LLVM_MAJOR}" "clang-format-${LLVM_MAJOR}" "clang-tidy-${LLVM_MAJOR}" \
 && rm -rf /var/lib/apt/lists/* \
 && test "$(gcc -dumpversion | cut -d. -f1)" = 13 \
 && test "$(g++ -dumpversion | cut -d. -f1)" = 13 \
 && clang-tidy-${LLVM_MAJOR} --version | grep -q "LLVM version ${LLVM_MAJOR}\." \
 && "/usr/lib/llvm-${LLVM_MAJOR}/bin/clang++" --version | grep -q "clang version ${LLVM_MAJOR}\." \
 && elixir --version | grep -q "^Elixir 1\.20\.2 " \
 && mix local.hex --force \
 && mix local.rebar --force
