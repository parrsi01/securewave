# SecureWave 1.0.0

A Linux WireGuard VPN application by **Simon Parris**, with a Flutter desktop
client, FastAPI control plane, PostgreSQL persistence, and a C++ privilege
boundary. The project focuses on reliable connection lifecycle management and
durable accounting of real tunnel traffic.

## Start here

| Reader | Recommended route |
| --- | --- |
| HR or talent acquisition | [Project overview](docs/portfolio/project-overview.md): purpose, contribution, skills, and delivery history |
| Software engineering reviewer | [Engineering walkthrough](docs/portfolio/engineering-walkthrough.md): code map, decisions, and review exercises |
| Architecture or research reviewer | [Technical monograph](docs/research/README.md): formal model, algorithms, correctness, evaluation, and limitations |
| Developer | [Quick start](QUICK_START.md), [workflows](docs/development/workflows.md), and [testing](docs/development/testing.md) |

## Implemented behavior

- Registration, sign-in, token validation, and logout.
- Client-owned WireGuard keys, per-account identity reuse, and authenticated peer provisioning.
- Connect, Disconnect, and Reconnect through a restricted Linux helper.
- Connection verification using the interface, expected peer, recent handshake, counters, routing, and changed public egress.
- Durable usage sessions, cumulative checkpoints, idempotent database updates, and final reporting after window close or process death.
- Responsive navy/cyan presentation with keyboard/accessibility and visual regression tests.

The current desktop target is **Ubuntu 24.04 ARM64 with WireGuard**. This
release does not claim supported Windows, macOS, mobile, OpenVPN, IKEv2, or
machine-learning anomaly detection.

## Repository map

```text
securewave_app/     Flutter UI, API/VPN services, native runner, helper, packaging
routes/            HTTP authentication, peer provisioning, and usage contracts
services/          Authentication, server management, transactional metering
models/            SQLAlchemy account, peer, session, and event models
database/          Database engine, sessions, and model metadata
infrastructure/    Server provisioning and systemd integration
scripts/           Development, migration, packaging, acceptance entrypoints
tests/             Backend contracts and real PostgreSQL checks
docs/portfolio/    Recruiter overview and engineering review guide
docs/research/     Research-style chapters, figures, and PDF
docs/development/  Reproducible workflows, testing, release procedures
docs/archive/      Earlier evidence, version names, and design notes
```

## Build and verify

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements-dev.txt
make test-backend
make test-flutter
make test-native
make check
```

See [Quick Start](QUICK_START.md) for native dependencies and packaging.
Contract tests use disposable fixtures; they do not establish a production VPN.

## Evidence and release status

**1.0.0 is the consolidated source version.** Earlier `4.0.0+…` names remain
in historical records and original package provenance. The project uses one
active branch, `master`; archive tags preserve checkpoints.

The [current validation record](docs/current-state.md) distinguishes source
checks from installed-product evidence. Historical tests demonstrated real
traffic, teardown, crash recovery, and final database persistence. Version
1.0.0 is installed with matching package bytes; services, cold launch,
authenticated Connect/Disconnect/Reconnect, real traffic and final backend
usage persistence passed. A fresh reboot with 1.0.0 installed and its
subsequent lifecycle remain the final open acceptance gate.

The [technical monograph](docs/research/README.md) adopts the research-question,
system-model, algorithm, and evaluation structure of
[my anomaly-detection paper](https://github.com/parrsi01/Decentralized-Federated-Detection-of-Network-Anomalies-in-Mobile-Networks/blob/main/Research/IEEE_conference_paper_simon_parris.pdf).
It provides original VPN-specific analysis as an engineering case study.
