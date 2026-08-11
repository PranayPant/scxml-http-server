defmodule ScxmlHttpEngine.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:scxml_http_engine, ScxmlHttpEngine.Router, [])[:port] || 4000

    children = [
      # The HTTP transport. `scxml-orchestrator` is a runtime dependency whose
      # own OTP application already boots the Registry + Instance supervisor,
      # so we do NOT add it here.
      {Plug.Cowboy, scheme: :http, plug: ScxmlHttpEngine.Router, options: [port: port]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ScxmlHttpEngine.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
