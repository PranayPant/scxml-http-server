defmodule ScxmlHttpEngine.Engine do
  @moduledoc """
  Thin facade over the `scxml-orchestrator` library's `ScxmlEngine` public API.

  Routes stay declarative and testable; all SCXML-specific concerns
  (JSON parsing ignored here — router passes decoded terms), `MapSet` → list
  conversions, instance-id resolution and result normalization live here.

  Every public function returns an `{:ok, ...}` / `{:error, reason}` tuple so
  the router can map results to HTTP status codes deterministically.
  """

  require Logger

  # Coarse (INFO-level) span wrappers give each flow a named server-side span
  # between the bandit HTTP span and the interpreter spans (which attach to
  # the caller's context — see ScxmlEngine.Instance).
  require OpenTelemetry.Tracer

  @type execution_status :: :idle | :running | :completed | :error

  @type snapshot :: %{
          instance_id: String.t(),
          configuration: [String.t()],
          datamodel: map(),
          done: boolean(),
          execution_status: execution_status(),
          active_states: [map()]
        }

  @doc """
  Load + compile + start an instance from an uploaded AST JSON document.

  `instance_id` is optional: when omitted the library falls back to the graph
  id, which we recover by matching the started pid against running instances.

  Returns `{:ok, snapshot}` or `{:error, reason}`.
  """
  @spec register_and_start(String.t(), String.t() | nil) :: {:ok, snapshot()} | {:error, term()}
  def register_and_start(document, instance_id) do
    OpenTelemetry.Tracer.with_span "engine.register_and_start" do
      Logger.debug("register_and_start: starting", instance_id: instance_id)

      opts = if is_binary(instance_id), do: [instance_id: instance_id], else: []

      try do
        with {:ok, pid} <- ScxmlEngine.run(document, opts) do
          resolved_id = instance_id || instance_id_for_pid(pid)
          Logger.debug("register_and_start: instance started", instance_id: resolved_id)
          snapshot = snapshot_for(resolved_id, pid)
          log_snapshot(:start, resolved_id, nil, snapshot)
          {:ok, snapshot}
        end
      rescue
        # The library raises for structurally-invalid-but-parseable AST JSON
        # (e.g. `%{"scxml" => "garbage"}`). At this HTTP boundary we convert
        # that into a clean {:error, reason} so the router can map it to 400.
        error ->
          Logger.debug("register_and_start: failed", error: inspect(error))
          {:error, error}
      end
    end
  end

  @doc """
  Start an instance against a previously stored graph.

  Returns `{:ok, snapshot}` or `{:error, reason}`.
  """
  @spec start_instance(String.t(), String.t() | nil, map()) :: {:ok, snapshot()} | {:error, term()}
  def start_instance(graph_id, instance_id, initial_datamodel) do
    OpenTelemetry.Tracer.with_span "engine.start_instance" do
      Logger.debug("start_instance: starting", graph_id: graph_id, instance_id: instance_id)

      with {:ok, pid} <-
             ScxmlEngine.start_instance(
               graph_id: graph_id,
               instance_id: instance_id,
               initial_datamodel: initial_datamodel
             ) do
        resolved_id = instance_id || graph_id
        Logger.debug("start_instance: instance started", instance_id: resolved_id)
        {:ok, snapshot_for(resolved_id, pid)}
      end
    end
  end

  @doc """
  Send an event to an instance (synchronous step) and return its settled state.

  Returns `{:ok, snapshot}` or `{:error, :not_found}`.
  """
  @spec step(String.t(), String.t(), term()) :: {:ok, snapshot()} | {:error, :not_found}
  def step(instance_id, event_name, data) do
    OpenTelemetry.Tracer.with_span "engine.step" do
      Logger.debug("step: sending event", instance_id: instance_id, event: event_name)

      data = data || %{}

      with {:ok, pid} <- ScxmlEngine.instance_pid(instance_id),
           :ok <- ScxmlEngine.send_event(pid, event_name, data) do
        Logger.debug("step: event processed", instance_id: instance_id, event: event_name)

        snapshot = snapshot_for(instance_id, pid)
        log_snapshot(:step, instance_id, event_name, snapshot)

        {:ok, snapshot}
      else
        :error ->
          Logger.debug("step: instance not found", instance_id: instance_id)
          {:error, :not_found}
      end
    end
  end

  @doc """
  Snapshot a running instance.

  Returns `{:ok, snapshot}` or `{:error, :not_found}`.
  """
  @spec snapshot(String.t()) :: {:ok, snapshot()} | {:error, :not_found}
  def snapshot(instance_id) do
    OpenTelemetry.Tracer.with_span "engine.snapshot" do
      Logger.debug("snapshot: fetching", instance_id: instance_id)

      case ScxmlEngine.instance_pid(instance_id) do
        {:ok, pid} ->
          Logger.debug("snapshot: fetched", instance_id: instance_id)
          {:ok, snapshot_for(instance_id, pid)}

        _ ->
          Logger.debug("snapshot: instance not found", instance_id: instance_id)
          {:error, :not_found}
      end
    end
  end

  @doc """
  Enumerate all running instances as snapshots.
  """
  @spec list_instances() :: [snapshot()]
  def list_instances do
    OpenTelemetry.Tracer.with_span "engine.list_instances" do
      instances =
        for {id, pid} <- ScxmlEngine.instances() do
          snapshot_for(id, pid)
        end

      Logger.debug("list_instances: returning #{length(instances)} instance(s)")
      instances
    end
  end

  @doc """
  Stop and remove an instance.

  Delegates to `ScxmlEngine.remove_instance/1`, which stops the instance process
  and synchronously deregisters it — once this returns `{:ok, :deleted}` the
  instance is no longer discoverable.

  Returns `{:ok, :deleted}` or `{:error, :not_found}`.
  """
  @spec remove_instance(String.t()) :: {:ok, :deleted} | {:error, :not_found}
  def remove_instance(instance_id) do
    OpenTelemetry.Tracer.with_span "engine.remove_instance" do
      Logger.debug("remove_instance: stopping", instance_id: instance_id)

      case ScxmlEngine.remove_instance(instance_id) do
        :ok ->
          Logger.debug("remove_instance: deleted", instance_id: instance_id)
          {:ok, :deleted}

        :error ->
          Logger.debug("remove_instance: instance not found", instance_id: instance_id)
          {:error, :not_found}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  @doc false

  @spec snapshot_for(String.t(), pid()) :: snapshot()
  defp snapshot_for(instance_id, pid) do
    %{
      instance_id: instance_id,
      configuration: pid |> ScxmlEngine.active_configuration() |> MapSet.to_list(),
      datamodel: ScxmlEngine.datamodel(pid),
      done: ScxmlEngine.done?(pid),
      execution_status: ScxmlEngine.execution_status(pid),
      active_states: ScxmlEngine.active_states(pid)
    }
  end

  # Emit a single structured debug line for a snapshot so the dataplane log is
  # self-contained per step: the event, the post-event configuration, whether
  # the instance is done, and its execution status. This surfaces silent state
  # drift (e.g. an event processed but the config ending up inconsistent) that
  # event-name-only logging cannot reveal.
  @spec log_snapshot(atom(), String.t(), String.t() | nil, snapshot()) :: :ok
  defp log_snapshot(kind, instance_id, event_name, snapshot) do
    Logger.debug("snapshot: #{kind}",
      instance_id: instance_id,
      event: event_name,
      configuration: snapshot.configuration,
      done: snapshot.done,
      execution_status: snapshot.execution_status,
      active_states:
        Enum.map(snapshot.active_states, fn s ->
          %{id: s.id, status: s.status, type: s.type}
        end)
    )

    :ok
  end

  defp instance_id_for_pid(pid) do
    Enum.find_value(ScxmlEngine.instances(), fn {id, p} ->
      if p == pid, do: id
    end)
  end
end
