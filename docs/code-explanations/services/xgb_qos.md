# `services/xgb_qos.py`

Purpose: This service module implements the business logic for xgb qos operations.

## Line Walkthrough

- `L1-L2`: Module or block docstring that describes the responsibility of this section.
- `L4-L5`: Implements this section of logic starting with `Classifies VPN connection quality based on telemetry metrics.`.
- `L7-L12`: Implements this section of logic starting with `Inputs:`.
- `L14-L18`: Implements this section of logic starting with `Output:`.
- `L20-L24`: Imports the dependencies used later in this module, including os, dataclasses, collections, pathlib, typing.
- `L26-L31`: Implements this section of logic starting with `# Lazy ML imports`.
- `L33-L37`: Attempts a potentially fragile operation and relies on later branches to handle failures safely.
- `L39`: Initializes module-level state or configuration such as `ML_AVAILABLE`.
- `L42-L49`: Applies decorators and defines `QoSInput` with the wrapped behavior declared above it.
- `L52-L58`: Applies decorators and defines `QoSResult` with the wrapped behavior declared above it.
- `L61-L72`: Applies decorators and defines `XGBQoSConfig` with the wrapped behavior declared above it.
- `L75-L79`: Defines `XGBQoSClassifier`. XGBoost-based QoS classifier. Falls back to rule-based scoring if ML dependencies unavailable.
- `L81-L83`: Implements this section of logic starting with `# Class label mapping`.
- `L85-L88`: Defines the `__init__` function and the logic it executes.
- `L90-L91`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L93-L101`: Defines `_load_model`. Load pre-trained model from disk.
- `L103-L106`: Defines `save_model`. Save trained model to disk.
- `L108-L116`: Defines `_extract_features`. Extract feature vector from input.
- `L118-L128`: Defines `_rule_based_score`. Rule-based QoS scoring (fallback when ML unavailable). Deterministic and interpretable.
- `L130-L137`: Implements this section of logic starting with `# Weighted combination`.
- `L139-L147`: Implements this section of logic starting with `# Map score to label`.
- `L149-L154`: Returns a value from the current function.
- `L156-L158`: Defines the `train` function and the logic it executes.
- `L160-L164`: Implements this section of logic starting with `Args:`.
- `L166-L174`: Defines the `train_with_config` function and the logic it executes.
- `L176-L179`: Initializes module-level state or configuration such as `cfg, y_int, X_arr, y_arr`.
- `L181-L186`: Initializes module-level state or configuration such as `sample_weight`.
- `L188-L210`: Initializes module-level state or configuration such as `self.model, n_estimators, max_depth, learning_rate, subsample, colsample_bytree`.
- `L212-L214`: Defines the `predict` function and the logic it executes.
- `L216-L221`: Implements this section of logic starting with `Returns:`.
- `L223-L225`: Attempts a potentially fragile operation and relies on later branches to handle failures safely.
- `L227-L231`: Implements this section of logic starting with `# Get class probabilities`.
- `L233-L234`: Implements this section of logic starting with `# Calculate continuous score from weighted probabilities`.
- `L236-L243`: Returns a value from the current function.
- `L245-L247`: Defines `predict_batch`. Predict QoS for multiple inputs.
- `L250-L251`: Implements this section of logic starting with `# Singleton instance`.
- `L254-L260`: Defines `get_qos_classifier`. Get or create singleton QoS classifier.
- `L263-L271`: Defines the `classify_qos` function and the logic it executes.
- `L273-L290`: Implements this section of logic starting with `Returns:`.
