defmodule Trinity.Examples.QwenRouterPromptEval.SnapshotResolver do
  @moduledoc """
  Resolves per-runtime-profile prompt-eval snapshot fixtures.
  """

  @snapshot_file "qwen_router_prompt_eval_logits.json"

  @spec resolve(atom(), String.t() | nil, keyword()) :: String.t() | nil
  def resolve(profile_name, explicit, opts \\ [])

  def resolve(_profile_name, explicit, _opts) when is_binary(explicit), do: explicit

  def resolve(profile_name, nil, opts) when is_atom(profile_name) do
    base_dir = Keyword.get(opts, :base_dir, package_root())

    per_profile =
      Path.join([
        base_dir,
        "fixtures",
        "runtime_profiles",
        Atom.to_string(profile_name),
        @snapshot_file
      ])

    if File.regular?(per_profile), do: per_profile, else: nil
  end

  defp package_root, do: Path.expand("../..", __DIR__)
end
