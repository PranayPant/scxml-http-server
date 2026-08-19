defmodule ScxmlHttpEngine.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    # Initialise the automated Bandit network-level tracing spans.
    OpentelemetryBandit.setup()

    port = Application.get_env(:scxml_http_engine, ScxmlHttpEngine.Router, [])[:port] || 4000

    children = [
      # The HTTP transport. `scxml-orchestrator` is a runtime dependency whose
      # own OTP application already boots the Registry + Instance supervisor,
      # so we do NOT add it here.
      {Bandit, plug: ScxmlHttpEngine.Router, scheme: :http, port: port}
    ]

    opts = [strategy: :one_for_one, name: ScxmlHttpEngine.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("scxml-http-engine started on port #{port}")
        {:ok, pid}

      error ->
        error
    end
  end
end
