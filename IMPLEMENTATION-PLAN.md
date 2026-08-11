# Implementation Plan

This document plans the HTTP engine implementation once the scaffolding +
pre-commit pipeline are in place. It drives the `ScxmlHttpEngine` transport on
top of the `scxml-orchestrator` library's `ScxmlEngine` public API.

> **STATUS: end-to-end implementation + Docker build complete (2026-08-11).**
> The endpoints below are implemented and verified (see §8). Remaining
> future work: durability/snapshot persistence, Horde distribution, and the
> test suites (intentionally still deferred).

## 0. Confirmed library API (from `scxml-orchestrator` `lib/scxml_engine.ex`)

| Function | Signature | Notes |
| --- | --- | --- |
| `run/2` | `run(ast_json, opts)` → `{:ok, pid} \| {:error, term}` | load+store+start in one go |
| `load/1` | `load(json)` → `{:ok, graph}` | parse AST JSON |
| `store/2` | `store(graph, graph_id \\ nil)` → `{:ok, graph_id}` | compile + persist graph |
| `start_instance/1` | `start_instance(opts)` → `{:ok, pid} \| :error` | opts: `:graph_id`, `:instance_id`, `:initial_datamodel` |
| `send_event/3` | `send_event(pid, name, payload \\ %{})` → `:ok` | synchronous step by pid |
| `send_event_to/3` | `send_event_to(id, name, payload \\ %{})` → `:ok \| :error` | route by instance id |
| `instance_pid/1` | `instance_pid(id)` → `{:ok, pid} \| :error \| nil` | registry lookup |
| `active_configuration/1` | `active_configuration(pid)` → `MapSet.t` | encode as JSON array |
| `datamodel/1` | `datamodel(pid)` → `map` | |
| `done?/1` | `done?(pid)` → `boolean` | terminal-state detection |
| `instances/0` | `instances()` → `[{id, pid}]` | enumerate |

## 1. Module layout

```
lib/scxml_http_engine/
  application.ex       # (exists) starts Plugin.Cowboy + Router
  router.ex            # (exists stub) route dispatch — will gain endpoints
  engine.ex            # NEW: thin facade over ScxmlEngine (serialization, errors)
  instance.ex          # NEW (optional): per-instance snapshot helpers
```

Keep the router thin: route matching + plug boilerplate lives in `router.ex`;
SCXML-specific logic (MapSet→array, error mapping, JSON payload handling) lives
in a small `Engine` facade so routes stay declarative and testable.

## 2. Endpoint surface (matches README §8)

| Method | Path | Flow | Success | Errors |
| --- | --- | --- | --- | --- |
| `POST` | `/statecharts` | body `{"document": <AST JSON>, "instance_id"?: id}` → `ScxmlEngine.run/2` | 201 `{instance_id, configuration}` | 400 bad AST / unknown |
| `GET` | `/statecharts/:graphId` | describe a stored graph (via `load`/inspect) | 200 graph metadata | 404 |
| `POST` | `/instances` | body `{"graph_id": g, "initial_datamodel"?: m}` → `start_instance/1` | 201 `{instance_id, configuration}` | 400 unknown graph_id |
| `GET` | `/instances/:id` | `instance_pid/1` → snapshot | 200 `{configuration, datamodel, done}` | 404 |
| `POST` | `/instances/:id/events` | body `{"name": n, "data": d}` → `send_event_to/3` | 200 settled state | 404 instance / bad event |
| `DELETE` | `/instances/:id` | stop & unregister instance | 204 | 404 |
| `GET` | `/instances` | `instances/0` → list | 200 `[{id, configuration}]` | — |

## 3. Serialization rules

- **Active configuration** is a `MapSet` → `MapSet.to_list/1`, encode as JSON array.
- **Datamodel** is a map → encode directly with `Jason`.
- **Event payload** `{"name": n, "data": d}` maps naturally to
  `send_event_to(id, name, data)` (the library wraps it as `%{"name" => n, "data" => d}`).
- **Errors**: `run/2` → 400 (bad request); unknown instance/graph → 404;
  internal failures → 500. Map library `{:error, reason}` to HTTP carefully.
- Reject unknown JSON keys / non-object bodies with 400 before calling the engine.

## 4. Concurrency & lifecycle notes

- Each `send_event_to` is a blocking `GenServer.call` on the *instance* process;
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
7. **Tests (deferred by user)** — add `mix test --stale` + `mix test --cover`
   stages to `lefthook.yml`, then write ExUnit+Plug.Test suites.

## 6. Known library gaps to watch

- **No teardown API observed** (only `start_instance`, no `stop_instance`). The
  `DELETE` endpoint may need to call the instance's `GenServer.stop/1` directly
  or rely on `DynamicSupervisor` termination. Verify in the library before
  implementing.
- **instance_id resolution**: README notes id defaults to graph id when omitted.
  The `run/2` returns only a pid; to recover the resolved id, match the pid
  against `instances/0` (as README's `instance_id_for_pid/1` does) or extend the
  facade to capture it at registration time.
- **Graph description** (`GET /statecharts/:graphId`) has no direct "describe"
  call — may need to keep a side-table of `graph_id → AST` (or re-parse) to
  return meaningful metadata.

## 7. Out of scope (this milestone)

- Tests (deferred; see note).
- Auth/rate-limiting.
- Persistence & Horde (deferred phases §5.5–5.6).
- `GET /statecharts/:graphId` (graph describe) — needs a side-table; deferred.

## 8. Shipped & verified (2026-08-11)

**Modules added**
- `lib/scxml_http_engine/engine.ex` — facade over `ScxmlEngine`
  (`register_and_start/2`, `start_instance/3`, `step/3`, `snapshot/1`,
  `list_instances/0`, `remove_instance/1`).
- `lib/scxml_http_engine/error.ex` — `to_json/1` maps `Engine` results to
  `{status, body}` (`200`/`201`/`400`/`404`).
- `lib/scxml_http_engine/router.ex` — routes wired to the facade.

**Endpoints verified via curl against a running server and a running container**

| Method/Path | Result |
| --- | --- |
| `POST /statecharts` | 201, starts instance, returns snapshot |
| `POST /instances` | 201 (valid graph); 400 (unknown graph) |
| `GET /instances/:id` | 200 snapshot; 404 after delete |
| `POST /instances/:id/events` | 200 settled state (synchronous step) |
| `GET /instances` | 200 array of snapshots |
| `DELETE /instances/:id` | 200 `{"deleted":true}`; then 404 |
| `GET /healthz` | 200; unknown route 404; bad JSON 400 |

**Docker**
- Multi-stage `Dockerfile` → self-contained Mix release on `debian:bookworm-slim`.
- `mix.exs`: conditional dep — path (`../scxml-orchestrator`) locally, git
  fallback in the container (needs git in builder).
- `config/runtime.exs`: runtime-configurable `SCXML_HTTP_ENGINE_PORT`.
- Verified: image builds (~164 MB), container boots clean (UTF-8 locale set),
  full statechart flow works over HTTP inside the container.

**Notes**
- `DELETE` uses `GenServer.stop(pid)`; the library's registry entry is keyed to
  the instance process, so it auto-unregisters on termination.
- `instance_id` resolution: when omitted, `register_and_start` recovers it by
  matching the pid against `instances/0`.
