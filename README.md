# scxml-http-engine

> How an HTTP service would consume the **`scxml-orchestrator`** library to
> actually execute SCXML statecharts.

This document is written from the perspective of a **separate, consumer
project** — an HTTP engine — that depends on the
[`scxml-orchestrator`](https://github.com/PranayPant/scxml-orchestrator)
library. It does **not** modify the library; it layers a transport on top of
`ScxmlEngine`'s public API. The library's own README explicitly scopes out
HTTP/WebSocket/gRPC transports — this repo is where that transport lives.

---

## 1. The mental model

The library is a **library-first, in-process statechart runtime** built on OTP:

```
 HTTP request ─► Phoenix/Plug router ─► ScxmlHttpEngine ─► ScxmlEngine (lib)
                                                  │
                                                  ├─ compiled graph  (:persistent_term)
                                                  ├─ Instance (GenServer) = one running statechart
                                                  └─ Registry (instance_id → pid) + DynamicSupervisor
```

| Library concept | BEAM reality | Lifetime |
| --- | --- | --- |
| **Graph** (compiled statechart) | Stored in `:persistent_term` under a `graph_id` | Long-lived, read-only, shared zero-copy across instances |
| **Instance** | A `ScxmlEngine.Instance` `GenServer` | One per running statechart invocation |
| **External event queue** | The GenServer's mailbox (`GenServer.call`) | Per instance |
| **Registry** | `ScxmlEngine.Registry` maps `instance_id → pid` | Process-wide |

Key design consequences:

- **Stateless by default.** Graphs and instances live in memory. A restart of
  the BEAM node loses all running instances (unless you add persistence).
- **Durability is the transport's job.** If the HTTP engine must survive
  restarts, it persists the active configuration + datamodel itself and
  rehydrates instances on boot.
- **Bulkheads are free.** The `DynamicSupervisor` isolates a crashing instance
  so a bad statechart can't take down the service or other instances.

---

## 2. Deps and supervision

In your `mix.exs`:

```elixir
defp deps do
  [
    {:scxml_orchestrator, path: "../scxml-orchestrator"},  # or a hex/git dep
    {:jason, "~> 1.4"},
    {:plug_cowboy, "~> 2.7"}   # or bandit + plug
  ]
end
```

The library ships an OTP application (`ScxmlOrchestrator.Application`) that
already boots `ScxmlEngine.Registry` + `ScxmlEngine.Instances`. Because it's a
runtime dependency, Mix's application-controller starts it automatically when
the release boots (and `ScxmlOrchestrator.Application` declares
`mod: {ScxmlOrchestrator.Application, []}`, so its supervisor is started by
OTP for you).

Your own supervision tree only needs your web layer:

```elixir
# lib/scxml_http_engine/application.ex
def start(_type, _args) do
  children = [
    ScxmlHttpEngine.Router            # your Plug router (cowboy/bandit)
  ]

  opts = [strategy: :one_for_one, name: ScxmlHttpEngine.Supervisor]
  Supervisor.start_link(children, opts)
end
```

> Do **not** also add `ScxmlOrchestrator.Application` as a child of your own
> supervisor — OTP already starts it as a dependency. If your app boots
> without `:applications` inference (e.g. explicit release config), add
> `:scxml_orchestrator` to your app's `extra_applications` instead.

---

## 3. Public API you'll drive

All calls are synchronous ("step") semantics — `send_event/3` returns once the
full macrostep has settled, so a single HTTP request yields a deterministic
post-state.

```elixir
# --- Load + compile + start in one go ---
{:ok, pid} = ScxmlEngine.run(ast_json, instance_id: "traffic_1")

# --- Drive with an event (synchronous step) ---
:ok = ScxmlEngine.send_event(pid, "next", %{"lane" => "north"})

# --- Inspect ---
active = ScxmlEngine.active_configuration(pid)   # MapSet of state ids
data   = ScxmlEngine.datamodel(pid)              # map
done   = ScxmlEngine.done?(pid)                  # true when finished

# --- Route by id ---
{:ok, pid} = ScxmlEngine.instance_pid("traffic_1")
:ok = ScxmlEngine.send_event_to("traffic_1", "next")
[{id, pid}] = ScxmlEngine.instances()            # all running instances

# --- Lower-level split (compile once, run many) ---
{:ok, graph} = ScxmlEngine.load(ast_json)
{:ok, graph_id} = ScxmlEngine.store(graph, "traffic")         # store once
{:ok, pid} = ScxmlEngine.start_instance(graph_id: "traffic", instance_id: "x")
```

| Function | HTTP role |
| --- | --- |
| `ScxmlEngine.run/2` | `POST /statecharts` (register + start) |
| `ScxmlEngine.start_instance/1` | start an instance against a pre-stored graph |
| `ScxmlEngine.store/2` | upload / pre-compile a statechart definition |
| `ScxmlEngine.send_event_to/3` | `POST /instances/:id/events` |
| `ScxmlEngine.active_configuration/1` | `GET /instances/:id` snapshot |
| `ScxmlEngine.datamodel/1` | inspect datamodel |
| `ScxmlEngine.done?/1` | terminal-state detection |
| `ScxmlEngine.instance_pid/1`, `instances/0` | routing / list endpoints |

---

## 4. Serialization notes (what the wire format is NOT)

The library consumes the **parser AST JSON**, not SCXML source. Events and
datamodel values are regular Elixir terms; over HTTP you'll `Jason.decode!`/
`Jason.encode!` them.

- **Payload shape:** `send_event(pid, name, payload)` wraps payload as
  `%{"name" => name, "data" => payload}` internally (available as `_event`
  in the datamodel). So an HTTP body like `{"name": "next", "data": {...}}`
  maps naturally.
- **Active configuration** comes back as a `MapSet` — encode it as a JSON
  array for the client.
- **Errors:** `ScxmlEngine.run/2` returns `{:error, reason}` (e.g. invalid
  JSON, unknown graph id). Map those to HTTP 4xx/5xx.

---

## 5. Reference: a minimal Plug router

```elixir
defmodule ScxmlHttpEngine.Router do
  use Plug.Router
  plug :match
  plug :dispatch

  # Register + start an instance from an uploaded AST JSON document.
  # Body: {"document": <AST JSON object>, "instance_id": "my-id" (optional)}
  post "/statecharts" do
    with {:ok, body, _} <- read_body(conn),
         {:ok, instance_id} <- start(body) do
      pid = fetch_pid!(instance_id)
      send_resp(conn, 201, Jason.encode!(%{instance_id: instance_id,
                                            configuration: ScxmlEngine.active_configuration(pid) |> MapSet.to_list()}))
    else
      {:error, reason} -> send_resp(conn, 400, Jason.encode!(%{error: inspect(reason)}))
    end
  end

  # Send an event (synchronous "step").
  post "/instances/:id/events" do
    with {:ok, body, _} <- read_body(conn),
         %{"name" => name, "data" => data} <- Jason.decode!(body),
         :ok <- ScxmlEngine.send_event_to(id, name, data || %{}) do
      pid = fetch_pid!(id)
      send_resp(conn, 200, Jason.encode!(%{configuration: ScxmlEngine.active_configuration(pid) |> MapSet.to_list(),
                                            datamodel: ScxmlEngine.datamodel(pid),
                                            done: ScxmlEngine.done?(pid)}))
    else
      _ -> send_resp(conn, 404, Jason.encode!(%{error: "instance not found or bad event"}))
    end
  end

  # Snapshot an instance.
  get "/instances/:id" do
    case ScxmlEngine.instance_pid(id) do
      {:ok, pid} ->
        send_resp(conn, 200, Jason.encode!(%{configuration: ScxmlEngine.active_configuration(pid) |> MapSet.to_list(),
                                             datamodel: ScxmlEngine.datamodel(pid),
                                             done: ScxmlEngine.done?(pid)}))
      _ ->
        send_resp(conn, 404, Jason.encode!(%{error: "instance not found"}))
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  # ---- Helpers ---------------------------------------------------------

  # Parse the body, extract the embedded AST JSON document and an optional
  # instance_id, then load+store+start the instance via the library.
  # (instance_id is optional — the library falls back to the graph id, which
  # we recover here by matching the started pid against ScxmlEngine.instances/0.)
  defp start(body) do
    decoded = Jason.decode!(body)
    doc = Map.fetch!(decoded, "document")
    requested_id = Map.get(decoded, "instance_id")

    with {:ok, pid} <- ScxmlEngine.run(Jason.encode!(doc), instance_id: requested_id) do
      resolved_id = requested_id || instance_id_for_pid(pid)
      {:ok, resolved_id}
    end
  end

  defp instance_id_for_pid(pid) do
    Enum.find_value(ScxmlEngine.instances(), fn {id, p} ->
      if p == pid, do: id
    end)
  end

  defp fetch_pid!(instance_id) do
    {:ok, pid} = ScxmlEngine.instance_pid(instance_id)
    pid
  end
end
```

> **Note on concurrency:** each `send_event_to` is a blocking `GenServer.call`
> that does the work on the instance process. A slow statechart (or lots of
> `raise`-internal events) will hold that one instance's mailbox but not the
> whole server — other instances keep stepping independently.

---

## 6. Lifecycle & durability (doing it "for real")

The library is **in-memory**. If your HTTP engine must survive reboots or
scale horizontally, treat this as a first-class design concern:

1. **Snapshot on every macrostep.** After each `send_event`, persist
   `{instance_id, active_configuration, datamodel, graph_id}` to Postgres /
   Redis / DETS. Because the library returns a settled state synchronously,
   you always have a consistent checkpoint to write.
2. **Rehydrate on boot.** On startup, reconstruct stored instances:
   ```elixir
   for {id, snapshot} <- load_snapshots() do
     {:ok, pid} = ScxmlEngine.run(snapshot.ast_json, instance_id: id,
                                   initial_datamodel: snapshot.datamodel)
   end
   ```
   (This restores the configuration from the initial entry, which is correct
   only if you save graphs + datamodel. If you need to restore mid-config,
   you'd extend the library or replay the event log.)
3. **Long-lived graphs:** `store/2` the compiled graph once and reference it
   by `graph_id` from many instances — compiled graphs live in
   `:persistent_term` and are shared zero-copy.

---

## 7. Distribution (optional)

For horizontal scale beyond one node:

- Swap `ScxmlEngine.Registry` for `Horde.Registry` and the instance supervisor
  for `Horde.DynamicSupervisor` (the ARCHITECTURE doc calls this out). The
  `send_event_to/3` routing layer is the seam to make node-aware.

---

## 8. Suggested endpoint surface

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/statecharts` | Upload AST JSON, store graph, start an instance |
| `GET` | `/statecharts/:graphId` | List/describe a stored graph |
| `POST` | `/instances` | Start a new instance from a stored `graphId` |
| `GET` | `/instances/:id` | Snapshot (configuration, datamodel, done?) |
| `POST` | `/instances/:id/events` | Send an event, return settled state |
| `DELETE` | `/instances/:id` | Stop and remove an instance |
| `GET` | `/instances` | Enumerate running instances |

Happy statecharting. 🤖
