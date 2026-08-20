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

# OpenTelemetry: export spans to the OpenTelemetry Collector via OTLP/HTTP
# (otel/otelcol-config.yaml + Jaeger for the waterfall UI at :16686).
#
# The endpoint defaults to a local collector (localhost:4318) for host-side
# `mix` runs; the docker-compose stack overrides it to http://otel-collector:4318.
# The transport can be switched with OTEL_EXPORTER_OTLP_PROTOCOL (grpc),
# and OTEL_TRACES_EXPORTER=none disables export entirely.
otlp_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")

otlp_protocol =
  case System.get_env("OTEL_EXPORTER_OTLP_PROTOCOL", "http/protobuf") do
    "grpc" -> :grpc
    _ -> :http_protobuf
  end

if config_env() == :test do
  # Test env keeps the batch processor disabled so unit tests never attempt
  # network exports; spans are still collected internally by the SDK.
  config :opentelemetry, :processors, []
else
  config :opentelemetry, :processors,
    otel_batch_processor: %{
      exporter: {:opentelemetry_exporter, %{otlp_endpoint: otlp_endpoint, otlp_protocol: otlp_protocol}}
    }
end

# Span detail fidelity: INFO (default) emits only the coarse system-flow spans
# (HTTP + handler + macrostep.process_event). DEBUG additionally emits the
# fine-grained interpreter spans (select_transitions / execute_transition /
# expression.evaluate) from the in-process scxml-orchestrator library.
# Driven by the same SCXML_HTTP_ENGINE_LOG_LEVEL env var as the Logger level.
span_detail =
  case System.get_env("SCXML_HTTP_ENGINE_LOG_LEVEL", "info") do
    "debug" -> :debug
    _ -> :info
  end

config :scxml_http_engine, :span_detail, span_detail

config :scxml_orchestrator, :span_detail, span_detail
