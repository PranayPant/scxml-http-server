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
      ScxmlHttpEngine
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
      extra_applications: [:logger],
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
      # Local dev uses the sibling checkout (../scxml-orchestrator); container
      # / CI builds where that path does not exist fall back to the git
      # dependency so `docker build` works without extra context.
      scxml_orchestrator_dep(),
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.7"},
      # Code-quality toolchain (dev/test only) — see lefthook.yml.
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false}
    ]
  end

  defp scxml_orchestrator_dep do
    if File.dir?("../scxml-orchestrator") do
      {:scxml_orchestrator, path: "../scxml-orchestrator"}
    else
      {:scxml_orchestrator, git: "https://github.com/PranayPant/scxml-orchestrator.git"}
    end
  end
end
