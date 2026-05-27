defmodule Trinity.Crucible.TapPlanBuilder do
  @moduledoc """
  Builds reusable Crucible tap plans from Trinity request context.
  """

  alias CrucibleTap.{TapPlan, TapSpec}
  alias Trinity.Crucible.RequestContext

  @default_layers [4, 8, 12]
  @planning_layers [6, 12, 18]
  @verification_layers [8, 16, 24]

  @spec build(RequestContext.t() | keyword() | map(), keyword() | map()) :: {:ok, TapPlan.t()}
  def build(context, runtime_profile \\ [])

  def build(%RequestContext{} = context, runtime_profile) do
    plan_id = "trinity:crucible:#{context.task_type}:turn:#{context.turn}"

    specs =
      context
      |> specs_for(runtime_profile)
      |> Enum.map(&TapSpec.new!/1)

    {:ok,
     TapPlan.new!(specs,
       plan_id: plan_id,
       metadata: %{
         owner: :trinity_framework,
         task_type: context.task_type,
         turn: context.turn,
         runtime_profile: runtime_profile_name(runtime_profile)
       }
     )}
  end

  def build(attrs, runtime_profile) when is_list(attrs) or is_map(attrs) do
    attrs |> RequestContext.new() |> build(runtime_profile)
  end

  @spec build!(RequestContext.t() | keyword() | map(), keyword() | map()) :: TapPlan.t()
  def build!(context, runtime_profile \\ []) do
    {:ok, plan} = build(context, runtime_profile)
    plan
  end

  defp specs_for(%RequestContext{task_type: :verification} = context, runtime_profile) do
    [
      final_logits_spec(context),
      verifier_signal_spec(context),
      trajectory_spec(context, runtime_profile, @verification_layers),
      logit_lens_spec(context, 16)
    ]
  end

  defp specs_for(%RequestContext{task_type: :review} = context, runtime_profile) do
    [
      final_logits_spec(context),
      verifier_signal_spec(context),
      trajectory_spec(context, runtime_profile, @verification_layers)
    ]
  end

  defp specs_for(%RequestContext{task_type: :planning} = context, runtime_profile) do
    [
      final_logits_spec(context),
      trajectory_spec(context, runtime_profile, @planning_layers),
      logit_lens_spec(context, 12)
    ]
  end

  defp specs_for(%RequestContext{} = context, runtime_profile) do
    [
      final_logits_spec(context),
      trajectory_spec(context, runtime_profile, @default_layers)
    ]
  end

  defp final_logits_spec(%RequestContext{} = context) do
    %{
      id: "trinity:final_logits:turn:#{context.turn}",
      signal_type: :final_logits,
      capture_mode: :summary,
      kind: :read,
      required?: true,
      metadata: %{reason: :route_decision}
    }
  end

  defp verifier_signal_spec(%RequestContext{} = context) do
    %{
      id: "trinity:verifier_signal:turn:#{context.turn}",
      signal_type: :verifier_signal,
      capture_mode: :summary,
      kind: :read,
      required?: false,
      metadata: %{reason: :safety_check}
    }
  end

  defp logit_lens_spec(%RequestContext{} = context, layer) do
    %{
      id: "trinity:logit_lens:layer:#{layer}:turn:#{context.turn}",
      signal_type: :logit_lens_intermediate,
      layers: [layer],
      capture_mode: :summary,
      kind: :read,
      required?: false,
      metadata: %{reason: :trajectory_stability}
    }
  end

  defp trajectory_spec(%RequestContext{} = context, runtime_profile, layers) do
    %{
      id: "trinity:trajectory:turn:#{context.turn}",
      signal_type: :middle_residuals,
      layers: profile_layers(runtime_profile, layers),
      capture_mode: :compressed_vector,
      kind: :read,
      required?: false,
      metadata: %{trajectory_id: "trinity:trajectory:#{context.turn}", drift?: true}
    }
  end

  defp profile_layers(runtime_profile, fallback) when is_map(runtime_profile) do
    case field(runtime_profile, :trajectory_layers) do
      layers when is_list(layers) and layers != [] -> layers
      _other -> fallback
    end
  end

  defp profile_layers(_runtime_profile, fallback), do: fallback

  defp runtime_profile_name(runtime_profile) when is_map(runtime_profile),
    do: field(runtime_profile, :name, :unknown)

  defp runtime_profile_name(runtime_profile) when is_atom(runtime_profile), do: runtime_profile
  defp runtime_profile_name(runtime_profile) when is_binary(runtime_profile), do: runtime_profile
  defp runtime_profile_name(_runtime_profile), do: :unknown

  defp field(map, field, default \\ nil),
    do: Map.get(map, field, Map.get(map, Atom.to_string(field), default))
end
