defmodule ScxmlHttpEngine.CodeReloader do
  @moduledoc """
  Request-driven Elixir code reloader for development.

  On every HTTP request in the `:dev` environment, this plug re-enables and
  re-runs the `compile.elixir` Mix task so that any source files synced by
  Docker Compose Watch are compiled before the request reaches the router.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if Mix.env() == :dev do
      Mix.Task.reenable("compile.elixir")
      Mix.Task.run("compile.elixir")
    end

    conn
  end
end
