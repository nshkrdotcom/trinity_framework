unless Code.ensure_loaded?(DependencySources) do
  Code.require_file(Path.expand("../../build_support/dependency_sources.exs", __DIR__))
end

defmodule Trinity.Ops.MixProject do
  use Mix.Project

  @framework_root Path.expand("../..", __DIR__)
  @source_url "https://github.com/nshkrdotcom/trinity_framework"

  def project do
    [
      app: :trinity_ops,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_deps: :apps_direct, plt_add_apps: [:mix, :nx]],
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
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
      {:trinity_contracts, path: "../../core/trinity_contracts"},
      {:trinity_single_node, path: "../../apps/trinity_single_node"},
      {:trinity_coordinator_core, path: "../../core/trinity_coordinator_core"},
      {:trinity_sakana_pipeline, path: "../../core/trinity_sakana_pipeline"},
      {:trinity_bridge_self_hosted_inference,
       path: "../../bridges/trinity_bridge_self_hosted_inference"},
      {:trinity_bridge_inference, path: "../../bridges/trinity_bridge_inference"},
      {:trinity_bridge_trace, path: "../../bridges/trinity_bridge_trace"},
      dep(:crucible_factorization),
      dep(:crucible_model_registry),
      dep(:crucible_mechinterp),
      dep(:crucible_policy),
      dep(:crucible_bumblebee),
      dep(:crucible_signal_trace),
      dep(:crucible_tap),
      dep(:self_hosted_inference_core),
      dep(:self_hosted_inference_bumblebee),
      {:hf_hub, "~> 0.3"},
      {:jason, "~> 1.4"}
    ] ++ quality_deps()
  end

  defp dep(app, opts \\ []), do: DependencySources.dep(app, @framework_root, opts)

  defp quality_deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: [:dev, :test], runtime: false}
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
