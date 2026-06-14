# Benchmark Fixture Notice

The files in this directory (`configs/`) and `requirements/` are **benchmark evaluation fixtures** derived from the author's internal project replay sessions. They serve as regression inputs to validate the replay control plane (`replay-autopilot`).

## What these are

- Real-world replay configurations used during control plane development
- Requirement snapshots from actual business projects
- Used as `Test-v*.ps1` regression test inputs to verify verifier behavior, carrier search correctness, plan gate logic, etc.

## What these are NOT

- Not templates for new projects
- Not runtime credentials, session logs, or private oracle diffs
- Not default business project configurations shipped with the kit

## How to use

New projects should create their own `config.yaml` in their replay evidence directory with project-specific paths. The `replay-autopilot/config.yaml` at the root of this kit serves as the canonical template with documented defaults.

The scripts in `configs/` and `requirements/` are never installed to user home directories. They live only in this repository as part of the regression test suite.
