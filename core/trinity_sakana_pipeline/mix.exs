defmodule Trinity.SakanaPipeline.MixProject do
  use Mix.Project

  def project do
    [
      app: :trinity_sakana_pipeline,
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
      {:trinity_contracts, path: "../trinity_contracts"},
      {:trinity_sakana_contracts, path: "../trinity_sakana_contracts"}
    ]
  end
end
