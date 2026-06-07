# V457 Carrier Selection and Layer Validation Experiments

## Experiment 1: Baseline Carrier Index

### USE_CACHED_INDEX Instruction

BEFORE selecting a carrier for ANY family:

1. **CONSULT** BASELINE_CARRIER_INDEX.json (auto-loaded if present in replay root)
2. **VALIDATE** carrier exists in index with `baseline_commit = e19c16c`
3. **CHECK** carrier.layer ∈ {Facade, Controller} for core_entry family
4. **IF** carrier.layer = Task/Service:
   - **DO NOT** select for core_entry family
   - **CONSIDER** selecting for stateful_side_effect family
5. **IF** no valid carrier found in index:
   - **EXECUTE** fallback: `rg "@Remote @CatfishRemote"` in claim-core
   - **IF** fallback returns empty: CREATE `planned_new_carrier` entry, DEFER to later slice

### Building the Index

To generate BASELINE_CARRIER_INDEX.json:
```powershell
.\scripts\Build-BaselineCarrierIndex.ps1 -BaselineRoot "D:\opt\claim" -OutputPath "BASELINE_CARRIER_INDEX.json"
```

### Index Schema

```json
{
  "schema_version": "v457",
  "baseline_commit": "e19c16c",
  "generated_at": "2026-06-05T10:00:00Z",
  "total_carriers": 42,
  "carriers": {
    "AiApplyClaimApiTaskProcessor": {
      "layer": "Task",
      "module": "claim-core",
      "file": "claim-core/src/main/java/.../AiApplyClaimApiTaskProcessor.java",
      "baseline_commit": "e19c16c",
      "type": "Task"
    }
  }
}
```

---

## Experiment 2: Layer Validation Pre-Check

### LAYER_VALIDATION_CHECKLIST

BEFORE confirming carrier selection for ANY family:

1. **EXECUTE**: `.\scripts\Get-CarrierLayer.ps1 -Carrier $SelectedCarrier`
2. **VALIDATE** result.layer against family requirements:
   - `core_entry` family: REQUIRES layer ∈ {Facade, Controller}
   - `stateful_side_effect` family: ALLOWS layer ∈ {Service, Facade}
   - `deploy_export_page` family: ALLOWS layer ∈ {Controller, Service}
3. **IF** layer validation FAILS:
   - **REJECT** current carrier
   - **SELECT** alternative carrier from same family
   - **IF** no alternative exists: CREATE `planned_new_carrier` entry
4. **ONLY AFTER** layer validation PASSES: Confirm carrier selection

### Get-CarrierLayer.ps1 Usage

```powershell
$result = .\scripts\Get-CarrierLayer.ps1 -Carrier "AiApplyClaimApiTaskProcessor" -BaselineRoot "D:\opt\claim"
# Returns: @{ layer = "Task"; file = "..."; reason = $null }
```

### Layer Classification Rules

| Layer Pattern | Layer Name | Valid For core_entry | Valid For stateful_side_effect |
|---------------|------------|---------------------|--------------------------------|
| `*Facade`, `*FacadeImpl` | Facade | YES | YES |
| `*Controller`, `*ApiController` | Controller | YES | NO |
| `*Service` | Service | NO | YES |
| `*TaskProcessor`, `*Task` | Task | NO | YES |
| `*Mapper`, `*Dao`, `*Provider` | Provider | NO | NO |
| Unknown pattern | Unknown | BLOCKED | BLOCKED |

---

## Example Workflow

### Step 1: Check Carrier Index
```markdown
# Load BASELINE_CARRIER_INDEX.json
$index = Get-Content "BASELINE_CARRIER_INDEX.json" | ConvertFrom-Json

# Check if carrier exists
if ($index.carriers.PSObject.Properties.Name -contains "AiApplyClaimApiTaskProcessor") {
    $carrierInfo = $index.carriers."AiApplyClaimApiTaskProcessor"
    Write-Host "Layer: $($carrierInfo.layer)"
}
```

### Step 2: Validate Layer
```markdown
# Execute layer validation
$result = .\scripts\Get-CarrierLayer.ps1 -Carrier "AiApplyClaimApiTaskProcessor"

# Check result
if ($result.layer -eq "Facade" -or $result.layer -eq "Controller") {
    # Valid for core_entry family
    $selected_carrier = "AiApplyClaimApiTaskProcessor"
} elseif ($result.layer -eq "Task" -or $result.layer -eq "Service") {
    # Invalid for core_entry, defer or select alternative
    Write-Host "ERROR: Layer $($result.layer) not valid for core_entry family"
}
```

---

## Integration with Existing Prompts

### For slice_planning.md

Add this section at the beginning of carrier selection logic:

```markdown
## V457 Carrier Index and Layer Validation (EXPERIMENTAL)

### Phase 0 Pre-Check

1. Load BASELINE_CARRIER_INDEX.json if present
2. For each candidate carrier:
   a. Check if carrier exists in index
   b. Validate carrier.layer matches family requirements
   c. If layer mismatch: reject carrier and select alternative

### Experiment Status

- Experiment 1 (Carrier Index): ENABLED for v456-r02
- Experiment 2 (Layer Validation): ENABLED for v456-r03
- Experiment 3 (Plan Hard Requirements): ENABLED for v456-r04
```

---

## Rollback Conditions

### Experiment 1 Rollback

If Phase0 pass rate < 50% after 3 rounds:
1. Disable `Build-BaselineCarrierIndex.ps1`
2. Remove USE_CACHED_INDEX instruction from prompt
3. Revert to manual carrier selection

### Experiment 2 Rollback

If `wrong_test_surface` mentions > 3 after 3 rounds:
1. Disable `Get-CarrierLayer.ps1`
2. Remove layer validation checklist from prompt
3. Allow carrier selection without pre-check

---

## Expected Impact

| Metric | Current | Target | Delta |
|--------|---------|--------|-------|
| Phase0 carrier verify pass rate | 0% | 80% | +80% |
| wrong_test_surface mentions | 12 | 1 | -92% |
| Plan-stage block rate | 60% | 20% | -40% |
