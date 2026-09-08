FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl build-essential cmake && rm -rf /var/lib/apt/lists/*
RUN mkdir /src && curl -fsSL --retry 2 --max-time 120 https://codeload.github.com/bacnet-stack/bacnet-stack/tar.gz/3603048350b8ba543ec76cf6aa8a232b3f4d442d | tar xz --strip-components=1 -C /src && cd /src && cmake -S . -B build -DBACNET_STACK_BUILD_APPS=ON && cmake --build build --target server -j2
USER 65534:65534
ENV BACNET_IFACE=eth0
EXPOSE 47808/udp
ENTRYPOINT ["/src/build/server", "123"]
