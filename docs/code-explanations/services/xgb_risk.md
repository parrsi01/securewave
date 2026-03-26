# `services/xgb_risk.py`

Purpose: This service module implements the business logic for xgb risk operations.

## Line Walkthrough

- `L1-L2`: Module or block docstring that describes the responsibility of this section.
- `L4-L5`: Implements this section of logic starting with `Scores user/connection risk based on behavioral signals.`.
- `L7-L13`: Implements this section of logic starting with `Inputs:`.
- `L15-L19`: Implements this section of logic starting with `Output:`.
- `L21-L24`: Imports the dependencies used later in this module, including os, dataclasses, pathlib, typing.
- `L26-L31`: Implements this section of logic starting with `# Lazy ML imports`.
- `L33-L37`: Attempts a potentially fragile operation and relies on later branches to handle failures safely.
- `L39`: Initializes module-level state or configuration such as `ML_AVAILABLE`.
- `L42-L51`: Applies decorators and defines `RiskInput` with the wrapped behavior declared above it.
- `L54-L60`: Applies decorators and defines `RiskResult` with the wrapped behavior declared above it.
- `L63-L74`: Applies decorators and defines `XGBRiskConfig` with the wrapped behavior declared above it.
- `L77-L81`: Defines `XGBRiskScorer`. XGBoost-based risk scorer. Falls back to rule-based scoring if ML dependencies unavailable.
- `L83`: Initializes module-level state or configuration such as `LEVELS`.
- `L85-L88`: Defines the `__init__` function and the logic it executes.
- `L90-L91`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L93-L101`: Defines `_load_model`. Load pre-trained model from disk.
- `L103-L106`: Defines `save_model`. Save trained model to disk.
- `L108-L118`: Defines `_extract_features`. Extract feature vector from input.
- `L120-L122`: Defines `_identify_risk_factors`. Identify which factors contribute to risk.
- `L124-L137`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L139`: Returns a value from the current function.
- `L141-L146`: Defines `_rule_based_score`. Rule-based risk scoring (fallback when ML unavailable). Uses weighted sum of risk indicators.
- `L148-L149`: Implements this section of logic starting with `# Calculate risk score from each factor`.
- `L151-L152`: Implements this section of logic starting with `# Login failures: each failure adds risk`.
- `L154-L155`: Implements this section of logic starting with `# Reconnect frequency: high frequency is suspicious`.
- `L157-L159`: Implements this section of logic starting with `# Unusual hours`.
- `L161-L162`: Initializes module-level variables and configuration used by later code.
- `L164-L166`: Implements this section of logic starting with `# Geo anomaly`.
- `L168-L169`: Implements this section of logic starting with `# Data exfiltration indicator`.
- `L171-L172`: Implements this section of logic starting with `# Session duration anomaly`.
- `L174-L175`: Implements this section of logic starting with `# Clamp to 0-1`.
- `L177-L185`: Implements this section of logic starting with `# Map score to level`.
- `L187-L192`: Returns a value from the current function.
- `L194-L196`: Defines the `train` function and the logic it executes.
- `L198-L202`: Implements this section of logic starting with `Args:`.
- `L204-L212`: Defines the `train_with_config` function and the logic it executes.
- `L214-L216`: Initializes module-level state or configuration such as `cfg, X_arr, y_arr`.
- `L218-L220`: Initializes module-level state or configuration such as `sample_weight`.
- `L222-L240`: Initializes module-level state or configuration such as `self.model, n_estimators, max_depth, learning_rate, subsample, colsample_bytree`.
- `L242-L244`: Defines the `predict` function and the logic it executes.
- `L246-L249`: Implements this section of logic starting with `Returns:`.
- `L251-L253`: Implements this section of logic starting with `# Fallback to rule-based if ML not available or not trained`.
- `L255-L257`: Attempts a potentially fragile operation and relies on later branches to handle failures safely.
- `L259-L261`: Implements this section of logic starting with `# Predict risk score`.
- `L263-L271`: Implements this section of logic starting with `# Map score to level`.
- `L273-L280`: Returns a value from the current function.
- `L282-L284`: Defines `predict_batch`. Predict risk for multiple inputs.
- `L287-L288`: Implements this section of logic starting with `# Singleton instance`.
- `L291-L297`: Defines `get_risk_scorer`. Get or create singleton risk scorer.
- `L300-L310`: Defines the `score_risk` function and the logic it executes.
- `L312-L331`: Implements this section of logic starting with `Returns:`.
