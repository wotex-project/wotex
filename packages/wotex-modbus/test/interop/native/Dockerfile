FROM debian@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY command.c probe.c check.c group_fault.c /build/
ENV CFLAGS="-std=c11 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer"
RUN cc $CFLAGS command.c -o /usr/local/bin/command && cc $CFLAGS probe.c -o /usr/local/bin/probe && cc $CFLAGS check.c -o /usr/local/bin/check
RUN cc $CFLAGS -Dsetpgid=wmb_fault_setpgid command.c group_fault.c -o /usr/local/bin/command-fault
RUN sha256sum *.c /usr/local/bin/command /usr/local/bin/probe /usr/local/bin/check /usr/local/bin/command-fault > /build/artifacts.sha256 && dpkg-query -W > /build/toolchain.packages
ENV ASAN_OPTIONS="detect_leaks=0:halt_on_error=1:abort_on_error=1"
ENV UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1"
USER 65534:65534
ENTRYPOINT ["/usr/local/bin/check", "/usr/local/bin/command", "/usr/local/bin/probe", "/usr/local/bin/command-fault"]
