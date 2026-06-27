defmodule Trinity.Crucible.ArtifactPaths do
  @moduledoc """
  Durable artifact layout helpers for Trinity Crucible operator commands.
  """

  @derive Jason.Encoder
  defstruct root: "tmp/crucible_v5",
            trace_name: nil,
            traces_dir: nil,
            reports_dir: nil,
            transcripts_dir: nil,
            policy_decisions_dir: nil,
            route_decisions_dir: nil,
            index_path: nil

  @type t :: %__MODULE__{}

  @spec new(keyword() | map()) :: t()
  def new(attrs \\ []) when is_list(attrs) or is_map(attrs) do
    attrs = attrs_map(attrs)
    root = field(attrs, :root, "tmp/crucible_v5")
    trace_name = field(attrs, :trace_name)

    %__MODULE__{
      root: root,
      trace_name: trace_name,
      traces_dir: Path.join(root, "traces"),
      reports_dir: Path.join(root, "reports"),
      transcripts_dir: Path.join(root, "transcripts"),
      policy_decisions_dir: Path.join(root, "policy_decisions"),
      route_decisions_dir: Path.join(root, "route_decisions"),
      index_path: Path.join(root, "ARTIFACT_INDEX.md")
    }
  end

  @spec ensure!(t()) :: t()
  def ensure!(%__MODULE__{} = paths) do
    [
      paths.root,
      paths.traces_dir,
      paths.reports_dir,
      paths.transcripts_dir,
      paths.policy_decisions_dir,
      paths.route_decisions_dir,
      Path.dirname(paths.index_path)
    ]
    |> Enum.uniq()
    |> Enum.each(&File.mkdir_p!/1)

    paths
  end

  @spec report_path(t(), String.t()) :: String.t()
  def report_path(%__MODULE__{} = paths, filename), do: Path.join(paths.reports_dir, filename)

  @spec trace_path(t(), String.t() | nil) :: String.t()
  def trace_path(%__MODULE__{} = paths, filename \\ nil) do
    name = filename || "#{paths.trace_name || "trace"}.jsonl"
    Path.join(paths.traces_dir, name)
  end

  @spec policy_decision_path(t(), String.t()) :: String.t()
  def policy_decision_path(%__MODULE__{} = paths, filename),
    do: Path.join(paths.policy_decisions_dir, filename)

  @spec route_decision_path(t(), String.t()) :: String.t()
  def route_decision_path(%__MODULE__{} = paths, filename),
    do: Path.join(paths.route_decisions_dir, filename)

  @spec write_artifact_index!(t(), [map()]) :: String.t()
  def write_artifact_index!(%__MODULE__{} = paths, entries) when is_list(entries) do
    ensure!(paths)

    body =
      ["# Trinity Crucible Artifact Index", ""]
      |> Kernel.++(Enum.map(entries, &index_line/1))
      |> Enum.join("\n")

    File.write!(paths.index_path, body <> "\n")
    paths.index_path
  end

  defp index_line(entry) when is_map(entry) do
    label = field(entry, :label, "artifact")
    path = field(entry, :path, "")
    "- #{label}: `#{path}`"
  end

  defp attrs_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp attrs_map(attrs) when is_map(attrs), do: attrs

  defp field(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
