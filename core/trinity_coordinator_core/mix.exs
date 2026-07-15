unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule Trinity.CoordinatorCore.MixProject do
  use Mix.Project

  @repo_root Path.expand("../..", __DIR__)
  @source_url "https://github.com/nshkrdotcom/trinity_framework"

  def project do
    [
      app: :trinity_coordinator_core,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_deps: :apps_direct],
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :logger, :outer_brain_context_abi]
    ]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test,
        credo: :test,
        dialyzer: :test,
        docs: :dev
      ]
    ]
  end

  defp deps do
    [
      {:trinity_contracts, path: "../trinity_contracts"},
      {:trinity_sakana_contracts, path: "../trinity_sakana_contracts"},
      DependencySources.dep(:crucible_signal, @repo_root),
      DependencySources.dep(:crucible_tap, @repo_root),
      DependencySources.dep(:crucible_policy, @repo_root),
      DependencySources.dep(:crucible_signal_trace, @repo_root),
      DependencySources.dep(:outer_brain_context_abi, @repo_root),
      {:jason, "~> 1.4.5"}
    ] ++ quality_deps()
  end

  defp quality_deps do
    [
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.3", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      ci: [
        "deps.get",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "credo --strict",
        "dialyzer --format short",
        "docs"
      ]
    ]
  end

  defp docs do
    [
      source_ref: "main",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end
end
