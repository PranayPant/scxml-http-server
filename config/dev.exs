import Config

# Human-readable console logging for local development.
# Uses Logger.Formatter.new/1 for Elixir 1.15+ Erlang :logger compatibility.
config :logger, :default_handler,
  formatter:
    Logger.Formatter.new(
      format: "[$level] $message $metadata\n",
      metadata: [
        :request_id,
        :trace_id,
        :span_id,
        :instance_id,
        :event,
        :graph_id,
        :body,
        :status,
        :method,
        :path,
        :error
      ]
    )

# Verbose debug logging during development.
config :logger, level: :debug
