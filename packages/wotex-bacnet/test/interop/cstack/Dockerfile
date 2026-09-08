FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl build-essential cmake && rm -rf /var/lib/apt/lists/*
LABEL org.opencontainers.image.source="https://github.com/bacnet-stack/bacnet-stack" org.opencontainers.image.revision="3603048350b8ba543ec76cf6aa8a232b3f4d442d"
RUN mkdir /src && curl -fsSL --retry 2 --max-time 120 -o /tmp/source.tar.gz https://codeload.github.com/bacnet-stack/bacnet-stack/tar.gz/3603048350b8ba543ec76cf6aa8a232b3f4d442d && echo 'b5529b73551c7bea6fdd2e6e44c1e4682f1ccb017f5e3ce6d28cac87c0d26043  /tmp/source.tar.gz' | sha256sum --check - && tar xzf /tmp/source.tar.gz --strip-components=1 -C /src && rm /tmp/source.tar.gz && cd /src && cmake -S . -B build -DBACNET_STACK_BUILD_APPS=ON && cmake --build build --target server -j2
USER 65534:65534
ENV BACNET_IFACE=eth0
EXPOSE 47808/udp
ENTRYPOINT ["/src/build/server", "123"]
