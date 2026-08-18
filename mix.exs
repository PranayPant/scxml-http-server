defmodule ScxmlHttpEngine.MixProject do
  use Mix.Project

  def project do
    [
      app: :scxml_http_engine,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [summary: [threshold: 100], ignore_modules: ignored_modules()],
      releases: releases(),
      deps: deps()
    ]
  end

  # Modules that are not covered by unit / Plug.Test tests (they boot the
  # real cowboy listener and are exercised by integration tests, which are
  # intentionally out of scope for now). Mirroring scxml-orchestrator's
  # `ignore_modules` usage.
  defp ignored_modules do
    [
      ScxmlHttpEngine.Application,
      ScxmlHttpEngine,
      ScxmlHttpEngine.Tracer,
      # Dev-only infrastructure plug — its `call/2` only runs when
      # `Mix.env() == :dev`, so tests in the `:test` environment cannot
      # exercise it.
      ScxmlHttpEngine.CodeReloader
    ]
  end

  # Run "mix help release" to learn about releases.
  defp releases do
    [
      scxml_http_engine: [
        include_executables_for: [:unix],
        steps: [:assemble]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :opentelemetry],
      mod: {ScxmlHttpEngine.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Transports on top of the in-process SCXML runtime.
      #
      # Pinned to a git tag from the orchestrator's release workflow.
      # For local development, override via `mix deps.update` or
      # temporarily swap to `path: "../scxml-orchestrator"`.
      {:scxml_orchestrator, github: "PranayPant/scxml-orchestrator", tag: "v0.0.1"},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.7"},
      {:open_api_spex, "~> 3.19"},
      {:logger_json, "~> 7.0"},
      {:opentelemetry, "~> 1.3"},
      {:opentelemetry_api, "~> 1.3"},
      {:opentelemetry_cowboy, "~> 1.0"},
      {:cors_plug, "~> 3.0"},
      # Code-quality toolchain (dev/test only) — see lefthook.yml.
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false}
    ]
  end

end
