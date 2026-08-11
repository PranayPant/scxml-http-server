import Config

# Runtime configuration, evaluated at app (and release) boot.
# Allows overriding the HTTP port via the SCXML_HTTP_ENGINE_PORT environment
# variable (used by the container / release without recompiling).
if config_env() == :prod do
  config :scxml_http_engine, ScxmlHttpEngine.Router,
    port: String.to_integer(System.get_env("SCXML_HTTP_ENGINE_PORT") || "4000")
end
