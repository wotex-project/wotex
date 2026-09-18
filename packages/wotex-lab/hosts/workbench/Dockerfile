ARG ELIXIR_IMAGE=hexpm/elixir:1.20.2-erlang-29.0.4-debian-bookworm-20260713-slim@sha256:290e52da1c5d5cbf62344d384387e8bdfa7d8a64784302bb7770e76ad13c88a5

FROM ${ELIXIR_IMAGE} AS build
ENV MIX_ENV=prod
WORKDIR /build

RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
COPY config ./config
RUN mix deps.get --only prod
RUN mix deps.compile

COPY lib ./lib
COPY priv ./priv
RUN mix compile --warnings-as-errors && mix release

FROM ${ELIXIR_IMAGE} AS runtime
LABEL org.opencontainers.image.title="WoTEx Lab Workbench" \
      org.opencontainers.image.description="Explicit disposable WoTEx Lab reference host" \
      org.opencontainers.image.source="https://github.com/wotex-project/wotex" \
      org.opencontainers.image.licenses="Apache-2.0"

RUN groupadd --gid 65532 wotex && \
    useradd --uid 65532 --gid 65532 --no-create-home --home-dir /tmp --shell /usr/sbin/nologin wotex

WORKDIR /opt/wotex
COPY --from=build --chown=65532:65532 /build/_build/prod/rel/wotex_lab_workbench ./

ENV HOME=/tmp \
    LANG=C.UTF-8 \
    PORT=4000 \
    RELEASE_TMP=/tmp \
    ERL_CRASH_DUMP=/tmp/erl_crash.dump

USER 65532:65532
EXPOSE 4000
VOLUME ["/var/lib/wotex-lab"]
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD /opt/wotex/bin/wotex_lab_workbench eval 'case WotexLabWorkbench.Health.probe() do :ok -> :ok; _ -> System.halt(1) end'
ENTRYPOINT ["/opt/wotex/bin/wotex_lab_workbench"]
CMD ["start"]
