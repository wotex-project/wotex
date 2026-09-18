# clang-tidy for the SDK-bound Matter sources: the `sdk` native_check suite
# of wotex-matter in tooling/packages.yaml runs clang-tidy in a container
# built from this file (Wotex.Workspace.NativeContainer), on the compile
# commands of the GN and CMake builds in the suite's workspace.
#
# The base is the image the Matter SDK build runs in, pinned by the same
# digest (`@image` in packages/wotex-matter/test/support/software/manifest.exs),
# with the packages that build installs, so every compile command resolves
# the same headers and GCC 12.2 toolchain. The suite builds and runs it for
# linux/amd64, the platform of that build. clang-tidy comes from LLVM 23 on
# apt.llvm.org, the major version CI installs (LLVM_MAJOR in
# .github/workflows/ci.yml). The image tag is a digest of this file, so a
# change here builds a new image.
FROM node:24-bookworm@sha256:6dac556d980b7f0e5498d08f08cee0ca67798b4ad6c23964a9214920e67758d0

ARG LLVM_MAJOR=23
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      binutils build-essential ca-certificates cmake curl libavahi-client-dev \
      libdbus-1-dev libglib2.0-dev libssl-dev ninja-build pkg-config \
 && curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key -o /etc/apt/trusted.gpg.d/apt.llvm.org.asc \
 && echo "deb http://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-${LLVM_MAJOR} main" \
      > /etc/apt/sources.list.d/llvm.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends "clang-tidy-${LLVM_MAJOR}" \
 && ln -s "/usr/bin/clang-tidy-${LLVM_MAJOR}" /usr/local/bin/clang-tidy \
 && rm -rf /var/lib/apt/lists/* \
 && test "$(uname -m)" = x86_64 \
 && test "$(g++ -dumpfullversion)" = 12.2.0 \
 && test "$(ninja --version)" = 1.11.1 \
 && clang-tidy --version | grep -q "LLVM version ${LLVM_MAJOR}\."
