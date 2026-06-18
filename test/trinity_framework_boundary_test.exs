defmodule TrinityFrameworkBoundaryTest do
  use ExUnit.Case, async: true

  @scan_roots [
    "mix.exs",
    "mix.lock",
    "README.md",
    "CHANGELOG.md",
    "build_support/",
    "config/",
    "docs/",
    "guides/",
    "lib/",
    "test/",
    "core/",
    "bridges/",
    "apps/",
    "tools/",
    "tools/python/",
    "examples/",
    "priv/sakana_trinity/scripts/",
    "priv/sakana_trinity/reference/",
    "priv/sakana_trinity/artifact_pin.json",
    "priv/sakana_trinity/reference/sakana_python_reference_manifest.json"
  ]

  @text_extensions [
    ".config",
    ".ex",
    ".exs",
    ".eex",
    ".heex",
    ".json",
    ".lock",
    ".md",
    ".py",
    ".sh",
    ".txt",
    ".yaml",
    ".yml"
  ]

  @text_basenames ["mix.lock", "README.md", "CHANGELOG.md"]

  test "framework source does not name downstream product boundaries" do
    assert no_matches?(boundary_paths(), downstream_terms())
  end

  test "framework source uses fixed scans and explicit config" do
    assert no_matches?(runtime_rule_paths(), runtime_forbidden_terms())
  end

  test "external Python trace-provider scripts are inside boundary scan roots" do
    assert "tools/python/crucible_torch_trace.py" in source_paths()
    refute File.dir?("python")
  end

  defp no_matches?(paths, terms) do
    matches =
      for path <- paths,
          content = File.read!(path),
          term <- terms,
          String.contains?(content, term),
          do: "#{path}: #{term}"

    assert matches == []
  end

  defp boundary_paths do
    source_paths()
    |> Enum.reject(&boundary_excluded?/1)
  end

  defp runtime_rule_paths do
    source_paths()
    |> Enum.reject(&runtime_rule_excluded?/1)
  end

  defp source_paths do
    paths =
      case git_source_paths() do
        [] -> filesystem_source_paths()
        paths -> paths
      end

    paths
    |> Enum.filter(fn path ->
      File.regular?(path) and in_scan_root?(path) and text_file?(path)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp git_source_paths do
    case System.cmd("git", ["ls-files", "--cached", "--others", "--exclude-standard"],
           stderr_to_stdout: true
         ) do
      {files, 0} -> String.split(files, "\n", trim: true)
      {_output, _status} -> []
    end
  end

  defp filesystem_source_paths do
    Enum.flat_map(@scan_roots, &walk_source_path/1)
  end

  defp walk_source_path(path) do
    cond do
      File.regular?(path) ->
        [path]

      File.dir?(path) ->
        path
        |> File.ls!()
        |> Enum.reject(&ignored_source_entry?/1)
        |> Enum.flat_map(&walk_source_path(Path.join(path, &1)))

      true ->
        []
    end
  end

  defp ignored_source_entry?(entry) do
    entry in [".git", "_build", "deps", "dist", "doc", "erl_crash.dump"]
  end

  defp boundary_excluded?(path) do
    path in ["AGENTS.md", "test/trinity_framework_boundary_test.exs"]
  end

  defp runtime_rule_excluded?(path) do
    path == "test/trinity_framework_boundary_test.exs" or
      runtime_config_source?(path)
  end

  defp runtime_config_source?(path) do
    path == "config/runtime.exs" or
      String.ends_with?(path, "/config/runtime.exs") or
      String.starts_with?(path, "config/runtime_sources/") or
      String.starts_with?(path, "config/sources/")
  end

  defp in_scan_root?(path) do
    Enum.any?(@scan_roots, fn root ->
      (String.ends_with?(root, "/") && String.starts_with?(path, root)) || path == root
    end)
  end

  defp text_file?(path) do
    Path.extname(path) in @text_extensions or Path.basename(path) in @text_basenames
  end

  defp downstream_terms do
    [
      "Mez" <> "zanine",
      "mez" <> "zanine",
      "Cit" <> "adel",
      "cit" <> "adel",
      "J" <> "ido",
      "j" <> "ido",
      "App" <> "Kit",
      "j" <> "ido_skill",
      "lower_" <> "runtime"
    ]
  end

  defp runtime_forbidden_terms do
    [
      <<126, 114, 47>>,
      "Regex" <> ".",
      "System." <> "get_env(",
      "System." <> "fetch_env(",
      "System." <> "fetch_env!(",
      "System." <> "put_env(",
      "System." <> "delete_env(",
      "String." <> "to_atom(",
      "String." <> "to_existing_atom(",
      ":" <> <<34, 35, 123>>
    ]
  end
end
