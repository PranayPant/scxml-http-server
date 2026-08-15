defmodule ScxmlHttpEngine.OpenApi.ApiSpec do
  @moduledoc """
  OpenAPI 3.0 specification for the SCXML HTTP Engine API.

  Implements the `OpenApiSpex.OpenApi` behaviour so the spec can be served at
  `/openapi` via `OpenApiSpex.Plug.RenderSpec`.
  """

  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.{Info, OpenApi, PathItem, Server}
  alias ScxmlHttpEngine.Handlers

  @impl OpenApiSpex.OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "SCXML HTTP Engine",
        version: "0.1.0",
        description: "HTTP transport layer for the scxml-orchestrator runtime. Execute SCXML statecharts over HTTP."
      },
      servers: [
        %Server{
          url: "http://localhost:4000",
          description: "Local development server"
        }
      ],
      paths: paths()
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp paths do
    %{
      "/healthz" =>
        PathItem.from_routes([
          %{verb: :get, plug: Handlers.Healthz, opts: []}
        ]),
      "/statecharts" =>
        PathItem.from_routes([
          %{verb: :post, plug: Handlers.Statecharts, opts: []}
        ]),
      "/instances" =>
        PathItem.from_routes([
          %{verb: :get, plug: Handlers.Instances, opts: [action: :index]},
          %{verb: :post, plug: Handlers.Instances, opts: [action: :create]}
        ]),
      "/instances/{id}" =>
        PathItem.from_routes([
          %{verb: :get, plug: Handlers.Instances, opts: [action: :show]},
          %{verb: :delete, plug: Handlers.Instances, opts: [action: :delete]}
        ]),
      "/instances/{id}/events" =>
        PathItem.from_routes([
          %{verb: :post, plug: Handlers.Instances, opts: [action: :event]}
        ])
    }
  end
end
