# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# scxml_http_engine — HTTP engine for the scxml-orchestrator runtime.
#
# Multi-stage build:
#   Stage 1 (builder): fetch deps (falling back to the git dependency for
#                      scxml-orchestrator when the sibling path is absent),
#                      compile, and assemble a self-contained Mix release.
#   Stage 2 (runtime): minimal runtime image hosting only the release.
#
# Usage:
#   docker build -t scxml-http-engine .
#   docker run --rm -p 4000:4000 -e SCXML_HTTP_ENGINE_PORT=4000 scxml-http-engine
#
# Endpoint:  GET  /healthz  (liveness)
# ---------------------------------------------------------------------------

# --- Builder ---------------------------------------------------------------
FROM hexpm/elixir:1.20.3-erlang-28.5.0.5-debian-bookworm-20260803-slim AS builder

# Create a non-root user so deps/_build/release land in its home.
RUN useradd --create-home --uid 1000 scxml_engine
WORKDIR /app
RUN chown scxml_engine:scxml_engine /app
USER scxml_engine

# The builder needs the OS toolchain: git (to resolve the :scxml_orchestrator
# git dependency) and build-essential (in case a transitive dep compiles NIFs /
# native code). Install as root before switching users.
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends git build-essential && \
    rm -rf /var/lib/apt/lists/*
USER scxml_engine

# Hex + rebar package managers.
RUN mix local.hex --force && \
    mix local.rebar --force

# Fetch deps first (layer-cached on mix.exs/mix.lock changes).
# The git fallback for :scxml_orchestrator is deliberate: `../scxml-orchestrator`
# is outside the build context, so Mix resolves the git dependency here.
COPY --chown=scxml_engine:scxml_engine mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy the remaining project sources and config.
COPY --chown=scxml_engine:scxml_engine lib ./lib
COPY --chown=scxml_engine:scxml_engine config ./config
COPY --chown=scxml_engine:scxml_engine .formatter.exs ./.formatter.exs

# Build the release (MIX_ENV=prod).
ENV MIX_ENV=prod
RUN mix release scxml_http_engine

# --- Runtime ---------------------------------------------------------------
FROM debian:bookworm-slim AS runtime

# UTF-8 locale so the ERTS uses utf8 native name encoding (avoids the
# "native name encoding of latin1" warning and keeps filenames/IO sane).
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Release bundles the Erlang runtime, but still needs a few OS libraries
# (iproute2 not required; minimal set for BEAM on glibc).
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libstdc++6 \
      openssl \
      libncurses6 \
      locales \
    && locale-gen C.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Non-root runtime user.
RUN useradd --create-home --uid 1000 scxml_engine
WORKDIR /app

COPY --from=builder --chown=scxml_engine:scxml_engine /app/_build/prod/rel/scxml_http_engine ./rel

USER scxml_engine

# The HTTP listener port.
ENV SCXML_HTTP_ENGINE_PORT=4000
EXPOSE 4000

# `start` launches the app (blocking); `eval` can run arbitrary code.
CMD ["/app/rel/bin/scxml_http_engine", "start"]
