defmodule ScxmlHttpEngine.Handlers.Instances do
  @moduledoc """
  Handlers for the `/instances` resource.

  Routes:
    - `POST /instances` â€” start an instance from a stored graph.
    - `GET /instances/:id` â€” snapshot an instance.
    - `POST /instances/:id/events` â€” send an event (synchronous step).
    - `DELETE /instances/:id` â€” stop and remove an instance.
    - `GET /instances` â€” enumerate all running instances.
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
  def call(conn, opts) do
    action = Keyword.get(opts, :action, :create)

    case action do
      :create -> create(conn, opts)
      :show -> show(conn, opts)
      :event -> event(conn, opts)
      :delete -> delete(conn, opts)
      :index -> index(conn, opts)
    end
  end

  @doc false
  def open_api_operation(opts) do
    action = Keyword.get(opts, :action, :create)

    case action do
      :create -> create_operation()
      :show -> show_operation()
      :event -> event_operation()
      :delete -> delete_operation()
      :index -> index_operation()
    end
  end

  # ---------------------------------------------------------------------------
  # Action handlers
  # ---------------------------------------------------------------------------

  defp create(conn, _opts) do
    with {:ok, body} <- read_json(conn),
         %{"graph_id" => graph_id} when is_binary(graph_id) <- body do
      initial_datamodel = body["initial_datamodel"] || %{}
      Logger.info("instances: starting instance", graph_id: graph_id, instance_id: body["instance_id"])
      result = Engine.start_instance(graph_id, body["instance_id"], initial_datamodel)
      {status, payload} = to_created(result)
      Plug.Conn.send_resp(conn, status, payload)
    else
      _ -> Plug.Conn.send_resp(conn, 400, Error.error_body("invalid request body"))
    end
  end

  defp show(conn, _opts) do
    instance_id = conn.path_params["id"]
    {status, payload} = Error.to_json(Engine.snapshot(instance_id))
    Plug.Conn.send_resp(conn, status, payload)
  end

  defp event(conn, _opts) do
    instance_id = conn.path_params["id"]

    with {:ok, body} <- read_json(conn),
         %{"name" => name} when is_binary(name) <- body do
      result = Engine.step(instance_id, name, body["data"])
      {status, payload} = Error.to_json(result)
      Plug.Conn.send_resp(conn, status, payload)
    else
      _ -> Plug.Conn.send_resp(conn, 400, Error.error_body("invalid request body"))
    end
  end

  defp delete(conn, _opts) do
    instance_id = conn.path_params["id"]
    {status, payload} = Error.to_json(Engine.remove_instance(instance_id))
    Plug.Conn.send_resp(conn, status, payload)
  end

  defp index(conn, _opts) do
    {status, payload} = Error.to_json({:ok, Engine.list_instances()})
    Plug.Conn.send_resp(conn, status, payload)
  end

  # ---------------------------------------------------------------------------
  # OpenAPI operation specs
  # ---------------------------------------------------------------------------

  defp create_operation do
    %Operation{
      operationId: "InstancesController.create",
      summary: "Start an instance from a stored graph",
      description: "Start a new running instance from a previously stored graph, optionally with an initial datamodel.",
      tags: ["Instances"],
      requestBody:
        Operation.request_body(
          "Graph ID and optional instance ID + initial datamodel",
          "application/json",
          Schemas.StartInstanceRequest
        ),
      responses: %{
        201 => Operation.response("Instance started", "application/json", Schemas.Snapshot),
        400 => Operation.response("Bad request", "application/json", Schemas.Error)
      }
    }
  end

  defp show_operation do
    %Operation{
      operationId: "InstancesController.show",
      summary: "Get instance snapshot",
      description:
        "Returns the current snapshot of a running statechart instance, including its configuration, datamodel, execution status, and active states.",
      tags: ["Instances"],
      parameters: [
        Operation.parameter(:id, :path, %OpenApiSpex.Schema{type: :string}, "Instance ID",
          required: true,
          example: "my-instance"
        )
      ],
      responses: %{
        200 => Operation.response("Instance snapshot", "application/json", Schemas.Snapshot),
        404 => Operation.response("Not found", "application/json", Schemas.Error)
      }
    }
  end

  defp event_operation do
    %Operation{
      operationId: "InstancesController.event",
      summary: "Send an event to an instance",
      description:
        "Send an event to a running statechart instance. The event is processed synchronously and the updated snapshot is returned.",
      tags: ["Instances"],
      parameters: [
        Operation.parameter(:id, :path, %OpenApiSpex.Schema{type: :string}, "Instance ID",
          required: true,
          example: "my-instance"
        )
      ],
      requestBody:
        Operation.request_body(
          "Event to send",
          "application/json",
          Schemas.EventRequest
        ),
      responses: %{
        200 => Operation.response("Updated snapshot", "application/json", Schemas.Snapshot),
        400 => Operation.response("Bad request", "application/json", Schemas.Error),
        404 => Operation.response("Not found", "application/json", Schemas.Error)
      }
    }
  end

  defp delete_operation do
    %Operation{
      operationId: "InstancesController.delete",
      summary: "Stop and remove an instance",
      description: "Stops a running statechart instance and removes it from the registry.",
      tags: ["Instances"],
      parameters: [
        Operation.parameter(:id, :path, %OpenApiSpex.Schema{type: :string}, "Instance ID",
          required: true,
          example: "my-instance"
        )
      ],
      responses: %{
        200 => Operation.response("Deleted", "application/json", Schemas.DeletedResponse),
        404 => Operation.response("Not found", "application/json", Schemas.Error)
      }
    }
  end

  defp index_operation do
    %Operation{
      operationId: "InstancesController.index",
      summary: "List running instances",
      description: "Returns a list of all currently running statechart instances.",
      tags: ["Instances"],
      responses: %{
        200 => Operation.response("Running instances", "application/json", Schemas.InstanceList)
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Helpers (mirrored from Router)
  # ---------------------------------------------------------------------------

  defp read_json(conn) do
    with {:ok, body, _} <- Plug.Conn.read_body(conn, length: 1_000_000),
         {:ok, decoded} <- Jason.decode(body) do
      {:ok, decoded}
    else
      _ -> {:error, :bad_json}
    end
  end

  defp to_created({:ok, _data} = result) do
    {201, result |> Error.to_json() |> elem(1)}
  end

  defp to_created(result), do: Error.to_json(result)
end
