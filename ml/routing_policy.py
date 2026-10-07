"""Pure routing policy shared by offline training and shadow evaluation."""

import math
from collections.abc import Mapping, Sequence

FEATURES = ("latency_ms", "packet_loss", "jitter_ms", "load_ratio")
ACTIONS = ("quality", "load", "baseline")


def _validate(predictions: Sequence[float], load_ratios: Sequence[float]) -> None:
    if not predictions or len(predictions) != len(load_ratios):
        raise ValueError("Predictions and loads must have matching nonempty lengths")
    if any(isinstance(v, bool) or not math.isfinite(v) for v in predictions):
        raise ValueError("Predictions must be finite numbers")
    if any(isinstance(v, bool) or not math.isfinite(v) or not 0 <= v <= 1 for v in load_ratios):
        raise ValueError("Loads must be finite ratios in [0, 1]")


def action_indices(predictions: Sequence[float], load_ratios: Sequence[float], baseline_index: int) -> tuple[int, int, int]:
    _validate(predictions, load_ratios)
    if isinstance(baseline_index, bool) or not isinstance(baseline_index, int) or not 0 <= baseline_index < len(predictions):
        raise ValueError("Invalid baseline index")
    quality = max(range(len(predictions)), key=lambda i: predictions[i])
    load = min(range(len(load_ratios)), key=lambda i: load_ratios[i])
    return quality, load, baseline_index


def state_key(predictions: Sequence[float], load_ratios: Sequence[float]) -> str:
    """Stable quantized context; never encodes user or infrastructure identities."""
    _validate(predictions, load_ratios)
    quality = max(range(len(predictions)), key=lambda i: predictions[i])
    load = min(range(len(load_ratios)), key=lambda i: load_ratios[i])
    # Cap before integer conversion: subtraction of large finite values may
    # overflow to infinity even though each input passed finite validation.
    spread = int(min(2.0, max(0.0, max(predictions) - min(predictions)) / 0.2))
    gap = int(min(2.0, max(0.0, predictions[quality] - predictions[load]) / 0.1))
    quality_load = min(2, int(load_ratios[quality] * 3))
    return f"v1:{min(8, len(predictions))}:{int(quality == load)}:{quality_load}:{spread}:{gap}"


def recommend_index(predictions: Sequence[float], load_ratios: Sequence[float], baseline_index: int,
                    q_table: Mapping[str, Sequence[float]]) -> tuple[int, str]:
    indices = action_indices(predictions, load_ratios, baseline_index)
    values = q_table.get(state_key(predictions, load_ratios))
    if values is None:
        return indices[0], "xgboost_only_unseen_state"
    if len(values) != len(ACTIONS) or any(isinstance(v, bool) or not math.isfinite(v) for v in values):
        raise ValueError("Policy state must contain three finite action values")
    action = max(range(len(ACTIONS)), key=lambda i: values[i])
    return indices[action], f"marl_xgboost_{ACTIONS[action]}"
