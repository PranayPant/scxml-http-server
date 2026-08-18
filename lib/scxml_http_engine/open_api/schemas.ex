defmodule ScxmlHttpEngine.OpenApi.Schemas do
  @moduledoc """
  OpenAPI request/response schema modules for the HTTP engine API.

  Each schema module implements the `OpenApiSpex.Schema` behaviour.
  """

  alias OpenApiSpex.Schema

  defmodule Error do
    @moduledoc "Error response body."
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Error",
      description: "An error response",
      type: :object,
      properties: %{
        error: %Schema{type: :string, description: "Error message"}
      },
      required: [:error]
    })
  end

  defmodule EventRequest do
    @moduledoc "Request body for sending an event to an instance."
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "EventRequest",
      description: "Event to send to a statechart instance",
      type: :object,
      properties: %{
        name: %Schema{
          type: :string,
          description: "Event name (e.g. \"next\")"
        },
        data: %Schema{
          type: :object,
          description: "Optional event payload data",
          nullable: true
        }
      },
      required: [:name]
    })
  end

  defmodule StateInfo do
    @moduledoc "Execution status of a single active state."
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "StateInfo",
      description: "A state's execution status",
      type: :object,
      properties: %{
        id: %Schema{type: :string, description: "State ID"},
        status: %Schema{
          type: :string,
          description: "Execution status",
          enum: ["running", "completed", "error"]
        },
        type: %Schema{
          type: :string,
          description: "State type",
          enum: ["atomic", "compound", "parallel", "final", "history"]
        }
      },
      required: [:id, :status, :type]
    })
  end

  defmodule Snapshot do
    @moduledoc "Snapshot of a statechart instance."
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Snapshot",
      description: "Current state of a statechart instance",
      type: :object,
      properties: %{
        instance_id: %Schema{type: :string, description: "Unique instance identifier"},
        configuration: %Schema{
          type: :array,
          description: "Active state configuration",
          items: %Schema{type: :string}
        },
        datamodel: %Schema{
          type: :object,
          description: "Current datamodel",
          nullable: true
        },
        done: %Schema{
          type: :boolean,
          description: "Whether the instance has reached a terminal state"
        },
        execution_status: %Schema{
          type: :string,
          description: "Overall execution status of the instance",
          enum: ["idle", "running", "completed", "error"]
        },
        active_states: %Schema{
          type: :array,
          description: "Per-state execution statuses",
          items: StateInfo
        }
      },
      required: [:instance_id, :configuration, :done, :execution_status, :active_states]
    })
  end

  defmodule InstanceList do
    @moduledoc "List of running instance snapshots."
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "InstanceList",
      description: "List of running instances",
      type: :array,
      items: Snapshot
    })
  end

  defmodule RegisterDocumentRequest do
    @moduledoc "Request body for registering a new statechart document."
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RegisterDocumentRequest",
      description: "Upload a statechart document and optionally start an instance",
      type: :object,
      properties: %{
        document: %Schema{
          type: :string,
          description: "SCXML AST JSON (as a string or a nested JSON object)"
        },
        instance_id: %Schema{
          type: :string,
          description: "Optional instance identifier",
          nullable: true
        }
      },
      required: [:document]
    })
  end

  defmodule StartInstanceRequest do
    @moduledoc "Request body for starting an instance from a stored graph."
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "StartInstanceRequest",
      description: "Start a new instance from a previously stored graph",
      type: :object,
      properties: %{
        graph_id: %Schema{type: :string, description: "ID of the stored graph"},
        instance_id: %Schema{
          type: :string,
          description: "Optional instance identifier",
          nullable: true
        },
        initial_datamodel: %Schema{
          type: :object,
          description: "Optional initial datamodel",
          nullable: true
        }
      },
      required: [:graph_id]
    })
  end

  defmodule DeletedResponse do
    @moduledoc "Response after deleting an instance."
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DeletedResponse",
      description: "Confirmation that an instance was deleted",
      type: :object,
      properties: %{
        deleted: %Schema{type: :boolean, description: "Whether the instance was deleted"}
      },
      required: [:deleted]
    })
  end
end
