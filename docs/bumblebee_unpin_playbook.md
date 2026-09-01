# Bumblebee Dependency Playbook

`trinity_framework` does not own Bumblebee directly in the root package. Qwen
runtime loading is isolated behind `self_hosted_inference_bumblebee`, selected
through dependency source manifests.

## Current Rule

- Keep the portable Hex tuple as the committed default; use Mix Workspace Ops
  for operator-selected local or Git source substitution.
- Use path or GitHub sources only through that manifest.
- Publish mode must resolve package dependencies through Hex where configured.

## Upgrade Checklist

1. Update the reusable runtime package first.
2. Run its own compile, tests, Credo, Dialyzer, and docs gates.
3. Update this framework dependency manifest only after the runtime package is
   published or intentionally selected by path for local testing.
4. Run `mix ci` from the framework root.
5. Run CUDA and adapted-bundle HITL checks on a CUDA host.

Do not add one-off dependency selection logic to `mix.exs`.
