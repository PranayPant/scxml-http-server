defmodule ScxmlHttpEngine.Router do
  @moduledoc """
  The HTTP transport / routing layer.

  Routes live here but the statechart endpoints are intentionally **not**
  implemented yet. During the scaffolding phase only a health check and a
  404 catch-all exist so the pipeline has a real module to compile, format and
  lint. The full endpoint surface is designed in the implementation plan.

  See README §8 for the intended routes.
  """

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  # Liveness probe for load balancers / orchestrators.
  get "/healthz" do
    send_resp(conn, 200, "ok")
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
