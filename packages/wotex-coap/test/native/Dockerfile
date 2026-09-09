FROM debian@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171
RUN apt-get update && apt-get install -y --no-install-recommends build-essential cmake pkg-config libssl-dev patch && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY source.tar.gz /build/source.tar.gz
RUN echo 'd8ce60574b1ed60ab1ef5c8d656bdf1c4a28fff0a00e9cb9f2cce3772f9db8cd  source.tar.gz' | sha256sum -c - && mkdir source && tar xzf source.tar.gz --strip-components=1 -C source
COPY 0001-reject-unsaved-sender-sequences.patch /build/sequence.patch
RUN patch --batch --fuzz=0 -p1 -d source < /build/sequence.patch
COPY 0002-skip-empty-cbor-byte-copy.patch /build/empty-bytes.patch
RUN patch --batch --fuzz=0 -p1 -d source < /build/empty-bytes.patch
COPY 0003-limit-whole-body-assembly.patch /build/body-limit.patch
RUN patch --batch --fuzz=0 -p1 -d source < /build/body-limit.patch
COPY 0004-reject-representation-restart.patch /build/representation.patch
RUN patch --batch --fuzz=0 -p1 -d source < /build/representation.patch
ENV CFLAGS="-O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer"
ENV LDFLAGS="-fsanitize=address,undefined"
RUN cmake -S source -B build -DENABLE_OSCORE=ON -DENABLE_DTLS=ON -DDTLS_BACKEND=openssl -DBUILD_SHARED_LIBS=OFF -DENABLE_DOCS=OFF -DENABLE_EXAMPLES=OFF && cmake --build build --parallel 2
COPY oscore_sequence_test.c /build/oscore_sequence_test.c
RUN cc -std=c11 -Wall -Wextra -Werror $CFLAGS -I/build/build/include -I/build/source/include /build/oscore_sequence_test.c /build/build/libcoap-3.a $LDFLAGS -lssl -lcrypto -o /usr/local/bin/oscore-sequence && sha256sum source.tar.gz sequence.patch empty-bytes.patch source/src/coap_oscore.c source/src/oscore/oscore_cbor.c build/libcoap-3.a /usr/local/bin/oscore-sequence > /build/artifacts.sha256 && dpkg-query -W > /build/toolchain.packages
COPY identity.c identity.h store.c store.h /build/first-party/
COPY oscore_identity_test.c oscore_store_test.c oscore_store_send_test.c /build/
RUN cc -std=c11 -Wall -Wextra -Werror $CFLAGS -I/build/first-party /build/first-party/identity.c /build/oscore_identity_test.c $LDFLAGS -lcrypto -o /usr/local/bin/oscore-identity
RUN cc -std=c11 -Wall -Wextra -Werror $CFLAGS -DWCO_STORE_TEST -I/build/first-party /build/first-party/identity.c /build/first-party/store.c /build/oscore_store_test.c $LDFLAGS -lcrypto -o /usr/local/bin/oscore-store
RUN cc -std=c11 -Wall -Wextra -Werror $CFLAGS -DWCO_STORE_TEST -I/build/first-party -I/build/build/include -I/build/source/include /build/first-party/identity.c /build/first-party/store.c /build/oscore_store_send_test.c /build/build/libcoap-3.a $LDFLAGS -lssl -lcrypto -o /usr/local/bin/oscore-store-send
RUN cc -std=c11 -Wall -Wextra -Werror $CFLAGS -I/build/first-party -c /build/first-party/store.c -o /build/store-production.o && sha256sum first-party/* oscore_identity_test.c oscore_store_test.c oscore_store_send_test.c store-production.o /usr/local/bin/oscore-identity /usr/local/bin/oscore-store /usr/local/bin/oscore-store-send >> /build/artifacts.sha256
COPY oscore_block_limit_test.c /build/oscore_block_limit_test.c
RUN cc -std=c11 -Wall -Wextra -Werror $CFLAGS -DWCO_ALLOCATION_WRAP -I/build/build/include -I/build/source/include /build/oscore_block_limit_test.c /build/build/libcoap-3.a $LDFLAGS -Wl,--wrap=coap_new_binary,--wrap=coap_resize_binary -lssl -lcrypto -o /usr/local/bin/oscore-block-limit && sha256sum body-limit.patch representation.patch source/src/coap_block.c oscore_block_limit_test.c /usr/local/bin/oscore-block-limit >> /build/artifacts.sha256
ENV ASAN_OPTIONS="detect_leaks=1:halt_on_error=1:abort_on_error=1"
ENV UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1"
USER 65534:65534
ENTRYPOINT ["/usr/local/bin/oscore-sequence"]
