# syntax=docker/dockerfile:1
FROM elixir:1.19.5-otp-28 AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential ca-certificates git openssh-client \
  && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8
ENV MIX_ENV=prod

ARG JIDO_OS_DEPLOY_KEY

WORKDIR /workspace

RUN mix local.hex --force \
  && mix local.rebar --force

COPY build_support build_support
COPY jido_hive_server/mix.exs jido_hive_server/mix.lock jido_hive_server/

WORKDIR /workspace/jido_hive_server

COPY jido_hive_server/config config

RUN mkdir -p /root/.ssh \
  && chmod 700 /root/.ssh \
  && ssh-keyscan github.com >> /root/.ssh/known_hosts \
  && if [ -n "${JIDO_OS_DEPLOY_KEY:-}" ]; then \
    printf '%s\n' "$JIDO_OS_DEPLOY_KEY" > /root/.ssh/id_ed25519_jido_os; \
    chmod 600 /root/.ssh/id_ed25519_jido_os; \
    printf 'Host github.com\n  HostName github.com\n  User git\n  IdentityFile /root/.ssh/id_ed25519_jido_os\n  IdentitiesOnly yes\n' > /root/.ssh/config; \
  fi \
  && mix deps.get \
  && rm -f /root/.ssh/id_ed25519_jido_os /root/.ssh/config
RUN MIX_ENV=dev mix deps.get \
  && MIX_ENV=dev mix deps.compile agent_session_manager --include-children \
  && MIX_ENV=dev mix deps.compile jido_integration_v2_runtime_asm_bridge --include-children
RUN mix deps.compile
RUN mix deps.compile jido jido_action jido_signal jido_shell jido_vfs --include-children
RUN mix deps.compile jido_os --include-children
RUN mix deps.compile \
  jido_harness \
  jido_integration_v2 \
  jido_integration_v2_runtime_asm_bridge \
  jido_integration_v2_codex_cli \
  jido_integration_v2_github \
  jido_integration_v2_notion \
  --include-children

COPY jido_hive_server/lib lib
COPY jido_hive_server/priv priv
COPY jido_hive_server/rel rel

RUN mix compile
RUN mix release

FROM debian:trixie-slim AS runner

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates libncurses6 libsqlite3-0 libstdc++6 openssl tini \
  && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8
ENV PHX_SERVER=true
ENV RELEASE_DISTRIBUTION=none
ENV SHELL=/bin/bash

RUN useradd --system --create-home --home-dir /app --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=builder --chown=app:app /workspace/jido_hive_server/_build/prod/rel/jido_hive_server ./

USER app

EXPOSE 4000

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/bin/server"]
