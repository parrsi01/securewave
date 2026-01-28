import json
from dataclasses import dataclass, field
from typing import Any, Dict

from services.marl_policy import MARLPolicyConfig
from services.xgb_qos import XGBQoSConfig
from services.xgb_risk import XGBRiskConfig


@dataclass
class SplitConfig:
    train_ratio: float = 0.8
    seed: int = 42


@dataclass
class AggregationConfig:
    trust_weight: float = 1.0
    feature_decay: float = 1.0


@dataclass
class ExperimentConfig:
    profile: str = "baseline"
    seed: int = 42
    split: SplitConfig = field(default_factory=SplitConfig)
    xgb_qos: XGBQoSConfig = field(default_factory=XGBQoSConfig)
    xgb_risk: XGBRiskConfig = field(default_factory=XGBRiskConfig)
    marl: MARLPolicyConfig = field(default_factory=MARLPolicyConfig)
    aggregation: AggregationConfig = field(default_factory=AggregationConfig)
    output_dir: str = "runs"

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "ExperimentConfig":
        return cls(
            profile=str(data.get("profile", "baseline")),
            seed=int(data.get("seed", 42)),
            split=SplitConfig(**data.get("split", {})),
            xgb_qos=XGBQoSConfig(**data.get("xgb_qos", {})),
            xgb_risk=XGBRiskConfig(**data.get("xgb_risk", {})),
            marl=MARLPolicyConfig(**data.get("marl", {})),
            aggregation=AggregationConfig(**data.get("aggregation", {})),
            output_dir=str(data.get("output_dir", "runs")),
        )


def load_config(path: str) -> ExperimentConfig:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    return ExperimentConfig.from_dict(data)
