defmodule ScxmlHttpEngine.Plugs.OtelPayloadLogger do
  @moduledoc """
  Automatically captures the request/response payload (body + headers) for every
  request, without adding manual `Logger` calls to routes/handlers.

  It **logs** the payload (level-gated) **and** sets it as OpenTelemetry span
  attributes (`http.request.body/headers`, `http.response.body/headers`) on the
  active request span created by `:opentelemetry_bandit`, so payloads show up in
  the trace backend as well.

  ## Level-gated fidelity

  * `:debug` — full fidelity: all headers + raw bodies (request and response).
  * `:info` (and above) — safe/trimmed: `authorization`/`cookie` headers are
    scrubbed and bodies are truncated to `@max_body_length` bytes, so secrets
    aren't forwarded to the log/trace sink.

  This is driven by the configured `Logger` level (e.g. the
  `SCXML_HTTP_ENGINE_LOG_LEVEL` env override), so a single switch controls how
  much payload detail is captured.

  ## Body caching

  The router does not use `Plug.Parsers`; handlers read the request body
  themselves via `read_json`. This plug therefore reads the full body once and
  caches it in `conn.assigns[:raw_request_body]` so downstream handlers can
  re-read it without hitting an empty socket.
  """

  import Plug.Conn

  alias OpenTelemetry.Tracer

  require Logger

  @max_body_length 4096
  # Headers scrubbed when not at :debug level.
  @sensitive_headers ["authorization", "cookie", "proxy-authorization", "x-api-key"]

  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    # Cache the raw request body so handlers can still read it after we peek.
    {:ok, raw_body, conn} = read_full_body(conn, "")
    conn = assign(conn, :raw_request_body, raw_body)

    debug? = Logger.level() == :debug

    req_headers = maybe_scrub_headers(conn.req_headers, debug?)
    req_body = maybe_truncate(raw_body, debug?)

    set_span_attributes([
      {"http.request.body", req_body},
      {"http.request.headers", inspect(req_headers)}
    ])

    if debug? do
      Logger.debug(fn ->
        "▶ REQUEST #{conn.method} #{conn.request_path}\nHeaders: #{inspect(req_headers)}\nBody: #{req_body}"
      end)
    else
      Logger.info(fn -> "▶ REQUEST #{conn.method} #{conn.request_path}\nBody: #{req_body}" end)
    end

    register_before_send(conn, fn conn ->
      resp_body = conn.resp_body || ""
      resp_headers = maybe_scrub_headers(conn.resp_headers, debug?)
      resp_body = maybe_truncate(resp_body, debug?)

      set_span_attributes([
        {"http.response.body", resp_body},
        {"http.response.headers", inspect(resp_headers)}
      ])

      if debug? do
        Logger.debug(fn ->
          "◀ RESPONSE #{conn.status}\nHeaders: #{inspect(resp_headers)}\nBody: #{resp_body}"
        end)
      else
        Logger.info(fn -> "◀ RESPONSE #{conn.status}\nBody: #{resp_body}" end)
      end

      conn
    end)
  end

  defp read_full_body(conn, acc) do
    case read_body(conn) do
      {:ok, body, conn} -> {:ok, acc <> body, conn}
      {:more, body, conn} -> read_full_body(conn, acc <> body)
      {:error, _reason} -> {:ok, acc, conn}
    end
  end

  defp maybe_truncate(body, true), do: body
  defp maybe_truncate(body, false), do: String.slice(body, 0, @max_body_length)

  defp maybe_scrub_headers(headers, true), do: headers

  defp maybe_scrub_headers(headers, false) do
    Enum.reject(headers, fn {name, _value} ->
      Enum.member?(@sensitive_headers, name |> to_string() |> String.downcase())
    end)
  end

  defp set_span_attributes(attrs) do
    Tracer.set_attributes(attrs)
  rescue
    # If no span/OTel is active, attributes are simply not recorded.
    _ -> :ok
  end
end
