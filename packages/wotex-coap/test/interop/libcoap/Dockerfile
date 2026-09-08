FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git build-essential autoconf automake libtool pkg-config && rm -rf /var/lib/apt/lists/*
RUN git clone https://github.com/obgm/libcoap.git /src && cd /src && git checkout 7cf7465b784baded4de183290c547d582becfd28 && ./autogen.sh && ./configure --disable-dtls --disable-documentation --disable-tests && make -j2 && make install && ldconfig
USER 65534:65534
EXPOSE 5683/udp
ENTRYPOINT ["coap-server-notls", "-A", "0.0.0.0", "-p", "5683", "-v", "0"]
