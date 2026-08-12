defmodule ScxmlHttpEngine.Engine do
  @moduledoc """
  Thin facade over the `scxml-orchestrator` library's `ScxmlEngine` public API.

  Routes stay declarative and testable; all SCXML-specific concerns
  (JSON parsing ignored here — router passes decoded terms), `MapSet` → list
  conversions, instance-id resolution and result normalization live here.

  Every public function returns an `{:ok, ...}` / `{:error, reason}` tuple so
  the router can map results to HTTP status codes deterministically.
  """

  @type snapshot :: %{instance_id: String.t(), configuration: [String.t()], datamodel: map(), done: boolean()}

  @doc """
  Load + compile + start an instance from an uploaded AST JSON document.

  `instance_id` is optional: when omitted the library falls back to the graph
  id, which we recover by matching the started pid against running instances.

  Returns `{:ok, snapshot}` or `{:error, reason}`.
  """
  @spec register_and_start(String.t(), String.t() | nil) :: {:ok, snapshot()} | {:error, term()}
  def register_and_start(document, instance_id) do
    opts = if is_binary(instance_id), do: [instance_id: instance_id], else: []

    try do
      with {:ok, pid} <- ScxmlEngine.run(document, opts) do
        resolved_id = instance_id || instance_id_for_pid(pid)
        {:ok, snapshot_for(resolved_id, pid)}
      end
    rescue
      # The library raises for structurally-invalid-but-parseable AST JSON
      # (e.g. `%{"scxml" => "garbage"}`). At this HTTP boundary we convert
      # that into a clean {:error, reason} so the router can map it to 400.
      error -> {:error, error}
    end
  end

  @doc """
  Start an instance against a previously stored graph.

  Returns `{:ok, snapshot}` or `{:error, reason}`.
  """
  @spec start_instance(String.t(), String.t() | nil, map()) :: {:ok, snapshot()} | {:error, term()}
  def start_instance(graph_id, instance_id, initial_datamodel) do
    with {:ok, pid} <-
           ScxmlEngine.start_instance(
             graph_id: graph_id,
             instance_id: instance_id,
             initial_datamodel: initial_datamodel
           ) do
      resolved_id = instance_id || graph_id
      {:ok, snapshot_for(resolved_id, pid)}
    end
  end

  @doc """
  Send an event to an instance (synchronous step) and return its settled state.

  Returns `{:ok, snapshot}` or `{:error, :not_found}`.
  """
  @spec step(String.t(), String.t(), term()) :: {:ok, snapshot()} | {:error, :not_found}
  def step(instance_id, event_name, data) do
    data = data || %{}

    with {:ok, pid} <- ScxmlEngine.instance_pid(instance_id),
         :ok <- ScxmlEngine.send_event(pid, event_name, data) do
      {:ok, snapshot_for(instance_id, pid)}
    else
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Snapshot a running instance.

  Returns `{:ok, snapshot}` or `{:error, :not_found}`.
  """
  @spec snapshot(String.t()) :: {:ok, snapshot()} | {:error, :not_found}
  def snapshot(instance_id) do
    case ScxmlEngine.instance_pid(instance_id) do
      {:ok, pid} -> {:ok, snapshot_for(instance_id, pid)}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Enumerate all running instances as snapshots.
  """
  @spec list_instances() :: [snapshot()]
  def list_instances do
    for {id, pid} <- ScxmlEngine.instances() do
      snapshot_for(id, pid)
    end
  end

  @doc """
  Stop and remove an instance.

  Terminating the instance process auto-unregisters it from the library's
  registry (the entry is keyed to the process).

  Returns `{:ok, :deleted}` or `{:error, :not_found}`.
  """

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  @spec remove_instance(String.t()) :: {:ok, :deleted} | {:error, :not_found}
  def remove_instance(instance_id) do
    case ScxmlEngine.instance_pid(instance_id) do
      {:ok, pid} ->
        GenServer.stop(pid)
        wait_until_unregistered(instance_id)
        {:ok, :deleted}

      _ ->
        {:error, :not_found}
    end
  end

  # GenServer.stop/3 is synchronous for the process itself, but the library
  # registry removes the entry asynchronously on the owner's DOWN. Poll briefly
  # so the "removed" contract holds immediately after this call returns.
  #
  # Public with @doc false solely so the defensive timeout branch (attempts == 0)
  # can be exercised directly by the test suite.
  @doc false
  @spec wait_until_unregistered(String.t(), pos_integer()) :: :ok
  def wait_until_unregistered(instance_id, attempts \\ 50)

  def wait_until_unregistered(_instance_id, 0), do: :ok

  def wait_until_unregistered(instance_id, attempts) do
    case ScxmlEngine.instance_pid(instance_id) do
      {:ok, _pid} ->
        Process.sleep(10)
        wait_until_unregistered(instance_id, attempts - 1)

      _ ->
        :ok
    end
  end

  defp snapshot_for(instance_id, pid) do
    %{
      instance_id: instance_id,
      configuration: pid |> ScxmlEngine.active_configuration() |> MapSet.to_list(),
      datamodel: ScxmlEngine.datamodel(pid),
      done: ScxmlEngine.done?(pid)
    }
  end

  defp instance_id_for_pid(pid) do
    Enum.find_value(ScxmlEngine.instances(), fn {id, p} ->
      if p == pid, do: id
    end)
  end
end
