defmodule Trinity.Ops.CrucibleMechInterpTasks do
  @moduledoc """
  Operator tasks for local, reproducible Crucible mech-interp workflows.

  These commands use a deterministic tiny GPT-2 model built through
  Bumblebee/Axon, then call the CrucibleBumblebee and CrucibleMechInterp
  primitives that production providers use.
  """

  alias Crucible.TensorSummary

  alias CrucibleBumblebee.{
    ActivationMapper,
    ExampleSurface,
    ForwardRunner,
    GenerationTrace,
    ModelBundle,
    TapCompiler
  }

  alias CrucibleMechInterp.{ActivationCache, LogitLens, Patching}
  alias CrucibleTap.TapPlan
  alias Trinity.SakanaPipeline.ArtifactIO

  @default_artifact_root "tmp/trinity_crucible/mechinterp"
  @default_input_ids [1, 2, 3]
  @hidden_size 4
  @num_blocks 2
  @vocab_size 32

  @spec capture(keyword()) :: :ok
  def capture(opts) do
    start_app!()
    ensure_tiny_fixture!(opts)

    trace_id = Keyword.get(opts, :trace_name, "tiny-gpt2-capture")
    out = output_path(opts, "capture_report.json")
    trace_out = trace_output_path(opts, "capture_trace.json")
    input_ids = input_ids(opts, :input_ids)

    {:ok, trace} = run_tiny_forward(capture_tap_plan(), input_ids, trace_id)
    trace_payload = forward_trace_payload(trace, input_ids)
    report = capture_report(trace, input_ids, trace_out)

    ArtifactIO.write_json!(trace_out, normalize_for_json(trace_payload))
    ArtifactIO.write_json!(out, normalize_for_json(report))

    Mix.shell().info("trinity.crucible.capture: #{out}")
    :ok
  end

  @spec generation_trace(keyword()) :: :ok
  def generation_trace(opts) do
    start_app!()
    ensure_tiny_fixture!(opts)

    out = output_path(opts, "generation_trace_report.json")
    trace_out = trace_output_path(opts, "generation_trace.json")
    input_ids = input_ids(opts, :input_ids)
    max_new_tokens = Keyword.get(opts, :max_new_tokens, 2)
    top_k = Keyword.get(opts, :top_k, 5)

    bundle = tiny_gpt2_generation_bundle(length(input_ids))

    {:ok, trace} =
      GenerationTrace.run_inputs(bundle, inputs(input_ids),
        max_new_tokens: max_new_tokens,
        top_k: top_k
      )

    {:ok, cache} = GenerationTrace.to_activation_cache(trace)
    trace_payload = generation_trace_payload(trace, input_ids)
    report = generation_report(trace, cache, input_ids, trace_out)

    ArtifactIO.write_json!(trace_out, normalize_for_json(trace_payload))
    ArtifactIO.write_json!(out, normalize_for_json(report))

    Mix.shell().info("trinity.crucible.generation_trace: #{out}")
    :ok
  end

  @spec logit_lens(keyword()) :: :ok
  def logit_lens(opts) do
    start_app!()
    ensure_tiny_fixture!(opts)

    out = output_path(opts, "logit_lens_report.json")
    input_ids = input_ids(opts, :input_ids)
    top_k = Keyword.get(opts, :top_k, 5)

    {_model, params, outputs} =
      tiny_gpt2_outputs(input_ids, output_hidden_states: true)

    cache = activation_cache_from_outputs(outputs, params)
    {logits, labels} = LogitLens.project(cache)

    report =
      logit_lens_report(cache, logits, labels,
        input_ids: input_ids,
        top_k: top_k
      )

    ArtifactIO.write_json!(out, normalize_for_json(report))
    Mix.shell().info("trinity.crucible.logit_lens: #{out}")
    :ok
  end

  @spec patch(keyword()) :: :ok
  def patch(opts) do
    start_app!()
    ensure_tiny_fixture!(opts)

    out = output_path(opts, "patch_report.json")
    clean_ids = input_ids(opts, :clean_input_ids, @default_input_ids)
    corrupted_ids = input_ids(opts, :corrupted_input_ids, [1, 2, 4])
    activation_name = Keyword.get(opts, :patch_activation, "blocks.0.hook_resid_pre")
    pos = Keyword.get(opts, :patch_pos, 1)

    {_model, clean_params, clean_outputs} =
      tiny_gpt2_outputs(clean_ids, output_hidden_states: true)

    {_model, corrupted_params, corrupted_outputs} =
      tiny_gpt2_outputs(corrupted_ids, output_hidden_states: true)

    clean_cache = activation_cache_from_outputs(clean_outputs, clean_params)
    corrupted_cache = activation_cache_from_outputs(corrupted_outputs, corrupted_params)

    patched_cache =
      Patching.patch_cache(corrupted_cache, clean_cache, activation_name, %{pos: pos})

    report =
      patch_report(clean_cache, corrupted_cache, patched_cache,
        activation_name: activation_name,
        pos: pos,
        clean_input_ids: clean_ids,
        corrupted_input_ids: corrupted_ids
      )

    ArtifactIO.write_json!(out, normalize_for_json(report))
    Mix.shell().info("trinity.crucible.patch: #{out}")
    :ok
  end

  defp run_tiny_forward(%TapPlan{} = plan, input_ids, trace_id) do
    surface = ExampleSurface.surface(num_blocks: @num_blocks)
    {:ok, compiled} = TapCompiler.compile(plan, surface)

    {_model, params, predict_fun} =
      tiny_gpt2_predict_fun(length(input_ids), compiled.global_layer_options)

    ForwardRunner.run(fn inputs -> predict_fun.(params, inputs) end, inputs(input_ids), plan,
      trace_id: trace_id,
      model_id: "tiny-gpt2",
      surface: surface
    )
  end

  defp tiny_gpt2_outputs(input_ids, global_layer_options) do
    {model, params, predict_fun} = tiny_gpt2_predict_fun(length(input_ids), global_layer_options)
    {model, params, predict_fun.(params, inputs(input_ids))}
  end

  defp tiny_gpt2_predict_fun(sequence_length, global_layer_options) do
    spec = tiny_gpt2_spec()
    model = Bumblebee.build_model(spec)
    {init_fn, predict_fun} = Axon.build(model, global_layer_options: global_layer_options)
    params = init_fn.(template(sequence_length), Axon.ModelState.empty())
    {model, params, predict_fun}
  end

  defp tiny_gpt2_generation_bundle(sequence_length) do
    spec = tiny_gpt2_spec()
    model = Bumblebee.build_model(spec)
    {init_fn, _predict_fun} = Axon.build(model)
    params = init_fn.(template(sequence_length), Axon.ModelState.empty())

    %ModelBundle{
      model_id: "tiny-gpt2",
      model: model,
      params: params,
      spec: spec,
      tokenizer: nil,
      model_family: :gpt2,
      backend: :binary
    }
  end

  defp tiny_gpt2_spec do
    Bumblebee.configure(Bumblebee.Text.Gpt2,
      architecture: :for_causal_language_modeling,
      vocab_size: @vocab_size,
      hidden_size: @hidden_size,
      num_blocks: @num_blocks,
      num_attention_heads: 2,
      max_positions: 8,
      intermediate_size: 8,
      dropout_rate: 0.0,
      embeddings_dropout_rate: 0.0,
      attention_dropout_rate: 0.0
    )
  end

  defp capture_tap_plan do
    TapPlan.new!(
      [
        [id: "hidden", signal_type: :middle_residuals, layers: [0]],
        [id: "attention-pattern", signal_type: :attention_weights, layers: [0]],
        [id: "attention-q", signal_type: :attention_q, layers: [0]],
        [id: "attention-k", signal_type: :attention_k, layers: [0]],
        [id: "attention-v", signal_type: :attention_v, layers: [0]],
        [id: "attention-scores", signal_type: :attention_scores, layers: [0]],
        [id: "attention-z", signal_type: :head_outputs, layers: [0]],
        [id: "mlp-pre", signal_type: :mlp_gates, layers: [0]],
        [id: "mlp-post", signal_type: :mlp_activation, layers: [0]],
        [
          id: "resid-pre",
          signal_type: :residual_stream,
          layers: [0],
          activation_name: "blocks.0.hook_resid_pre"
        ],
        [
          id: "resid-mid",
          signal_type: :residual_stream,
          layers: [0],
          activation_name: "blocks.0.hook_resid_mid"
        ],
        [id: "final-norm", signal_type: :norm_telemetry, layers: [:final]],
        [id: "logits", signal_type: :final_logits, layers: [:final]]
      ],
      plan_id: "trinity-crucible-tiny-gpt2-capture"
    )
  end

  defp activation_cache_from_outputs(outputs, params) do
    hidden_states = outputs.hidden_states |> Tuple.to_list()

    activations =
      hidden_states
      |> Enum.with_index()
      |> Map.new(fn {tensor, index} ->
        metadata = ActivationMapper.hidden_state(index, length(hidden_states))
        {metadata.activation_name, tensor}
      end)

    ActivationCache.new!(activations,
      model_info: %{
        n_layers: @num_blocks,
        final_norm: final_norm(params),
        unembedding: parameter!(params, "language_modeling_head.output", "kernel"),
        unembedding_orientation: :d_vocab_d_model
      },
      metadata: %{
        source: :tiny_gpt2_forward,
        model_id: "tiny-gpt2",
        provider_kind: :elixir_bumblebee
      }
    )
  end

  defp final_norm(params) do
    %{
      type: :layer_norm,
      weight: parameter!(params, "norm", "gamma"),
      bias: parameter!(params, "norm", "beta"),
      eps: 1.0e-5
    }
  end

  defp parameter!(%Axon.ModelState{data: data}, layer, name) do
    data
    |> Map.fetch!(layer)
    |> Map.fetch!(name)
  end

  defp parameter!(%{data: data}, layer, name) do
    data
    |> Map.fetch!(layer)
    |> Map.fetch!(name)
  end

  defp parameter!(%{parameters: parameters}, layer, name) do
    parameters
    |> Map.fetch!(layer)
    |> Map.fetch!(name)
  end

  defp capture_report(trace, input_ids, trace_out) do
    activation_names = activation_names(trace)

    %{
      schema: "trinity.crucible.capture.v1",
      status: :ok,
      model_id: trace.model_id,
      provider_kind: :elixir_bumblebee,
      fixture: :tiny_gpt2,
      input_ids: input_ids,
      trace_id: trace.trace_id,
      trace_path: trace_out,
      signal_count: length(trace.signals),
      activation_names: activation_names,
      capture_groups: capture_groups(activation_names),
      compiled_taps: get_in(trace.metadata, [:compiled_taps])
    }
  end

  defp generation_report(trace, cache, input_ids, trace_out) do
    logits = ActivationCache.get!(cache, "unembed.hook_logits")

    %{
      schema: "trinity.crucible.generation_trace.v1",
      status: :ok,
      model_id: "tiny-gpt2",
      provider_kind: :elixir_bumblebee,
      fixture: :tiny_gpt2,
      input_ids: input_ids,
      trace_path: trace_out,
      generated_token_ids: trace.generated_token_ids,
      cache_offsets: Enum.map(trace.steps, & &1.cache_offset),
      generation_success_level: trace.generation_success_level,
      activation_cache: %{
        keys: ActivationCache.keys(cache),
        logits: tensor_summary(logits)
      },
      trace_metadata: trace.trace_metadata
    }
  end

  defp logit_lens_report(cache, logits, labels, opts) do
    input_ids = Keyword.fetch!(opts, :input_ids)
    top_k = Keyword.fetch!(opts, :top_k)

    %{
      schema: "trinity.crucible.logit_lens.v1",
      status: :ok,
      model_id: "tiny-gpt2",
      provider_kind: :elixir_bumblebee,
      fixture: :tiny_gpt2,
      input_ids: input_ids,
      activation_cache_keys: ActivationCache.keys(cache),
      labels: labels,
      logits_shape: Tuple.to_list(Nx.shape(logits)),
      top_k_by_label: top_k_by_label(logits, labels, length(input_ids), top_k)
    }
  end

  defp patch_report(clean_cache, corrupted_cache, patched_cache, opts) do
    activation_name = Keyword.fetch!(opts, :activation_name)
    pos = Keyword.fetch!(opts, :pos)

    clean = ActivationCache.get!(clean_cache, activation_name)
    corrupted = ActivationCache.get!(corrupted_cache, activation_name)
    patched = ActivationCache.get!(patched_cache, activation_name)
    patched_delta = max_abs_difference(patched, corrupted)

    clean_match_delta =
      max_abs_difference(position_slice(patched, pos), position_slice(clean, pos))

    %{
      schema: "trinity.crucible.patch.v1",
      status: :ok,
      model_id: "tiny-gpt2",
      provider_kind: :elixir_bumblebee,
      fixture: :tiny_gpt2,
      clean_input_ids: Keyword.fetch!(opts, :clean_input_ids),
      corrupted_input_ids: Keyword.fetch!(opts, :corrupted_input_ids),
      activation_name: activation_name,
      indices: %{pos: pos},
      corrupted_summary: tensor_summary(corrupted),
      clean_summary: tensor_summary(clean),
      patched_summary: tensor_summary(patched),
      patched_delta_max_abs: patched_delta,
      patched_position_clean_delta_max_abs: clean_match_delta,
      patched_position_matches_clean?: clean_match_delta == 0.0
    }
  end

  defp forward_trace_payload(trace, input_ids) do
    %{
      schema: "trinity.crucible.forward_trace.summary.v1",
      trace_id: trace.trace_id,
      model_id: trace.model_id,
      fixture: :tiny_gpt2,
      input_ids: input_ids,
      tap_plan_ref: trace.tap_plan_ref,
      final_logits_signal_id: trace.final_logits && trace.final_logits.signal_id,
      cache_summary: trace.cache_summary,
      signals: Enum.map(trace.signals, &signal_payload/1),
      layer_trajectory: trace.layer_trajectory,
      metadata: trace.metadata
    }
  end

  defp generation_trace_payload(trace, input_ids) do
    %{
      schema: "trinity.crucible.generation_trace.summary.v1",
      model_id: "tiny-gpt2",
      fixture: :tiny_gpt2,
      input_ids: input_ids,
      generated_token_ids: trace.generated_token_ids,
      decoded_text: trace.decoded_text,
      generation_success_level: trace.generation_success_level,
      optional_internals: trace.optional_internals,
      trace_metadata: trace.trace_metadata,
      steps: Enum.map(trace.steps, &GenerationTrace.public_step/1)
    }
  end

  defp signal_payload(signal) do
    %{
      signal_id: signal.signal_id,
      signal_type: signal.signal_type,
      activation_name: activation_name(signal),
      layer_index: signal.layer_index,
      node_name: signal.node_name,
      capture_method: signal.capture_method,
      capability_status: signal.capability_status,
      shape: signal.shape,
      rank: signal.rank,
      dtype: signal.dtype,
      tensor_summary: signal.tensor_summary,
      metadata: signal.metadata
    }
  end

  defp top_k_by_label(logits, labels, prompt_length, top_k) do
    labels
    |> Enum.with_index()
    |> Enum.map(fn {label, index} ->
      label_logits =
        logits
        |> Nx.slice([index, 0, prompt_length - 1, 0], [1, 1, 1, @vocab_size])
        |> Nx.reshape({@vocab_size})

      %{label: label, summary: TensorSummary.compute(label_logits, entropy: true, top_k: top_k)}
    end)
  end

  defp tensor_summary(%Nx.Tensor{} = tensor), do: TensorSummary.compute(tensor, entropy: false)

  defp position_slice(tensor, pos), do: Nx.slice_along_axis(tensor, pos, 1, axis: 1)

  defp max_abs_difference(left, right) do
    left
    |> Nx.subtract(right)
    |> Nx.abs()
    |> Nx.reduce_max()
    |> Nx.to_number()
  end

  defp activation_names(trace) do
    trace.signals
    |> Enum.map(&activation_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp activation_name(signal) do
    Map.get(signal.metadata, :activation_name) || Map.get(signal.metadata, "activation_name")
  end

  defp capture_groups(activation_names) do
    []
    |> maybe_group(:attention_qkv, Enum.any?(activation_names, &attention_qkv?/1))
    |> maybe_group(
      :attention_scores,
      Enum.any?(activation_names, &String.contains?(&1, "hook_attn_scores"))
    )
    |> maybe_group(
      :attention_pattern,
      Enum.any?(activation_names, &String.contains?(&1, "hook_pattern"))
    )
    |> maybe_group(
      :attention_z,
      Enum.any?(activation_names, &String.ends_with?(&1, ".attn.hook_z"))
    )
    |> maybe_group(:mlp_activations, Enum.any?(activation_names, &String.contains?(&1, ".mlp.")))
    |> maybe_group(
      :residual_streams,
      Enum.any?(activation_names, &String.contains?(&1, "hook_resid"))
    )
    |> maybe_group(
      :norm_telemetry,
      Enum.any?(activation_names, &String.starts_with?(&1, "ln_final."))
    )
    |> maybe_group(:final_logits, "unembed.hook_logits" in activation_names)
    |> Enum.reverse()
  end

  defp attention_qkv?(name) do
    String.ends_with?(name, ".attn.hook_q") or
      String.ends_with?(name, ".attn.hook_k") or
      String.ends_with?(name, ".attn.hook_v")
  end

  defp maybe_group(groups, group, true), do: [group | groups]
  defp maybe_group(groups, _group, false), do: groups

  defp output_path(opts, filename) do
    Keyword.get(opts, :out) || Path.join([artifact_root(opts), "reports", filename])
  end

  defp trace_output_path(opts, filename) do
    Keyword.get(opts, :trace_out) || Path.join([artifact_root(opts), "traces", filename])
  end

  defp artifact_root(opts), do: Keyword.get(opts, :artifact_root, @default_artifact_root)

  defp ensure_tiny_fixture!(opts) do
    case Keyword.get(opts, :fixture, "tiny_gpt2") do
      "tiny_gpt2" -> :ok
      :tiny_gpt2 -> :ok
      other -> Mix.raise("unsupported Crucible mech-interp fixture: #{inspect(other)}")
    end
  end

  defp input_ids(opts, key, default \\ @default_input_ids) do
    opts
    |> Keyword.get(key)
    |> parse_input_ids(default)
  end

  defp parse_input_ids(nil, default), do: default

  defp parse_input_ids(value, _default) when is_binary(value) do
    ids =
      value
      |> String.split([",", " "], trim: true)
      |> Enum.map(&parse_token_id!/1)

    if ids == [], do: Mix.raise("input ids cannot be empty"), else: ids
  end

  defp parse_token_id!(value) do
    case Integer.parse(value) do
      {id, ""} when id >= 0 and id < @vocab_size ->
        id

      _other ->
        Mix.raise("invalid tiny GPT-2 token id #{inspect(value)}; expected 0..#{@vocab_size - 1}")
    end
  end

  defp inputs(input_ids), do: %{"input_ids" => Nx.tensor([input_ids], type: :u32)}
  defp template(sequence_length), do: %{"input_ids" => Nx.template({1, sequence_length}, :u32)}

  defp start_app!, do: Mix.Task.run("app.start")

  defp normalize_for_json(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> normalize_for_json()
  end

  defp normalize_for_json(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {normalize_json_key(key), normalize_for_json(item)} end)
  end

  defp normalize_for_json(value) when is_list(value), do: Enum.map(value, &normalize_for_json/1)
  defp normalize_for_json(value) when is_tuple(value), do: Tuple.to_list(value)
  defp normalize_for_json(value) when is_boolean(value), do: value
  defp normalize_for_json(nil), do: nil
  defp normalize_for_json(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_for_json(value), do: value

  defp normalize_json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_json_key(key), do: key
end
