defmodule ScxmlHttpEngine.Router do
  @moduledoc """
  The HTTP transport / routing layer.

  Exposes the statechart engine over HTTP. All statechart handling is delegated
  to `ScxmlHttpEngine.Engine`; this module only matches routes, reads JSON
  bodies and maps results to status codes via `ScxmlHttpEngine.Error`.

  See `IMPLEMENTATION-PLAN.md` for the endpoint design and `README §8` for the
  intended route surface.
  """

  use Plug.Router

  alias ScxmlHttpEngine.Engine
  alias ScxmlHttpEngine.Error

  plug(:match)
  plug(:dispatch)

  # Liveness probe for load balancers / orchestrators.
  get "/healthz" do
    send_resp(conn, 200, "ok")
  end

  # Register + start an instance from an uploaded AST JSON document.
  # Body: {"document": <AST JSON string>, "instance_id"?: "my-id"}
  post "/statecharts" do
    with {:ok, body} <- read_json(conn),
         %{"document" => document} when is_binary(document) <- body do
      result = Engine.register_and_start(document, body["instance_id"])
      {status, payload} = to_created(result)
      send_resp(conn, status, payload)
    else
      _ -> send_resp(conn, 400, Error.error_body("invalid request body"))
    end
  end

  # Start an instance from a stored graph.
  # Body: {"graph_id": "g", "instance_id"?: "x", "initial_datamodel"?: {...}}
  post "/instances" do
    with {:ok, body} <- read_json(conn),
         %{"graph_id" => graph_id} when is_binary(graph_id) <- body do
      initial_datamodel = body["initial_datamodel"] || %{}
      result = Engine.start_instance(graph_id, body["instance_id"], initial_datamodel)
      {status, payload} = to_created(result)
      send_resp(conn, status, payload)
    else
      _ -> send_resp(conn, 400, Error.error_body("invalid request body"))
    end
  end

  # Snapshot an instance.
  get "/instances/:id" do
    {status, payload} = Error.to_json(Engine.snapshot(id))
    send_resp(conn, status, payload)
  end

  # Send an event (synchronous "step") and return the settled state.
  # Body: {"name": "next", "data": {...}}
  post "/instances/:id/events" do
    with {:ok, body} <- read_json(conn),
         %{"name" => name} when is_binary(name) <- body do
      result = Engine.step(id, name, body["data"])
      {status, payload} = Error.to_json(result)
      send_resp(conn, status, payload)
    else
      _ -> send_resp(conn, 400, Error.error_body("invalid request body"))
    end
  end

  # Stop and remove an instance.
  delete "/instances/:id" do
    {status, payload} = Error.to_json(Engine.remove_instance(id))
    send_resp(conn, status, payload)
  end

  # Enumerate all running instances.
  get "/instances" do
    {status, payload} = Error.to_json({:ok, Engine.list_instances()})
    send_resp(conn, status, payload)
  end

  match _ do
    send_resp(conn, 404, Error.error_body("not found"))
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # POST handlers return 201 on success; GET/DELETE return 200.
  defp to_created({:ok, _data} = result) do
    {201, result |> Error.to_json() |> elem(1)}
  end

  defp to_created(result), do: Error.to_json(result)

  @doc false
  def read_json(conn) do
    with {:ok, body, _} <- read_body(conn, length: 1_000_000),
         {:ok, decoded} <- Jason.decode(body) do
      {:ok, decoded}
    else
      _ -> {:error, :bad_json}
    end
  end
end
