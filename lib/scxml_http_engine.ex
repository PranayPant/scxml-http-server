defmodule ScxmlHttpEngine do
  @moduledoc """
  HTTP engine for executing SCXML statecharts.

  This module is a thin transport on top of the `scxml-orchestrator` library's
  `ScxmlEngine` API. During the scaffolding phase it exposes only the server
  entry points; the statechart endpoint implementation is designed in the
  implementation plan.
  """

  @doc """
  Starts the HTTP engine (via the OTP application supervisor).
  """
  @spec start(Application.start_type(), Application.start_args()) :: Supervisor.on_start()
  def start(_type, _args) do
    ScxmlHttpEngine.Application.start(:normal, [])
  end
end
