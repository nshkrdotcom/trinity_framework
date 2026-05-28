#!/usr/bin/env python3
"""Emit Crucible JSONL traces from real PyTorch/Transformers model execution."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import re
import time
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "crucible.trace.v4"
PROVIDER_KIND = "python_pytorch"
BACKEND = "pytorch"


def utc_now() -> str:
    return dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def safe_name(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", value).strip("_") or "trace"


def sha256_text(value: str) -> str:
    return "sha256:" + hashlib.sha256(value.encode("utf-8")).hexdigest()


def tensor_digest(tensor: Any) -> str:
    array = tensor.detach().cpu().contiguous().numpy()
    digest = hashlib.sha256()
    digest.update(str(tuple(array.shape)).encode("utf-8"))
    digest.update(str(array.dtype).encode("utf-8"))
    digest.update(array.tobytes())
    return "sha256:" + digest.hexdigest()


def json_safe(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(key): json_safe(item) for key, item in value.items()}

    if isinstance(value, (list, tuple)):
        return [json_safe(item) for item in value]

    if isinstance(value, (str, int, bool)) or value is None:
        return value

    if isinstance(value, float):
        if math.isfinite(value):
            return value

        return None

    if hasattr(value, "item"):
        return json_safe(value.item())

    return str(value)


def summarize_tensor(tensor: Any, *, entropy: bool = False, top_k: int = 0, tokenizer: Any = None) -> dict[str, Any]:
    import torch

    detached = tensor.detach().float().cpu()
    flat = detached.reshape(-1)
    finite = flat[torch.isfinite(flat)]
    shape = list(detached.shape)

    summary = {
        "shape": shape,
        "rank": len(shape),
        "dtype": str(tensor.dtype).replace("torch.", ""),
        "min": None,
        "max": None,
        "mean": None,
        "stddev": None,
        "norm_l2": None,
        "entropy": None,
        "top_k": [],
        "digest": tensor_digest(tensor),
    }

    if finite.numel() > 0:
        summary["min"] = float(torch.min(finite).item())
        summary["max"] = float(torch.max(finite).item())
        summary["mean"] = float(torch.mean(finite).item())
        summary["stddev"] = float(torch.std(finite, unbiased=False).item())
        summary["norm_l2"] = float(torch.linalg.vector_norm(finite).item())

        if entropy:
            probabilities = torch.softmax(finite, dim=-1)
            summary["entropy"] = float(-(probabilities * torch.log(probabilities.clamp_min(1.0e-12))).sum().item())

    if top_k > 0 and flat.numel() > 0:
        k = min(top_k, flat.numel())
        logits, indices = torch.topk(flat, k)
        probabilities = torch.softmax(flat, dim=-1)

        rows = []
        for logit, index in zip(logits, indices, strict=True):
            token_id = int(index.item())
            row = {
                "token_id": token_id,
                "logit": float(logit.item()),
                "probability": float(probabilities[index].item()),
            }

            if tokenizer is not None:
                row["token"] = tokenizer.decode([token_id], clean_up_tokenization_spaces=False)

            rows.append(row)

        summary["top_k"] = rows

    return summary


def logsumexp(tensor: Any) -> float:
    import torch

    flat = tensor.detach().float().cpu().reshape(-1)
    max_value = torch.max(flat)
    return float((torch.log(torch.sum(torch.exp(flat - max_value))) + max_value).item())


def signal_record(
    *,
    trace_id: str,
    run_id: str,
    model_id: str,
    model_family: str,
    signal_type: str,
    signal_id: str,
    tensor: Any | None,
    node_name: str,
    layer_index: int | None = None,
    token_index: int | None = None,
    capture_method: str = "transformers_output",
    tensor_summary: dict[str, Any] | None = None,
    metadata: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if tensor_summary is None and tensor is not None:
        tensor_summary = summarize_tensor(tensor)

    shape = tensor_summary.get("shape") if tensor_summary else None
    rank = tensor_summary.get("rank") if tensor_summary else None
    dtype = tensor_summary.get("dtype") if tensor_summary else None

    return {
        "signal_id": signal_id,
        "trace_id": trace_id,
        "run_id": run_id,
        "signal_type": signal_type,
        "provider_kind": PROVIDER_KIND,
        "model_id": model_id,
        "model_family": model_family,
        "backend": BACKEND,
        "dtype": dtype,
        "shape": shape,
        "rank": rank,
        "device": str(tensor.device) if tensor is not None and hasattr(tensor, "device") else None,
        "layer_index": layer_index,
        "token_index": token_index,
        "node_name": node_name,
        "capture_method": capture_method,
        "capability_status": "captured",
        "tensor_summary": tensor_summary,
        "tensor_ref": None,
        "metadata": metadata or {},
    }


def event(event_type: str, trace_id: str, **attrs: Any) -> dict[str, Any]:
    payload = {
        "schema_version": SCHEMA_VERSION,
        "event_type": event_type,
        "trace_id": trace_id,
        "timestamp": utc_now(),
    }
    payload.update(attrs)
    return json_safe(payload)


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(json_safe(payload), sort_keys=True, indent=2) + "\n", encoding="utf-8")


def write_jsonl(path: Path, events: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as file:
        for item in events:
            file.write(json.dumps(json_safe(item), sort_keys=True) + "\n")


def artifact_paths(root: Path, trace_name: str) -> dict[str, Path]:
    name = safe_name(trace_name)
    return {
        "trace": root / "traces" / "python" / f"{name}.trace.jsonl",
        "capability_report": root / "capability_reports" / f"{name}.capability_report.json",
        "report": root / "reports" / f"{name}.python_trace_report.json",
    }


def selected_hidden_layers(hidden_states: tuple[Any, ...]) -> list[tuple[int, Any, str]]:
    rows = []
    for index, tensor in enumerate(hidden_states):
        node = "transformer.wte" if index == 0 else f"transformer.h.{index - 1}"
        rows.append((index, tensor, node))

    return rows


def build_trace(args: argparse.Namespace) -> dict[str, Any]:
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer

    root = Path(args.artifact_root)
    trace_name = args.trace_name or f"python_torch_{safe_name(args.model_id)}"
    paths = artifact_paths(root, trace_name)
    trace_id = f"tr_{safe_name(trace_name)}"
    run_id = f"run_{safe_name(trace_name)}"
    model_family = args.model_family
    started = time.perf_counter()

    events: list[dict[str, Any]] = [
        event(
            "trace_start",
            trace_id,
            run_id=run_id,
            provider_kind=PROVIDER_KIND,
            model_id=args.model_id,
            model_family=model_family,
            backend=BACKEND,
        )
    ]

    load_start = time.perf_counter()
    events.append(event("model_load_start", trace_id, model_id=args.model_id))
    tokenizer = AutoTokenizer.from_pretrained(args.model_id)

    try:
        model = AutoModelForCausalLM.from_pretrained(args.model_id, attn_implementation="eager")
    except TypeError:
        model = AutoModelForCausalLM.from_pretrained(args.model_id)

    device = torch.device(args.device)
    model.to(device)
    model.eval()
    load_time_ms = round((time.perf_counter() - load_start) * 1000)
    events.append(event("model_load_end", trace_id, model_id=args.model_id, load_time_ms=load_time_ms))

    encoded = tokenizer(args.prompt, return_tensors="pt")
    input_ids = encoded["input_ids"].to(device)
    attention_mask = encoded.get("attention_mask")
    if attention_mask is not None:
        attention_mask = attention_mask.to(device)

    signal_events: list[dict[str, Any]] = []
    signal_events.append(
        event(
            "signal_record",
            trace_id,
            signal=signal_record(
                trace_id=trace_id,
                run_id=run_id,
                model_id=args.model_id,
                model_family=model_family,
                signal_type="input_ids",
                signal_id=f"{trace_id}_input_ids",
                tensor=input_ids,
                node_name="tokenizer.input_ids",
                capture_method="tokenizer",
                metadata={"prompt_digest": sha256_text(args.prompt), "token_count": int(input_ids.numel())},
            ),
        )
    )

    if attention_mask is not None:
        signal_events.append(
            event(
                "signal_record",
                trace_id,
                signal=signal_record(
                    trace_id=trace_id,
                    run_id=run_id,
                    model_id=args.model_id,
                    model_family=model_family,
                    signal_type="attention_mask",
                    signal_id=f"{trace_id}_attention_mask",
                    tensor=attention_mask,
                    node_name="tokenizer.attention_mask",
                    capture_method="tokenizer",
                ),
            )
        )

    forward_start = time.perf_counter()
    events.append(event("forward_start", trace_id, prompt_digest=sha256_text(args.prompt)))

    with torch.no_grad():
        outputs = model(
            input_ids=input_ids,
            attention_mask=attention_mask,
            output_hidden_states=True,
            output_attentions=True,
            use_cache=False,
        )

    final_logits = outputs.logits[:, -1, :]
    signal_events.append(
        event(
            "signal_record",
            trace_id,
            signal=signal_record(
                trace_id=trace_id,
                run_id=run_id,
                model_id=args.model_id,
                model_family=model_family,
                signal_type="final_logits",
                signal_id=f"{trace_id}_final_logits",
                tensor=final_logits,
                tensor_summary=summarize_tensor(final_logits, entropy=True, top_k=args.top_k, tokenizer=tokenizer),
                node_name="lm_head.logits",
                token_index=int(input_ids.shape[-1] - 1),
                capture_method="transformers_forward",
            ),
        )
    )

    hidden_count = 0
    for layer_index, tensor, node_name in selected_hidden_layers(outputs.hidden_states or ()):
        hidden_count += 1
        signal_events.append(
            event(
                "signal_record",
                trace_id,
                signal=signal_record(
                    trace_id=trace_id,
                    run_id=run_id,
                    model_id=args.model_id,
                    model_family=model_family,
                    signal_type="hidden_state",
                    signal_id=f"{trace_id}_hidden_state_{layer_index}",
                    tensor=tensor,
                    node_name=node_name,
                    layer_index=layer_index,
                    token_index=int(input_ids.shape[-1] - 1),
                    capture_method="transformers_output_hidden_states",
                ),
            )
        )

    attention_count = 0
    for layer_index, tensor in enumerate(outputs.attentions or ()):
        attention_count += 1
        signal_events.append(
            event(
                "signal_record",
                trace_id,
                signal=signal_record(
                    trace_id=trace_id,
                    run_id=run_id,
                    model_id=args.model_id,
                    model_family=model_family,
                    signal_type="attention_weights",
                    signal_id=f"{trace_id}_attention_weights_{layer_index}",
                    tensor=tensor,
                    node_name=f"transformer.h.{layer_index}.attn.attn_weights",
                    layer_index=layer_index,
                    token_index=int(input_ids.shape[-1] - 1),
                    capture_method="transformers_output_attentions",
                ),
            )
        )

    generation_rows = manual_generation(
        args,
        model=model,
        tokenizer=tokenizer,
        input_ids=input_ids,
        attention_mask=attention_mask,
        trace_id=trace_id,
        run_id=run_id,
        model_family=model_family,
    )
    signal_events.extend(generation_rows["events"])

    forward_time_ms = round((time.perf_counter() - forward_start) * 1000)

    supported = [
        "input_ids",
        "attention_mask",
        "final_logits",
        "generation_step_logits",
        "generation_token",
        "decoded_text",
        "backend_event",
    ]
    unsupported = []

    if hidden_count > 0:
        supported.append("hidden_state")
    else:
        unsupported.append({"capability": "hidden_state", "reason": "transformers_hidden_states_unavailable"})

    if attention_count > 0:
        supported.append("attention_weights")
    else:
        unsupported.append({"capability": "attention_weights", "reason": "transformers_attentions_unavailable"})

    capability_report = {
        "provider_kind": PROVIDER_KIND,
        "model_id": args.model_id,
        "model_family": model_family,
        "backend": BACKEND,
        "supported": supported,
        "unsupported": unsupported,
        "required_missing": [],
        "optional_dropped": unsupported,
        "degraded": [],
        "failed": [],
        "resource_budget": {
            "supports_token_callback?": True,
            "supports_auxiliary_forward?": True,
            "supports_active_injection?": False,
            "max_extra_forward_passes": args.max_new_tokens + 1,
            "max_parallel_kv_caches": 0,
            "estimated_vram_multiplier": 1.0,
        },
    }

    events.append(
        event(
            "provider_capability_report",
            trace_id,
            capability_report=capability_report,
            capability_report_digest=sha256_text(json.dumps(json_safe(capability_report), sort_keys=True)),
        )
    )
    events.extend(signal_events)
    events.append(
        event(
            "backend_event",
            trace_id,
            backend=BACKEND,
            device=str(device),
            model_load_time_ms=load_time_ms,
            forward_time_ms=forward_time_ms,
            generated_tokens=generation_rows["generated_tokens"],
        )
    )
    events.append(event("forward_end", trace_id, forward_time_ms=forward_time_ms))
    duration_ms = round((time.perf_counter() - started) * 1000)
    events.append(event("trace_end", trace_id, status="ok", duration_ms=duration_ms))

    write_jsonl(paths["trace"], events)
    write_json(paths["capability_report"], capability_report)

    report = {
        "ok": True,
        "schema": "trinity.crucible.python_torch_trace.v1",
        "trace_id": trace_id,
        "run_id": run_id,
        "model_id": args.model_id,
        "model_family": model_family,
        "backend": BACKEND,
        "device": str(device),
        "prompt_digest": sha256_text(args.prompt),
        "signals": {
            "input_ids": 1,
            "attention_mask": 1 if attention_mask is not None else 0,
            "final_logits": 1,
            "hidden_state": hidden_count,
            "attention_weights": attention_count,
            "generation_step_logits": generation_rows["generation_step_logits"],
            "generation_token": generation_rows["generated_tokens"],
        },
        "generated_text": generation_rows["generated_text"],
        "paths": {key: str(path) for key, path in paths.items()},
        "duration_ms": duration_ms,
    }
    write_json(paths["report"], report)

    return report


def manual_generation(
    args: argparse.Namespace,
    *,
    model: Any,
    tokenizer: Any,
    input_ids: Any,
    attention_mask: Any,
    trace_id: str,
    run_id: str,
    model_family: str,
) -> dict[str, Any]:
    import torch

    events: list[dict[str, Any]] = [
        event("generation_start", trace_id, mode="manual_greedy", max_new_tokens=args.max_new_tokens)
    ]
    generated_ids: list[int] = []
    current_ids = input_ids
    current_mask = attention_mask

    with torch.no_grad():
        for step in range(args.max_new_tokens):
            outputs = model(input_ids=current_ids, attention_mask=current_mask, use_cache=False)
            step_logits = outputs.logits[:, -1, :]
            next_token = torch.argmax(step_logits, dim=-1, keepdim=True)
            token_id = int(next_token[0, 0].item())
            generated_ids.append(token_id)

            events.append(
                event(
                    "signal_record",
                    trace_id,
                    signal=signal_record(
                        trace_id=trace_id,
                        run_id=run_id,
                        model_id=args.model_id,
                        model_family=model_family,
                        signal_type="generation_step_logits",
                        signal_id=f"{trace_id}_generation_step_logits_{step}",
                        tensor=step_logits,
                        tensor_summary=summarize_tensor(
                            step_logits,
                            entropy=True,
                            top_k=args.top_k,
                            tokenizer=tokenizer,
                        ),
                        node_name="lm_head.step_logits",
                        token_index=step,
                        capture_method="manual_autoregressive_loop",
                        metadata={
                            "decode_mode": "greedy",
                            "energy": logsumexp(step_logits),
                            "selected_token_id": token_id,
                            "selected_token": tokenizer.decode([token_id], clean_up_tokenization_spaces=False),
                        },
                    ),
                )
            )
            events.append(
                event(
                    "signal_record",
                    trace_id,
                    signal=signal_record(
                        trace_id=trace_id,
                        run_id=run_id,
                        model_id=args.model_id,
                        model_family=model_family,
                        signal_type="generation_token",
                        signal_id=f"{trace_id}_generation_token_{step}",
                        tensor=next_token,
                        node_name="manual_decode.next_token",
                        token_index=step,
                        capture_method="manual_autoregressive_loop",
                        metadata={
                            "token_id": token_id,
                            "token": tokenizer.decode([token_id], clean_up_tokenization_spaces=False),
                        },
                    ),
                )
            )
            events.append(event("generation_step", trace_id, step=step, token_id=token_id))

            current_ids = torch.cat([current_ids, next_token.to(current_ids.device)], dim=-1)
            if current_mask is not None:
                current_mask = torch.cat([current_mask, torch.ones_like(next_token).to(current_mask.device)], dim=-1)

    generated_text = tokenizer.decode(generated_ids, clean_up_tokenization_spaces=False)
    events.append(
        event(
            "signal_record",
            trace_id,
            signal=signal_record(
                trace_id=trace_id,
                run_id=run_id,
                model_id=args.model_id,
                model_family=model_family,
                signal_type="decoded_text",
                signal_id=f"{trace_id}_decoded_text",
                tensor=None,
                tensor_summary=None,
                node_name="manual_decode.generated_text",
                capture_method="manual_autoregressive_loop",
                metadata={"generated_text": generated_text, "generated_token_ids": generated_ids},
            ),
        )
    )
    events.append(event("generation_end", trace_id, generated_token_ids=generated_ids, generated_text=generated_text))

    return {
        "events": events,
        "generated_tokens": len(generated_ids),
        "generation_step_logits": len(generated_ids),
        "generated_text": generated_text,
    }


def self_test() -> dict[str, Any]:
    payload = {
        "ok": True,
        "schema": "trinity.crucible.python_torch_trace.self_test.v1",
        "provider_kind": PROVIDER_KIND,
        "backend": BACKEND,
        "artifact_dirs": [
            "traces/python",
            "capability_reports",
            "policy_decisions",
            "route_decisions",
            "reports",
        ],
    }
    print(json.dumps(payload, sort_keys=True))
    return payload


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-id", default="hf-internal-testing/tiny-random-gpt2")
    parser.add_argument("--model-family", default="gpt2")
    parser.add_argument("--prompt", default="Hi")
    parser.add_argument("--artifact-root", default="tmp/crucible_v5")
    parser.add_argument("--trace-name", default=None)
    parser.add_argument("--max-new-tokens", type=int, default=3)
    parser.add_argument("--top-k", type=int, default=5)
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if args.self_test:
        self_test()
        return

    report = build_trace(args)
    print(json.dumps(json_safe(report), sort_keys=True))


if __name__ == "__main__":
    main()
