defmodule ScxmlHttpEngine.Tracer do
  @moduledoc """
  A `Plug` that injects request-level metadata into the Logger process
  dictionary so every downstream log line (engine steps, payload logging, etc.)
  carries the request id and the OpenTelemetry trace/span id.

  ## Pipeline placement

  Must be placed **after** `Plug.RequestId` (which sets `Process.get(:request_id)`)
  and **after** the `CodeReloader` plug (dev-only).  Placed before `:match` /
  `:dispatch` so that all downstream code inherits the metadata.

  ## Quiet paths

  Health-check and API-documentation endpoints
  (`/healthz`, `/openapi`, `/swaggerui`) are set to `:warning` process-level
  so that `:info` and `:debug` messages are suppressed for those routes.

  > Request/response payload logging and completion logs are handled by
  > `ScxmlHttpEngine.Plugs.OtelPayloadLogger`; this plug only concerns itself
  > with metadata stamping and quiet-path suppression.
  """

  @quiet_prefixes ["/healthz", "/openapi", "/swaggerui"]

  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    # Read from the process dictionary where Plug.RequestId stored it.
    request_id = Process.get(:request_id)

    # Safely extract the OTel trace / span context created by
    # :opentelemetry_bandit so it can be included in every log line.
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
    if Enum.any?(@quiet_prefixes, &String.starts_with?(conn.request_path, &1)) do
      Logger.put_process_level(self(), :warning)
    end

    conn
  end
end
