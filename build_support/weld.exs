Code.require_file("workspace_contract.exs", __DIR__)

defmodule TrinityFramework.Build.WeldContract do
  @moduledoc false

  alias TrinityFramework.Build.WorkspaceContract

  @manifest_dependencies [
    crucible_safetensors: [requirement: "~> 0.1.0", opts: []],
    crucible_factorization: [requirement: "~> 0.1.0", opts: []],
    crucible_tensor_patch: [requirement: "~> 0.1.0", opts: []],
    crucible_model_registry: [requirement: "~> 0.3.1", opts: []],
    crucible_mechinterp: [requirement: "~> 0.1.0", opts: [override: true]],
    crucible_provider_contracts: [requirement: "~> 0.1.0", opts: [override: true]],
    crucible_signal: [requirement: "~> 0.1.0", opts: [override: true]],
    crucible_tap: [requirement: "~> 0.1.0", opts: [override: true]],
    crucible_signal_trace: [requirement: "~> 0.1.0", opts: [override: true]],
    crucible_bumblebee: [requirement: "~> 0.1.0", opts: [override: true]],
    crucible_policy: [requirement: "~> 0.1.0", opts: [override: true]],
    self_hosted_inference_core: [requirement: "~> 0.1.0", opts: []],
    self_hosted_inference_bumblebee: [requirement: "~> 0.1.0", opts: []],
    execution_plane: [requirement: "~> 0.1.0", opts: []],
    execution_plane_process: [requirement: "~> 0.1.0", opts: []],
    inference: [requirement: "~> 0.1.0", opts: []],
    outer_brain_context_abi: [requirement: "~> 0.1.0", opts: [override: true]],
    aitrace: [requirement: "~> 0.1.0", opts: []]
  ]

  @artifact_docs [
    "README.md",
    "CHANGELOG.md",
    "guides/onboarding.md",
    "guides/current_direction.md",
    "guides/crucible_path.md",
    "guides/crucible_artifact_layout.md",
    "guides/crucible_capability_degradation.md",
    "guides/crucible_provider_boundary.md",
    "guides/crucible_replay.md",
    "guides/crucible_testing.md",
    "guides/crucible_mechinterp.md",
    "guides/system_architecture.md",
    "guides/service_buildout.md",
    "guides/router_fabric.md",
    "guides/operations_qc.md",
    "guides/artifact_distribution.md",
    "guides/artifacts_and_export.md",
    "guides/runtime_profiles.md",
    "guides/evals.md",
    "guides/python_parity_reconstruction.md",
    "guides/python_torch_trace_provider.md",
    "guides/stage_checks_and_tolerances.md",
    "guides/svd_generation_runbook.md",
    "guides/provider_service_hardening.md",
    "guides/trinity_live_inspect.md",
    "guides/troubleshooting.md",
    "docs/agent_slot_provider_mapping.md",
    "docs/bumblebee_unpin_playbook.md",
    "docs/configurable_provider_pools.md",
    "docs/coordination_head_variants.md",
    "docs/elixir_svd_decomposition.md",
    "docs/production_qwen_slm_profile.md",
    "docs/production_runbook.md",
    "docs/provider_smoke_tests.md",
    "docs/adaptation_readiness_loop.md",
    "docs/router_reflex.md",
    "docs/sakana_adapted_artifact_plan.md",
    "docs/sakana_svd_byte_match_rigor_plan.md",
    "docs/sakana_svd_parity_debug_checklist.md",
    "docs/sakana_fitness_export.md",
    "docs/trace_persistence.md"
  ]

  @artifact_assets [
    "assets/trinity_framework.svg",
    "LICENSE",
    "priv/sakana_trinity/artifact_pin.json",
    "priv/sakana_trinity/reference/sakana_python_reference_manifest.json",
    "examples/qwen_router_prompt_eval/fixtures",
    "tools/python/crucible_torch_trace.py"
  ]

  def manifest do
    [
      workspace: [
        root: "..",
        project_globs: WorkspaceContract.active_project_globs()
      ],
      classify: [
        tooling: ["."]
      ],
      publication: [
        internal_only: ["."]
      ],
      dependencies: @manifest_dependencies,
      artifacts: [
        trinity_framework: artifact()
      ]
    ]
  end

  def artifact do
    [
      roots: ["."],
      package: [
        name: "trinity_framework",
        otp_app: :trinity_framework,
        version: "0.1.0",
        description: "Reusable TRINITY router and coordination framework"
      ],
      output: [
        docs: @artifact_docs,
        assets: @artifact_assets
      ],
      verify: [
        artifact_tests: ["test"],
        hex_build: false,
        hex_publish: false
      ]
    ]
  end
end

TrinityFramework.Build.WeldContract.manifest()
