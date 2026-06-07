<!-- ~/.claude/rules/openspec-integration.md -->

# OpenSpec + Superpowers Integration

## Before Any Implementation Work

1. Check if active `spec.md` exists
2. If not, create one with `/opsx:new`
3. Review `archived/` for similar past implementations

## During Implementation

1. Follow Superpowers TDD workflow:
   - brainstorm → write-tests → implement → run-tests → code-review
2. Update `spec.md` with implementation decisions using `/opsx:continue`
3. Keep spec in sync with actual implementation

## After Implementation

1. Run Superpowers code review
2. Archive completed spec with `/opsx:archive`
3. Document learnings for future reference

## ⚠️ Do NOT

- Implement without a spec.md
- Let spec.md drift from actual implementation
- Skip the archive step after completion
