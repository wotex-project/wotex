FROM debian@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171
RUN apt-get update && apt-get install -y --no-install-recommends build-essential autoconf automake libtool pkg-config ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY source.tar.gz /build/source.tar.gz
RUN echo '5d0f56cdd9f4f4bc6863dcac6bc9bdc7ea862566aefa29eef2f1bf649cc1ea3a  source.tar.gz' | sha256sum -c - && tar xzf source.tar.gz --strip-components=1
ENV CFLAGS="-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer"
ENV LDFLAGS="-fsanitize=address,undefined"
RUN ./autogen.sh && ./configure --prefix=/opt/libmodbus --disable-shared --enable-static && make -j2 && make install
COPY server.c /build/server.c
RUN cc -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror $CFLAGS /build/server.c -I/opt/libmodbus/include /opt/libmodbus/lib/libmodbus.a $LDFLAGS -o /usr/local/bin/fixture && sha256sum /usr/local/bin/fixture /opt/libmodbus/lib/libmodbus.a > /build/binaries.sha256
ENV ASAN_OPTIONS="detect_leaks=1:halt_on_error=1:abort_on_error=1"
ENV UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1"
USER 65534:65534
EXPOSE 1502
ENTRYPOINT ["/usr/local/bin/fixture"]
