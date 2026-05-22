defmodule Trinity.Examples.QwenRouterPromptEval.MixProject do
  use Mix.Project

  def project do
    [
      app: :qwen_router_prompt_eval,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:trinity_contracts, path: "../../core/trinity_contracts"}
    ]
  end
end
