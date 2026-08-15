defmodule ScxmlHttpEngine.Router do
  @moduledoc """
  The HTTP transport / routing layer.

  Exposes the statechart engine over HTTP. All statechart handling is delegated
  to `ScxmlHttpEngine.Engine` (via handler modules); this module only matches
  routes and delegates to the appropriate handler.

  See `IMPLEMENTATION-PLAN.md` for the endpoint design and `README §8` for the
  intended route surface.
  """

  use Plug.Router

  alias ScxmlHttpEngine.Handlers

  # Request-driven code reloader (dev-mode only — recompiles synced sources
  # before each request so Docker Compose Watch hot-reload works).
  if Mix.env() == :dev do
    plug(ScxmlHttpEngine.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(ScxmlHttpEngine.Tracer)

  plug(OpenApiSpex.Plug.PutApiSpec, module: ScxmlHttpEngine.OpenApi.ApiSpec)
  plug(:match)
  plug(:dispatch)

  # Liveness probe for load balancers / orchestrators.
  get("/healthz", to: Handlers.Healthz, init_opts: [])

  # Register + start an instance from an uploaded AST JSON document.
  # Body: {"document": <AST JSON string>, "instance_id"?: "my-id"}
  post("/statecharts", to: Handlers.Statecharts, init_opts: [])

  # Start an instance from a stored graph.
  # Body: {"graph_id": "g", "instance_id"?: "x", "initial_datamodel"?: {...}}
  post("/instances", to: Handlers.Instances, init_opts: [action: :create])

  # Snapshot an instance.
  get("/instances/:id", to: Handlers.Instances, init_opts: [action: :show])

  # Send an event (synchronous "step") and return the settled state.
  # Body: {"name": "next", "data": {...}}
  post("/instances/:id/events", to: Handlers.Instances, init_opts: [action: :event])

  # Stop and remove an instance.
  delete("/instances/:id", to: Handlers.Instances, init_opts: [action: :delete])

  # Enumerate all running instances.
  get("/instances", to: Handlers.Instances, init_opts: [action: :index])

  # OpenAPI spec endpoint
  get("/openapi", to: OpenApiSpex.Plug.RenderSpec, init_opts: [])

  # Swagger UI
  get("/swaggerui", to: OpenApiSpex.Plug.SwaggerUI, init_opts: [path: "/openapi"])

  @json_error_body Jason.encode!(%{error: "not found"})

  match _ do
    send_resp(conn, 404, @json_error_body)
  end
end
