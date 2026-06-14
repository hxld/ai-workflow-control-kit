# V454 Service Layer Async Task Exception Guidance

**Experiment**: 2 - Service Layer Async Task Exception
**Purpose**: Accept Service layer orchestrators as valid targets when triggered by async task processor

---

## Carrier Selection Rules

1. Prefer Facade/Controller layer for core_entry family
2. EXCEPTION: Service layer is VALID when:
   a. Carrier is referenced by existing baseline async task processor
   b. Oracle analysis shows HIGH weight
   c. Carrier has >100 oracle additions

3. When selecting between multiple carriers:
   - Prioritize orchestrator (large oracle additions) over helper (small additions)
   - Business weight multiplier: HIGH=3.0, MEDIUM=1.5, LOW=1.0

---

## Service Layer Exception Conditions

A Service layer carrier is valid when ALL three conditions are met:

1. **Async Task Trigger**: Carrier is triggered by existing async task processor
   - Examples: ExampleApiTaskProcessor, ExampleFlowService
   - Evidence: Method reference or inheritance from async processor

2. **High Oracle Weight**: Oracle analysis shows HIGH weight
   - Must have weight = "HIGH" in oracle diff analysis
   - Must have >100 oracle additions

3. **Baseline Reference**: Carrier has >100 oracle additions
   - Carrier is referenced by baseline entry class
   - Evidence: Method call or field reference in Entry/Controller/Facade

---

## Layer Validation Process

```powershell
# Validate layer rule change
$layerResult = Invoke-LayerValidation -ReplayRoot $replayRoot -SelectedCarrier "ExampleFlowService"
if ($layerResult.status -eq "PASS" -and $layerResult.service_layer_exception -eq $true) {
    Write-Output "Experiment 2 SUCCESS: Service layer exception working"
} else {
    Write-Output "Experiment 2 FAIL: Service layer still rejected"
}
```

---

## Expected Metric Delta

- Coverage: 0% → >60% (core_entry family can be targeted via ExampleFlowService)
- Layer validation pass rate: 0% → 80% (Service layer orchestrators accepted)
- Oracle overlap: 0% → >50% (can target HIGH-weight carriers)

---

## Rollback Condition

- Layer validation still rejects ExampleFlowService
- service_layer_exception not set to true
- Coverage remains 0%

---

## Success Threshold

Layer validation passes for ExampleFlowService with service_layer_exception=true

---

**Version**: v454
**Date**: 2026-06-05
