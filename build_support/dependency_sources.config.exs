%{
  deps: %{
    crucible_safetensors: %{
      path: "../../North-Shore-AI/crucible_safetensors",
      github: %{repo: "North-Shore-AI/crucible_safetensors", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_factorization: %{
      path: "../../North-Shore-AI/crucible_factorization",
      github: %{repo: "North-Shore-AI/crucible_factorization", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_tensor_patch: %{
      path: "../../North-Shore-AI/crucible_tensor_patch",
      github: %{repo: "North-Shore-AI/crucible_tensor_patch", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_model_registry: %{
      path: "../../North-Shore-AI/crucible_model_registry",
      github: %{repo: "North-Shore-AI/crucible_model_registry", branch: "main"},
      hex: "~> 0.3.1",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_signal: %{
      path: "../../North-Shore-AI/crucible_signal",
      github: %{repo: "North-Shore-AI/crucible_signal", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_tap: %{
      path: "../../North-Shore-AI/crucible_tap",
      github: %{repo: "North-Shore-AI/crucible_tap", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_signal_trace: %{
      path: "../../North-Shore-AI/crucible_signal_trace",
      github: %{repo: "North-Shore-AI/crucible_signal_trace", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_bumblebee: %{
      path: "../../North-Shore-AI/crucible_bumblebee",
      github: %{repo: "North-Shore-AI/crucible_bumblebee", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_policy: %{
      path: "../../North-Shore-AI/crucible_policy",
      github: %{repo: "North-Shore-AI/crucible_policy", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    self_hosted_inference_core: %{
      path: "../self_hosted_inference_core",
      github: %{repo: "nshkrdotcom/self_hosted_inference_core", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    self_hosted_inference_bumblebee: %{
      path: "../self_hosted_inference_bumblebee",
      github: %{repo: "nshkrdotcom/self_hosted_inference_bumblebee", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    execution_plane: %{
      path: "../execution_plane/core/execution_plane",
      github: %{
        repo: "nshkrdotcom/execution_plane",
        branch: "main",
        subdir: "core/execution_plane"
      },
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    execution_plane_process: %{
      path: "../execution_plane/runtimes/execution_plane_process",
      github: %{
        repo: "nshkrdotcom/execution_plane",
        branch: "main",
        subdir: "runtimes/execution_plane_process"
      },
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    inference: %{
      path: "../inference/apps/inference",
      github: %{repo: "nshkrdotcom/inference", branch: "main", subdir: "apps/inference"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    outer_brain_context_abi: %{
      path: "../outer_brain/core/context_abi",
      github: %{
        repo: "nshkrdotcom/outer_brain",
        branch: "main",
        subdir: "core/context_abi"
      },
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    aitrace: %{
      path: "../AITrace",
      github: %{repo: "nshkrdotcom/AITrace", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    mezzanine_ai_execution_engine: %{
      path: "../mezzanine/core/ai_execution_engine",
      github: %{
        repo: "nshkrdotcom/mezzanine",
        branch: "main",
        subdir: "core/ai_execution_engine"
      },
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    }
  }
}
