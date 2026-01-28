from ml.config import ExperimentConfig
from ml.experiment import run_experiment


def test_experiment_smoke(tmp_path):
    csv_path = tmp_path / "telemetry.csv"
    csv_path.write_text(
        "latency_ms,packet_loss,jitter_ms,bandwidth_mbps,connection_stability,disconnect_count,qos_label,risk_score\n"
        "30,0.01,2,100,0.98,0,excellent,0.1\n"
        "80,0.03,8,80,0.85,1,good,0.2\n"
        "160,0.06,18,60,0.7,2,fair,0.4\n"
        "260,0.12,30,40,0.5,3,poor,0.6\n"
        "400,0.2,45,20,0.3,5,poor,0.8\n",
        encoding="utf-8",
    )
    config = ExperimentConfig()
    run_dir = run_experiment(config, data_path=str(csv_path), output_dir=str(tmp_path))
    assert (run_dir / "metrics.json").exists()
