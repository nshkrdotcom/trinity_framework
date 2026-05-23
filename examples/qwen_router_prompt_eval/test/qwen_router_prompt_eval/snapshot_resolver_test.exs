defmodule Trinity.Examples.QwenRouterPromptEval.SnapshotResolverTest do
  use ExUnit.Case, async: true

  alias Trinity.Examples.QwenRouterPromptEval.SnapshotResolver

  test "explicit override wins" do
    assert SnapshotResolver.resolve(:cuda_exla, "/tmp/explicit.json") == "/tmp/explicit.json"
  end

  test "per-profile fixture wins when present" do
    dir = tmp_dir()
    on_exit(fn -> File.rm_rf!(dir) end)

    profile_path =
      Path.join([
        dir,
        "fixtures",
        "runtime_profiles",
        "fake",
        "qwen_router_prompt_eval_logits.json"
      ])

    File.mkdir_p!(Path.dirname(profile_path))
    File.write!(profile_path, "{}")

    assert SnapshotResolver.resolve(:fake, nil, base_dir: dir) == profile_path
  end

  test "legacy fixture is not an implicit fallback" do
    dir = tmp_dir()
    on_exit(fn -> File.rm_rf!(dir) end)

    legacy_path = Path.join([dir, "fixtures", "qwen_router_prompt_eval_logits.json"])
    File.mkdir_p!(Path.dirname(legacy_path))
    File.write!(legacy_path, "{}")

    assert SnapshotResolver.resolve(:cuda_exla, nil, base_dir: dir) == nil
  end

  defp tmp_dir do
    Path.join(System.tmp_dir!(), "qwen-snapshot-resolver-#{System.unique_integer([:positive])}")
  end
end
