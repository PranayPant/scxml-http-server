# Implementation Plan

This document plans the HTTP engine implementation once the scaffolding +
pre-commit pipeline are in place. It drives the `ScxmlHttpEngine` transport on
top of the `scxml-orchestrator` library's `ScxmlEngine` public API.

> **STATUS: full implementation + tests + CI pipeline complete (2026-08-15).**
> The endpoints below are implemented and verified (see §8). All contract-layer
> tests are written at 100% coverage. Remaining future work: durability/snapshot
> persistence and Horde distribution.

## 0. Confirmed library API (from `scxml-orchestrator` `lib/scxml_engine.ex`)

| Function                 | Signature                                                   | Notes                                                   |
| ------------------------ | ----------------------------------------------------------- | ------------------------------------------------------- |
| `run/2`                  | `run(ast_json, opts)` → `{:ok, pid} \| {:error, term}`      | load+store+start in one go                              |
| `load/1`                 | `load(json)` → `{:ok, graph}`                               | parse AST JSON                                          |
| `store/2`                | `store(graph, graph_id \\ nil)` → `{:ok, graph_id}`         | compile + persist graph                                 |
| `start_instance/1`       | `start_instance(opts)` → `{:ok, pid} \| :error`             | opts: `:graph_id`, `:instance_id`, `:initial_datamodel` |
| `send_event/3`           | `send_event(pid, name, payload \\ %{})` → `:ok`             | synchronous step by pid                                 |
| `send_event_to/3`        | `send_event_to(id, name, payload \\ %{})` → `:ok \| :error` | route by instance id                                    |
| `instance_pid/1`         | `instance_pid(id)` → `{:ok, pid} \| :error \| nil`          | registry lookup                                         |
| `active_configuration/1` | `active_configuration(pid)` → `MapSet.t`                    | encode as JSON array                                    |
| `datamodel/1`            | `datamodel(pid)` → `map`                                    |                                                         |
| `done?/1`                | `done?(pid)` → `boolean`                                    | terminal-state detection                                |
| `instances/0`            | `instances()` → `[{id, pid}]`                               | enumerate                                               |

## 1. Module layout

```
lib/scxml_http_engine/
  application.ex       # starts Plug.Cowboy + Router
  router.ex            # route dispatch — wired to handler modules
  engine.ex            # thin facade over ScxmlEngine (serialization, errors)
  error.ex             # maps Engine results to HTTP status + JSON body
  tracer.ex            # custom tracing plug: OTel metadata, request logging, quiet paths
  code_reloader.ex     # dev-only request-driven compilation (ignored from coverage)
  handlers/
    healthz.ex         # GET /healthz
    instances.ex       # GET/POST/DELETE /instances, POST /instances/:id/events
    statecharts.ex     # POST /statecharts
  open_api/
    api_spec.ex        # OpenAPI 3.0 spec (OpenApiSpex)
    schemas.ex         # nested schema modules: Error, EventRequest, Snapshot, etc.
```

Keep the router thin: route matching + plug boilerplate lives in `router.ex`;
SCXML-specific logic (MapSet→array, error mapping, JSON payload handling) lives
in a small `Engine` facade so routes stay declarative and testable.

## 2. Endpoint surface (matches README §8)

| Method   | Path                    | Flow                                                                      | Success                                | Errors                   |
| -------- | ----------------------- | ------------------------------------------------------------------------- | -------------------------------------- | ------------------------ |
| `POST`   | `/statecharts`          | body `{"document": <AST JSON>, "instance_id"?: id}` → `ScxmlEngine.run/2` | 201 `{instance_id, configuration}`     | 400 bad AST / unknown    |
| `GET`    | `/statecharts/:graphId` | describe a stored graph (via `load`/inspect)                              | 200 graph metadata                     | 404                      |
| `POST`   | `/instances`            | body `{"graph_id": g, "initial_datamodel"?: m}` → `start_instance/1`      | 201 `{instance_id, configuration}`     | 400 unknown graph_id     |
| `GET`    | `/instances/:id`        | `instance_pid/1` → snapshot                                               | 200 `{configuration, datamodel, done}` | 404                      |
| `POST`   | `/instances/:id/events` | body `{"name": n, "data": d}` → `send_event_to/3`                         | 200 settled state                      | 404 instance / bad event |
| `DELETE` | `/instances/:id`        | stop & unregister instance                                                | 204                                    | 404                      |
| `GET`    | `/instances`            | `instances/0` → list                                                      | 200 `[{id, configuration}]`            | —                        |

