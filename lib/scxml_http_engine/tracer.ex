defmodule ScxmlHttpEngine.Tracer do
  @moduledoc """
  A `Plug` that injects request-level metadata into the Logger process
  dictionary and registers a `register_before_send` callback for three-level
  request/response tracing:

    * `:error` â€” 5xx responses
    * `:info`  â€” 2xx / 4xx responses (suppressed for health-check/API-doc paths)
    * `:debug` â€” intermediate engine steps logged by `ScxmlHttpEngine.Engine`

  ## Pipeline placement

  Must be placed **after** `Plug.RequestId` (which sets `Process.get(:request_id)`)
  and **after** the `CodeReloader` plug (dev-only).  Placed before `:match` /
  `:dispatch` so that all downstream code inherits the metadata.

  ## Quiet paths

  Health-check and API-documentation endpoints
  (`/healthz`, `/openapi`, `/swaggerui`) are set to `:warning` process-level
  so that `:info` and `:debug` messages are suppressed for those routes.
  """

  import Plug.Conn

  require Logger

  @quiet_prefixes ["/healthz", "/openapi", "/swaggerui"]

  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    # Read from the process dictionary where Plug.RequestId stored it.
    request_id = Process.get(:request_id)

    # Safely extract the OTel trace / span context created by
    # :opentelemetry_cowboy so it can be included in every log line.
    otel_metadata =
      try do
        case OpenTelemetry.Tracer.current_span_ctx() do
          ctx when ctx != :undefined ->
            [
              trace_id: OpenTelemetry.Span.trace_id(ctx),
              span_id: OpenTelemetry.Span.span_id(ctx)
            ]

          _ ->
            []
        end
      rescue
        _ -> []
      end

    Logger.metadata([request_id: request_id] ++ otel_metadata)

    # Suppress info/debug for high-frequency health / API-doc endpoints.
    is_quiet_route = Enum.any?(@quiet_prefixes, &String.starts_with?(conn.request_path, &1))

    if is_quiet_route do
      Logger.put_process_level(self(), :warning)
    end

    # Register a before-send callback for request-completion logging.
    register_before_send(conn, fn callback_conn ->
      status = callback_conn.status

      cond do
        # 5xx â†’ :error level
        status >= 500 ->
          Logger.error("API Request Failed",
            status: status,
            method: callback_conn.method,
            path: callback_conn.request_path
          )

        # 2xx / 4xx â†’ :info level (unless this is a quiet route)
        status < 500 ->
          if !is_quiet_route do
            Logger.info("API Request Completed",
              status: status,
              method: callback_conn.method,
              path: callback_conn.request_path
            )
          end
      end

      callback_conn
    end)
  end
end
