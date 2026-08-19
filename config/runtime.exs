import Config

# Runtime configuration, evaluated at app (and release) boot.
# Allows overriding the HTTP port via the SCXML_HTTP_ENGINE_PORT environment
# variable (used by the container / release without recompiling).
if config_env() == :prod do
  config :scxml_http_engine, ScxmlHttpEngine.Router,
    port: String.to_integer(System.get_env("SCXML_HTTP_ENGINE_PORT") || "4000")
end

# Allow overriding the Logger level at launch via the
# SCXML_HTTP_ENGINE_LOG_LEVEL environment variable (e.g. "debug", "info").
# Works in every environment and overrides the per-env default
# (dev = :debug, prod = :info) when set. This also drives how much request/
# response payload detail OtelPayloadLogger captures (debug = full, info = trimmed).
if level = System.get_env("SCXML_HTTP_ENGINE_LOG_LEVEL") do
  config :logger, level: String.to_existing_atom(String.downcase(level))
end

# OpenTelemetry: export spans to stdout in production (no sidecar needed for
# local debugging).  Override via standard OTel environment variables for
# deployment (e.g. OTEL_TRACES_EXPORTER=otlp).
#
# In dev/test the exporter is disabled so logs aren't cluttered with raw
# Erlang span tuples — the Tracer plug's structured "API Request Completed"
# log lines are sufficient for local debugging.
if config_env() == :prod do
  config :opentelemetry, :processors,
    otel_batch_processor: %{
      exporter: {:otel_exporter_stdout, []}
    }
else
  # Dev/test: no batch processor configured — spans are collected
  # internally by the SDK but not exported.  The Tracer plug's structured
  # "API Request Completed" log lines and the Engine debug logs provide
  # all the observability you need locally without the raw Erlang tuples.
  config :opentelemetry, :processors, []
end
