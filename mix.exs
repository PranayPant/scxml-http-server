defmodule ScxmlHttpEngine.MixProject do
  use Mix.Project

  def project do
    [
      app: :scxml_http_engine,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ScxmlHttpEngine.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Transports on top of the in-process SCXML runtime.
      {:scxml_orchestrator, path: "../scxml-orchestrator"},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.7"},
      # Code-quality toolchain (dev/test only) — see lefthook.yml.
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false}
    ]
  end
end
