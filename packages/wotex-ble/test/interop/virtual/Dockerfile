FROM hexpm/elixir@sha256:4aa97e06567fc47061ca94f7fcab89157608a03a06a0d0c1282620a77031dbc1 AS lower
FROM hexpm/elixir@sha256:290e52da1c5d5cbf62344d384387e8bdfa7d8a64784302bb7770e76ad13c88a5
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl build-essential autoconf automake libtool pkg-config libdbus-1-dev libglib2.0-dev libreadline-dev libudev-dev python3 python3-venv qemu-system-arm=1:7.2+dfsg-7+deb12u18+b3 linux-image-6.1.0-53-arm64=6.1.187-1 linux-headers-6.1.0-53-arm64=6.1.187-1 linux-source-6.1=6.1.187-1 initramfs-tools kmod iproute2 dbus e2fsprogs && rm -rf /var/lib/apt/lists/*
COPY bluez.tar.gz /source/bluez.tar.gz
RUN echo '53a95c3dc9897f617b8bae0121d3f4c55c28a757bd48546c707bd2bbac45af0a  /source/bluez.tar.gz' | sha256sum -c - && tar -xzf /source/bluez.tar.gz -C /source
WORKDIR /source/bluez-2123ab772fbe97d1369fc9e179ea87c3469cf98f
RUN ./bootstrap && ./configure --prefix=/opt/bluez --enable-testing --enable-experimental --enable-deprecated --disable-systemd --disable-udev --disable-cups --disable-obex --disable-manpages --disable-mesh && make -j4 && make install && cp emulator/btvirt /opt/bluez/bin/btvirt
# The distribution omits HCIVHCI. Build the unmodified matching driver with
# its exact kernel headers/configuration/Module.symvers, never on the host.
RUN echo 'c0fc1b659e3a2cf9145f8056c80913ac3c5a992013ce72c172795412583bc8dc  /usr/src/linux-source-6.1.tar.xz' | sha256sum -c - && mkdir /module && tar -xJf /usr/src/linux-source-6.1.tar.xz -C /module --strip-components=3 linux-source-6.1/drivers/bluetooth/hci_vhci.c && echo '73e20d1971b77d38f3715990562e2fe8be03043362e01c5b0217c9e920d65e41  /module/hci_vhci.c' | sha256sum -c - && echo 'obj-m := hci_vhci.o' > /module/Makefile && make -C /lib/modules/6.1.0-53-arm64/build M=/module CONFIG_BT_HCIVHCI=m modules && install -m644 /module/hci_vhci.ko /lib/modules/6.1.0-53-arm64/kernel/drivers/bluetooth/hci_vhci.ko && depmod -a 6.1.0-53-arm64
COPY bluez/requirements.txt /opt/wbl/bluez/requirements.txt
RUN python3 -m venv /opt/sdk && /opt/sdk/bin/pip install --require-hashes --no-cache-dir -r /opt/wbl/bluez/requirements.txt
RUN apt-get update && apt-get install -y --no-install-recommends qemu-utils=1:7.2+dfsg-7+deb12u18+b3 && rm -rf /var/lib/apt/lists/*
COPY --from=lower /usr/local/lib/erlang /opt/lower/erlang
COPY --from=lower /usr/local/lib/elixir /opt/lower/elixir
COPY bluez /opt/wbl/bluez
COPY virtual /opt/wbl/fixture
RUN cp /opt/wbl/fixture/bootstrap.sh /bootstrap.sh && chmod 755 /bootstrap.sh && mkdir -p /results && python3 /opt/wbl/fixture/build_manifest.py > /opt/wbl/build.json
WORKDIR /results
