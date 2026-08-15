import Config

# Structured JSON logging for production aggregators.
config :logger, :default_handler,
  formatter:
    {LoggerJSON.Formatters.Logger,
     metadata: [:request_id, :trace_id, :span_id, :instance_id, :event, :graph_id, :body, :status, :method, :path, :error]}

# Default to info level; debug is only for development.
config :logger, level: :info