## 3. Serialization rules

- **Active configuration** is a `MapSet` → `MapSet.to_list/1`, encode as JSON array.
- **Datamodel** is a map → encode directly with `Jason`.
- **Event payload** `{"name": n, "data": d}` maps naturally to
  `send_event_to(id, name, data)` (the library wraps it as `%{"name" => n, "data" => d}`).
- **Errors**: `run/2` → 400 (bad request); unknown instance/graph → 404;
  internal failures → 500. Map library `{:error, reason}` to HTTP carefully.
- Reject unknown JSON keys / non-object bodies with 400 before calling the engine.

## 4. Concurrency & lifecycle notes

- Each `send_event_to` is a blocking `GenServer.call` on the _instance_ process;
  a slow/hung instance holds only its own mailbox — other instances keep
  stepping. No global locks needed.
- `ScxmlOrchestrator.Application` (Registry + Instance supervisor) is already
  booted by Mix as a runtime dependency — do **not** add it to our own tree.
- `DELETE /instances/:id` needs a stop path. Confirm whether the library exposes
  one (or `:ets.unregister` via the registry). If not, extend `start_instance`/
  teardown in the facade (see §6 "library gaps").

## 5. Build order (layered, each layer green before next)

1. **Engine facade** — add `Engine` module: `register/2`, `start/2`,
   `step/3`, `snapshot/1`, `list/0`, `remove/1`, each returning a normalized
   result the router can map to HTTP. Unit-test-free for now, but keep pure.
2. **Router endpoints** — implement routes against the facade; keep `/healthz`.
3. **Error mapping** — central `error_to_status/1` + JSON error body helper.
4. **Boot & manual verify** — run server, `curl` each endpoint with a small
   sample AST document (e.g. the traffic-light example).
5. **Durability (later phase)** — snapshot `{instance_id, configuration,
datamodel, graph_id}` after each macrostep; rehydrate on boot via
   `run/2` with `initial_datamodel`. Requires storing the original AST JSON.
6. **Distribution (optional later phase)** — swap Registry/DynamicSupervisor for
   Horde; make `send_event_to` node-aware at the routing seam.
7. **Tests** — add `mix test --stale` (pre-commit) + `mix test --cover` (pre-push)
   stages to `lefthook.yml`, then write ExUnit+Plug.Test suites for all handlers
   and the engine/error facades. 57 tests, 100% contract-layer coverage.

## 6. Known library gaps (resolved)

- **No teardown API** → `GenServer.stop(pid)` works; the library's registry
  entry is keyed to the instance process, so it auto-unregisters on termination.
  (Resolved — see §8 Notes.)
- **instance_id resolution** → when omitted, `register_and_start` recovers it by
  matching the pid against `instances/0`. (Resolved — see §8 Notes.)
- **Graph description** (`GET /statecharts/:graphId`) has no direct "describe"
  call — may need to keep a side-table of `graph_id → AST` (or re-parse) to
  return meaningful metadata. (Still deferred.)

## 7. Out of scope (this milestone)

- Auth/rate-limiting.
- Persistence & Horde (deferred phases §5.5–5.6).
- `GET /statecharts/:graphId` (graph describe) — needs a side-table; deferred.

## 8. Shipped & verified (2026-08-15)

### Modules

- `lib/scxml_http_engine/engine.ex` — facade over `ScxmlEngine`
  (`register_and_start/2`, `start_instance/3`, `step/3`, `snapshot/1`,
  `list_instances/0`, `remove_instance/1`).
- `lib/scxml_http_engine/error.ex` — `to_json/1` maps `Engine` results to
  `{status, body}` (`200`/`201`/`400`/`404`).
- `lib/scxml_http_engine/router.ex` — routes wired to handler modules.
- `lib/scxml_http_engine/tracer.ex` — custom tracing plug: injects `request_id`
  - OTel metadata, logs request completion, suppresses health check noise.
- `lib/scxml_http_engine/code_reloader.ex` — dev-only request-driven compilation.
- `lib/scxml_http_engine/handlers/healthz.ex` — `init/1`, `call/2` for `GET /healthz`.
- `lib/scxml_http_engine/handlers/instances.ex` — `init/1`, `call/2` for all
  instance CRUD routes.
