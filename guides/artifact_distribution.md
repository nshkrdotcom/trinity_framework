# Artifact Distribution

The adapted Qwen3/Sakana bundle is generated output. It is distributed through a
HuggingFace dataset repo and materialized locally by `mix trinity.artifact.fetch`.

The current public dataset repo id is still:

```text
nshkrdotcom/trinity-coordinator-adapted-qwen3-0.6b
```

That name is historical. The framework is now the implementation owner.

## Consumer Flow: Download From HuggingFace

```bash
mix trinity.artifact.fetch
```

The task reads:

```text
priv/sakana_trinity/artifact_pin.json
```

It downloads each pinned file with `hf_hub`, verifies SHA-256 checksums, and
writes the bundle to:

```text
priv/sakana_trinity/adapted_qwen3_0_6b_layer26
```

Custom destination:

```bash
mix trinity.artifact.fetch --dest /opt/trinity/bundles/v1.0.0
```

Custom pin:

```bash
mix trinity.artifact.fetch --pin priv/forks/my_pin.json
```

Offline cache-only mode:

```bash
HF_HUB_OFFLINE=1 mix trinity.artifact.fetch --offline
```

## Publisher Flow: Upload To HuggingFace

Publisher work requires `HF_TOKEN` with write access. Keep token usage in the
explicit shell/IEx session.

Start IEx with caller-owned credentials available to the session. Inside IEx:

```elixir
artifact_dir = "priv/sakana_trinity/adapted_qwen3_0_6b_layer26"
repo_id = "nshkrdotcom/trinity-coordinator-adapted-qwen3-0.6b"
token = caller_owned_huggingface_token

{:ok, _repo} =
  HfHub.Repo.create(repo_id,
    repo_type: :dataset,
    private: false,
    exist_ok: true,
    token: token
  )

{:ok, info} =
  HfHub.Commit.upload_folder(
    artifact_dir,
    repo_id,
    token: token,
    repo_type: :dataset,
    commit_message: "publish adapted Qwen3/Sakana bundle",
    ignore_patterns: ["*.log.jsonl", "*.tmp", ".DS_Store"],
    max_workers: 1,
    lfs_upload_timeout: 60 * 60 * 1000,
    lfs_task_timeout: 65 * 60 * 1000
  )

IO.inspect(info, label: "commit")

{:ok, %Req.Response{status: 200, body: tree}} =
  Req.get("https://huggingface.co/api/datasets/#{repo_id}/tree/main",
    params: [recursive: true]
  )

true = length(tree) >= 11

{:ok, _tag} =
  HfHub.Git.create_tag(repo_id, "v1.0.0",
    repo_type: :dataset,
    message: "Adapted Qwen3/Sakana bundle",
    token: token
  )
```

Do not tag until the tree verification succeeds.

## Pin Regeneration

After publishing a new revision, regenerate and commit
`priv/sakana_trinity/artifact_pin.json`. If no build-support helper exists for
the target revision, create the pin from the uploaded manifest and exact
per-file SHA-256 values. Consumers rely on this pin for checksum verification.
