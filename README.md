# scxml-http-engine

> HTTP transport layer for the **`scxml-orchestrator`** runtime. Execute SCXML
> statecharts over HTTP with a built-in OpenAPI spec and Swagger UI.

Layers a Plug/Cowboy transport on top of
[`scxml-orchestrator`](https://github.com/PranayPant/scxml-orchestrator)'s
public API. The library's own README explicitly scopes out HTTP/WebSocket/gRPC
transports — this repo is where that transport lives.

---

## 1. Quick start

```bash
# Build and run with Docker
docker build -t scxml-http-engine .
docker run --rm -p 4000:4000 -e SCXML_HTTP_ENGINE_PORT=4000 scxml-http-engine

# Try it
curl http://localhost:4000/healthz          # → "ok"
curl http://localhost:4000/openapi           # → OpenAPI 3.0 spec
open http://localhost:4000/swaggerui         # → Swagger UI
```

---

## 1.5. Developer experience — hot reloading

During development, the app uses **Docker Compose Watch** with a **request-driven
compilation** strategy for instant code reload without restarting the container.

```bash
docker compose up --watch
```

This syncs your `./lib` and `./config` directories into the running container
and triggers a full image rebuild only when `mix.exs` or `mix.lock` change. A
`CodeReloader` plug recompiles freshly synced `.ex` files on every HTTP request
in `:dev` mode, so you just refresh your browser or re-curl to pick up changes.

| File                                     | Role                                              |
| ---------------------------------------- | ------------------------------------------------- |
| `lib/scxml_http_engine/code_reloader.ex` | `Plug` that runs `compile.elixir` on each request |
| `Dockerfile` (stage `dev`)               | `MIX_ENV=dev`, `CMD ["mix", "run", "--no-halt"]`  |
| `docker-compose.yml`                     | `target: dev`, `develop.watch` sync/rebuild rules |

---

## 2. Endpoint surface

| Method   | Path                    | Description                                                          | Request body                                                              |
| -------- | ----------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `GET`    | `/healthz`              | Liveness probe                                                       | —                                                                         |
| `POST`   | `/statecharts`          | Upload AST JSON, store graph, start an instance                      | `{"document": "<SCXML AST JSON>", "instance_id"?: "..."}`                 |
| `POST`   | `/instances`            | Start an instance from a stored graph                                | `{"graph_id": "...", "instance_id"?: "...", "initial_datamodel"?: {...}}` |
| `GET`    | `/instances/:id`        | Snapshot (configuration, datamodel, active_states, execution_status) | —                                                                         |
| `POST`   | `/instances/:id/events` | Send an event, return settled state                                  | `{"name": "next", "data"?: {...}}`                                        |
| `DELETE` | `/instances/:id`        | Stop and remove an instance                                          | —                                                                         |
| `GET`    | `/instances`            | Enumerate all running instances                                      | —                                                                         |
| `GET`    | `/openapi`              | OpenAPI 3.0 specification (JSON)                                     | —                                                                         |
| `GET`    | `/swaggerui`            | Swagger UI documentation browser                                     | —                                                                         |

The full schema is available interactively at `/swaggerui` or as a raw JSON
spec at `/openapi`.

---

## 3. Project structure

```
lib/
├── scxml_http_engine.ex                    # top-level module alias
├── scxml_http_engine/
│   ├── application.ex                      # OTP application (Plug.Cowboy child)
│   ├── router.ex                           # Plug.Router — route matching + delegation
│   ├── engine.ex                           # Facade over ScxmlEngine public API
│   ├── error.ex                            # {:ok,_}/{:error,_} → HTTP response helpers
│   ├── handlers/
│   │   ├── healthz.ex                      # GET /healthz
│   │   ├── statecharts.ex                  # POST /statecharts
│   │   └── instances.ex                    # all /instances routes (CRUD + event)
│   └── open_api/
│       ├── api_spec.ex                     # OpenApiSpex.OpenApi behaviour
│       └── schemas.ex                      # Request/response schema definitions
```

### Architecture overview

```
 HTTP request ─► Plug.Router ─► Handler modules ─► ScxmlHttpEngine.Engine ─► ScxmlEngine (lib)
                    │                                                              │
                    ├─ PutApiSpec (OpenAPI)                                         ├─ compiled graph  (:persistent_term)
                    ├─ /openapi → RenderSpec                                        ├─ Instance (GenServer)
                    └─ /swaggerui → SwaggerUI                                       └─ Registry + DynamicSupervisor
```

---

## 4. The mental model

The library is a **library-first, in-process statechart runtime** built on OTP:

| Library concept                 | BEAM reality                                    | Lifetime                                                 |
| ------------------------------- | ----------------------------------------------- | -------------------------------------------------------- |
| **Graph** (compiled statechart) | Stored in `:persistent_term` under a `graph_id` | Long-lived, read-only, shared zero-copy across instances |
| **Instance**                    | A `ScxmlEngine.Instance` `GenServer`            | One per running statechart invocation                    |
| **External event queue**        | The GenServer's mailbox (`GenServer.call`)      | Per instance                                             |
| **Registry**                    | `ScxmlEngine.Registry` maps `instance_id → pid` | Process-wide                                             |

Key design consequences:

- **Stateless by default.** Graphs and instances live in memory. A restart of
  the BEAM node loses all running instances (unless you add persistence).
- **Durability is the transport's job.** If the HTTP engine must survive
  restarts, it persists the active configuration + datamodel itself and
  rehydrates instances on boot.
- **Bulkheads are free.** The `DynamicSupervisor` isolates a crashing instance
  so a bad statechart can't take down the service or other instances.

---

## 5. Deps and supervision

The engine depends on `scxml-orchestrator`, `plug_cowboy`, `jason`, and
`open_api_spex`:

```elixir
defp deps do
  [
    {:scxml_orchestrator, path: "../scxml-orchestrator"},  # or hex/git
    {:jason, "~> 1.4"},
    {:plug_cowboy, "~> 2.7"},
    {:open_api_spex, "~> 3.19"}
  ]
end
```

The library ships an OTP application (`ScxmlOrchestrator.Application`) that
already boots `ScxmlEngine.Registry` + `ScxmlEngine.Instances`. Because it's a
runtime dependency, Mix's application-controller starts it automatically when
the release boots (and `ScxmlOrchestrator.Application` declares
`mod: {ScxmlOrchestrator.Application, []}`, so its supervisor is started by
OTP for you).

Your own supervision tree only needs the web layer:

```elixir
# lib/scxml_http_engine/application.ex
def start(_type, _args) do
  port = Application.get_env(:scxml_http_engine, ScxmlHttpEngine.Router, [])[:port] || 4000

  children = [
    {Plug.Cowboy, scheme: :http, plug: ScxmlHttpEngine.Router, options: [port: port]}
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

## 6. Public API you'll drive

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

| Function                                    | HTTP role                                    |
| ------------------------------------------- | -------------------------------------------- |
| `ScxmlEngine.run/2`                         | `POST /statecharts` (register + start)       |
| `ScxmlEngine.start_instance/1`              | start an instance against a pre-stored graph |
| `ScxmlEngine.store/2`                       | upload / pre-compile a statechart definition |
| `ScxmlEngine.send_event_to/3`               | `POST /instances/:id/events`                 |
| `ScxmlEngine.active_configuration/1`        | `GET /instances/:id` snapshot                |
| `ScxmlEngine.datamodel/1`                   | inspect datamodel                            |
| `ScxmlEngine.done?/1`                       | terminal-state detection                     |
| `ScxmlEngine.instance_pid/1`, `instances/0` | routing / list endpoints                     |

---

## 7. Serialization notes (what the wire format is NOT)

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

## 8. Lifecycle & durability (doing it "for real")

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

## 9. Distribution (optional)

For horizontal scale beyond one node:

- Swap `ScxmlEngine.Registry` for `Horde.Registry` and the instance supervisor
  for `Horde.DynamicSupervisor` (the ARCHITECTURE doc calls this out). The
  `send_event_to/3` routing layer is the seam to make node-aware.

---

Happy statecharting. 🤖