- `lib/scxml_http_engine/handlers/statecharts.ex` — `init/1`, `call/2` for `POST /statecharts`.
- `lib/scxml_http_engine/open_api/api_spec.ex` — OpenAPI 3.0 spec using `OpenApiSpex`.
- `lib/scxml_http_engine/open_api/schemas.ex` — nested schema modules (`Error`,
  `EventRequest`, `StateInfo`, `Snapshot`, `InstanceList`,
  `RegisterDocumentRequest`, `StartInstanceRequest`, `DeletedResponse`).

### Endpoints verified via curl against a running server and container

| Method/Path                  | Result                                 |
| ---------------------------- | -------------------------------------- |
| `POST /statecharts`          | 201, starts instance, returns snapshot |
| `POST /instances`            | 201 (valid graph); 400 (unknown graph) |
| `GET /instances/:id`         | 200 snapshot; 404 after delete         |
| `POST /instances/:id/events` | 200 settled state (synchronous step)   |
| `GET /instances`             | 200 array of snapshots                 |
| `DELETE /instances/:id`      | 200 `{"deleted":true}`; then 404       |
| `GET /healthz`               | 200; unknown route 404; bad JSON 400   |

### Test suite (57 tests, 100% contract-layer coverage)

| Test file                            | Tests | Coverage | Notes                          |
| ------------------------------------ | ----- | -------- | ------------------------------ |
| `test/engine_test.exs`               | 6     | 100%     | all 6 public functions         |
| `test/error_test.exs`                | 6     | 100%     | all status/body combos         |
| `test/router_test.exs`               | 21    | 100%     | init/1, all endpoints, errors  |
| `test/tracer_test.exs`               | 12    | 100%     | metadata, quiet paths, logging |
| `test/handlers/healthz_test.exs`     | —     | 100%     | covered via router_test        |
| `test/handlers/instances_test.exs`   | —     | 100%     | covered via router_test        |
| `test/handlers/statecharts_test.exs` | —     | 100%     | covered via router_test        |

Coverage enforced via `mix test --cover` (pre-push hook) with a 100% threshold.
Ignored modules: `Application`, `ScxmlHttpEngine` (top-level), `Tracer`, `CodeReloader`.

### Pre-commit / pre-push pipeline (`lefthook.yml`)

| Hook       | Commands                                                                 |
| ---------- | ------------------------------------------------------------------------ |
| pre-commit | `mix format --check-formatted`, `mix credo --strict`, `mix test --stale` |
| pre-push   | `mix test --cover`                                                       |

Credo: `MissedMetadataKeyInLoggerConfig` disabled (false positive — keys are
configured inside nested formatter tuples).

### Logging & Tracing

| Feature              | Implementation                                                                    |
| -------------------- | --------------------------------------------------------------------------------- |
| Structured JSON logs | `LoggerJSON ~> 7.0` in prod via `{LoggerJSON.Formatters.Logger, metadata: [...]}` |
| Dev console logs     | `Logger.Formatter.new(metadata: [...])` with all keys                             |
| Logger levels        | `:debug` dev, `:info` prod                                                        |
| OTel spans           | `opentelemetry_api ~> 1.3`, `opentelemetry_cowboy ~> 1.0`                         |
| OTel exporter        | Prod-only via `config/runtime.exs` (OTLP, disabled in dev/test)                   |
| Request tracing      | `Plug.RequestId` + custom `Tracer` plug injects metadata, logs completion         |
| Quiet paths          | `/healthz`, `/openapi`, `/swaggerui` suppressed to `:warning` level               |

Reference: `LOGGING_TRACING.md` for full architecture details.

### Docker

- Multi-stage `Dockerfile` → self-contained Mix release on `debian:bookworm-slim`.
- `mix.exs`: conditional dep — path (`../scxml-orchestrator`) locally, git
  fallback in the container (`branch: main`, locked to commit `dbd9d93`).
- `config/runtime.exs`: runtime-configurable `SCXML_HTTP_ENGINE_PORT`.
- `docker-compose.yml` with Compose Watch for hot reloading (sync `./lib`, `./config`;
  rebuild on `mix.exs`/`mix.lock`).
- Verified: image builds (~164 MB), container boots clean (UTF-8 locale set),
  full statechart flow works over HTTP inside the container.

Reference: `HOT_RELOADING_DOCKER.md` for the hot reload workflow.

### Notes

- `DELETE` uses `GenServer.stop(pid)`; the library's registry entry is keyed to
  the instance process, so it auto-unregisters on termination.
- `instance_id` resolution: when omitted, `register_and_start` recovers it by
  matching the pid against `instances/0`.
