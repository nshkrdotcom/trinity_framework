defmodule Trinity.SingleNode.Examples.LocalCoordinatorRoute do
  @moduledoc false

  alias Trinity.Coordinator.RoleInjector
  alias Trinity.SakanaPipeline.ArtifactIO
  alias Trinity.SingleNode

  @default_prompt "Select a TRINITY role for this reasoning task."

  def main(argv) do
    opts = parse!(argv)
    Application.ensure_all_started(:trinity_single_node)

    artifact_dir = Keyword.fetch!(opts, :artifact_dir)
    profile = Keyword.fetch!(opts, :runtime_profile)
    prompt = Keyword.fetch!(opts, :prompt)
    messages = [%{role: "user", content: prompt}]

    maybe_ensure_manifest!(profile, artifact_dir)

    {:ok, result} =
      SingleNode.route(messages,
        runtime_profile: profile,
        artifact_root: artifact_dir
      )

    print_report(artifact_dir, profile, prompt, result)
  end

  defp parse!(argv) do
    {opts, rest, errors} =
      argv
      |> normalize_argv()
      |> OptionParser.parse(
        strict: [
          artifact_dir: :string,
          prompt: :string,
          runtime_profile: :string
        ]
      )

    unless rest == [], do: raise("Unexpected arguments: #{inspect(rest)}")
    unless errors == [], do: raise("Invalid options: #{inspect(errors)}")

    [
      artifact_dir: Keyword.get(opts, :artifact_dir, default_artifact_dir()),
      prompt: Keyword.get(opts, :prompt, @default_prompt),
      runtime_profile: runtime_profile!(Keyword.get(opts, :runtime_profile, "cuda_exla"))
    ]
  end

  defp print_report(artifact_dir, profile, prompt, result) do
    decision = result.decision
    logits = result.logits
    manifest_path = Path.join(artifact_dir, ArtifactIO.manifest_file())

    IO.puts("""

    Input
      prompt: #{prompt}
      transcript_hash: #{decision.transcript_hash}

    Artifact
      dir: #{artifact_dir}
      manifest_path: #{manifest_path}
      manifest_sha256: #{manifest_sha(manifest_path)}

    Runtime
      profile: #{profile}
      backend: #{inspect(logits.backend_label)}

    Router
      selected_agent_id: #{decision.selected_agent_id}
      selected_role_id: #{decision.selected_role_id}
      selected_role_name: #{RoleInjector.role_name(decision.selected_role_id)}
      token_count: #{decision.token_count}
      route_hash: #{decision.route_hash}

    Boundary
      provider_calls: none
      purpose: prove the standalone single-node runtime loads and produces a local route.
    """)
  end

  defp maybe_ensure_manifest!(:mock_tiny, _artifact_dir), do: :ok

  defp maybe_ensure_manifest!(_profile, artifact_dir) do
    manifest_path = Path.join(artifact_dir, ArtifactIO.manifest_file())
    unless File.exists?(manifest_path), do: raise("Missing adapted artifact manifest: #{manifest_path}")
  end

  defp manifest_sha(path), do: if(File.exists?(path), do: ArtifactIO.file_sha256!(path), else: "n/a")

  defp runtime_profile!("mock_tiny"), do: :mock_tiny
  defp runtime_profile!("host_exla"), do: :host_exla
  defp runtime_profile!("cuda_exla"), do: :cuda_exla
  defp runtime_profile!(other), do: raise("Unsupported runtime profile #{inspect(other)}")

  defp default_artifact_dir do
    Path.expand(
      "../../../priv/sakana_trinity/adapted_qwen3_0_6b_layer26",
      __DIR__
    )
  end

  defp normalize_argv(["--" | rest]), do: rest
  defp normalize_argv(argv), do: argv
end

Trinity.SingleNode.Examples.LocalCoordinatorRoute.main(System.argv())
