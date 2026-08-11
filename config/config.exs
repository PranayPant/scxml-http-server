import Config

# The port the Plug router listens on. Override at runtime with
# `SCXML_HTTP_ENGINE_PORT` if the HTTP engine is deployed behind a proxy.
config :scxml_http_engine, ScxmlHttpEngine.Router,
  port: String.to_integer(System.get_env("SCXML_HTTP_ENGINE_PORT") || "4000")

import_config "#{config_env()}.exs"
