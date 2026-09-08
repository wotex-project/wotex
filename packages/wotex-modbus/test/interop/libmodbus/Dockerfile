FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends build-essential autoconf automake libtool ca-certificates curl && rm -rf /var/lib/apt/lists/*
WORKDIR /build
RUN curl -fsSL https://codeload.github.com/stephane/libmodbus/tar.gz/9af6c16074df566551bca0a7c37443e48f216289 -o source.tar.gz && tar xzf source.tar.gz --strip-components=1 && ./autogen.sh && ./configure --prefix=/usr/local && make -j2 && make install && ldconfig
COPY server.c /build/server.c
RUN cc -Wall -Wextra -Werror /build/server.c -lmodbus -o /usr/local/bin/fixture
USER 65534:65534
EXPOSE 1502
ENTRYPOINT ["/usr/local/bin/fixture"]
