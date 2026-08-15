defmodule ScxmlHttpEngine.Handlers.Statecharts do
  @moduledoc """
  Handlers for the `/statecharts` resource.

  Routes:
    - `POST /statecharts` â€” register and start an instance from an uploaded AST JSON document.
  """

  @behaviour Plug

  alias OpenApiSpex.Operation
  alias ScxmlHttpEngine.Engine
  alias ScxmlHttpEngine.Error
  alias ScxmlHttpEngine.OpenApi.Schemas

  require Logger

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with {:ok, body} <- read_json(conn),
         %{"document" => document} when not is_nil(document) <- body do
      document = normalize_document(document)
      result = Engine.register_and_start(document, body["instance_id"])
      {status, payload} = to_created(result)
      Plug.Conn.send_resp(conn, status, payload)
    else
      {:error, :bad_json} ->
        Logger.debug("statecharts: failed to parse request body as JSON")
        Plug.Conn.send_resp(conn, 400, Error.error_body("invalid request body"))

      body ->
        Logger.debug("statecharts: unexpected body format", body: inspect(body))
        Plug.Conn.send_resp(conn, 400, Error.error_body("invalid request body"))
    end
  end

  @doc false
  def open_api_operation(_opts) do
    %Operation{
      operationId: "StatechartsController.create",
      summary: "Register and start a statechart",
      description: "Upload an SCXML AST JSON document, compile it, store the graph, and start a running instance.",
      tags: ["Statecharts"],
      # ---------------------------------------------------------------------------
      # Helpers (mirrored from Router)
      # ---------------------------------------------------------------------------
      requestBody:
        Operation.request_body(
          "SCXML document to register",
          "application/json",
          Schemas.RegisterDocumentRequest
        ),
      responses: %{
        201 => Operation.response("Instance started", "application/json", Schemas.Snapshot),
        400 => Operation.response("Bad request", "application/json", Schemas.Error)
      }
    }
  end

  defp read_json(conn) do
    with {:ok, body, _} <- Plug.Conn.read_body(conn, length: 1_000_000),
         {:ok, decoded} <- Jason.decode(body) do
      {:ok, decoded}
    else
      _ -> {:error, :bad_json}
    end
  end

  # Accept document as a JSON string (e.g. from code) or a nested JSON object
  # (e.g. when copy-pasting the raw fixture). If it's a map, re-encode it.
  defp normalize_document(document) when is_binary(document), do: document
  defp normalize_document(document) when is_map(document), do: Jason.encode!(document)

  defp to_created({:ok, _data} = result) do
    {201, result |> Error.to_json() |> elem(1)}
  end

  defp to_created(result), do: Error.to_json(result)
end
