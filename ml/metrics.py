from typing import Dict, Iterable, List


def accuracy_score(true_labels: List[str], pred_labels: List[str]) -> float:
    if not true_labels:
        return 0.0
    matches = sum(1 for true, pred in zip(true_labels, pred_labels) if true == pred)
    return matches / len(true_labels)


def mean_absolute_error(true_values: List[float], pred_values: List[float]) -> float:
    if not true_values:
        return 0.0
    total = sum(abs(true - pred) for true, pred in zip(true_values, pred_values))
    return total / len(true_values)


def aggregate_policy_actions(actions: Iterable[str], trust_weight: float = 1.0) -> Dict[str, float]:
    counts: Dict[str, float] = {}
    for action in actions:
        counts[action] = counts.get(action, 0.0) + trust_weight
    return counts
