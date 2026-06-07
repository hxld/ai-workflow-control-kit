# Golden Sample Mining Review

You are reviewing deterministic replay evidence mining output.

Inputs:
- ledger: {{GOLDEN_SAMPLE_LEDGER}}
- generated SOP: {{GOLDEN_SAMPLE_SOP}}
- generated control prompt: {{GOLDEN_SAMPLE_PROMPT}}

Write the result to:
- {{OUTPUT_PATH}}

Rules:
1. Treat this as workflow evidence only, not as oracle implementation facts.
2. Do not copy project-specific class names, table names, commits, replay roots, or business details into general skills.
3. Identify which mined rules are safe to apply cross-feature.
4. Identify which anti-patterns still need tooling gates rather than prompt wording.
5. If the deterministic SOP is unsafe, write `final_status: REJECTED` with reasons.
6. If it is safe, write `final_status: ACCEPTED` and list the exact generic gates to keep.

Required output shape:

```text
final_status: ACCEPTED | REJECTED
safe_cross_feature_rules:
- ...
unsafe_project_specific_items:
- ...
recommended_next_gate:
- ...
```
