# SecureWave: Architecture, Algorithms and Assurance

Master's-level engineering report for SecureWave 1.0.0. Prepared for the
project maintained by Simon Parris, revised 7 October 2026. This is an engineering
analysis of the repository, not a peer-reviewed publication or an independent
security certification.

Read the [complete PDF](securewave-architecture.pdf) or the chapters below.
The PDF is generated from these Markdown sources and the SVG figures by
[`scripts/build_research_pdf.py`](../../scripts/build_research_pdf.py).
The report uses the problem–model–algorithm–evaluation structure of
[the author's network anomaly detection paper](https://github.com/parrsi01/Decentralized-Federated-Detection-of-Network-Anomalies-in-Mobile-Networks/blob/main/Research/IEEE_conference_paper_simon_parris.pdf).
Its published classifier results and university affiliations are not claimed
as results or endorsements of SecureWave. The separately specified
[routing adaptation](../development/routing-optimizer.md) uses new offline
policy learning and shadow observation, with no production performance claim.

| Chapter | Subject |
| --- | --- |
| [Abstract and research questions](00-abstract.md) | Scope and contribution |
| [1. Problem and requirements](01-problem.md) | Observable correctness and operating assumptions |
| [2. System architecture](02-architecture.md) | Components, data flow and trust boundaries |
| [3. Security model](03-security.md) | Identities, authentication and privileged execution |
| [4. Lifecycle algorithms](04-lifecycle.md) | Connection, recovery and disconnection |
| [5. Durable usage accounting](05-accounting.md) | Counter model, checkpoints and crash recovery |
| [6. Backend and persistence](06-backend.md) | API contracts, schema and migrations |
| [7. Correctness and complexity](07-analysis.md) | Invariants, arguments and limits |
| [8. Evaluation methodology](08-evaluation.md) | Tests, acceptance protocol and threats to validity |
| [9. Delivery and reproducibility](09-delivery.md) | Source, package, deployment and evidence |
| [10. Limitations and future work](10-limitations.md) | Open questions and conclusion |
| [11. Experimental routing policy](11-routing.md) | MARL/XGBoost adaptation, shadow authority and data validity |
| [References](references.md) | Primary sources and code traceability |

## Rebuild the report

```sh
python3 -m venv .venv-docs
.venv-docs/bin/pip install -r requirements-docs.txt
.venv-docs/bin/python scripts/build_research_pdf.py
```

Run from the repository root. The renderer requires the DejaVu fonts installed
on Ubuntu; it embeds them in the PDF. There are no remote rendering services.
The source version is 1.0.0; package installation, public delivery and real VPN
acceptance have separate evidence in [current state](../current-state.md).
