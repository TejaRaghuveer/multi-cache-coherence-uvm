# Verification Plan â€“ Multi-Level Cache Coherence

## Objectives
- Confirm MESI/MOESI protocol compliance across all cache levels and coherence agents.
- Guarantee data consistency: latest write visibility, single Modified owner, correct invalidations and writebacks.
- Validate state machines: all legal transitions, downgrade/upgrade flows, transient handling, victim/owned behavior.
- Ensure robustness under error scenarios (protocol violations, invalidates, writebacks) and collect functional coverage proving completeness.

## Methodology
- UVM-based environment with L1/L2 agents, shared cache_state_model, cache_model_mgr golden reference, scoreboard, and dedicated state/data checkers.
- Directed and randomized sequences (coh_state_walk_seq, coh_upgrade_seq, coh_conflict_seq, coh_random_seq, coh_full_transition_vseq) exercising protocol paths, contention, races, and flush/invalidate patterns.
- Monitors capture transactions, populate coverage, feed the scoreboard and trace manager (with rotated/compressed logs).
- Regression automation (scripts/run_uvm_regression.ps1) enables simulator selection, randomized seeds, coverage collection, and UCDB merge/report.

## Coverage Goals
- **State/Transition**: 100% coverage for MESI/MOESI states and legal transitions; cross prev_state Ã— txn Ã— next_state.
- **Transactions**: All processor and snoop types (PR_RD, PR_WR, BUS_RD, BUS_RDX, BUS_UPGR, BUS_INV, WB).
- **Multi-Level**: Cross coverage of L1/L2 state combinations, sharer counts (0, 1, â‰¥2), owned downgrades, victim evictions.
- **Error Scenarios**: Coverage bins tagged when scoreboard/checkers raise protocol violations or data mismatches.

## Test Scenarios
1. **Directed State Walk** â€“ Force lines through Iâ†’Eâ†’Mâ†’Oâ†’Sâ†’I.
2. **Upgrade Contention** â€“ Parallel upgrades with overlapping address sets plus directory invalidates.
3. **Conflict Storm** â€“ Random address thrash to stress replacement and eviction flows.
4. **Mixed Directed + Random** â€“ Deterministic sequence on one core, randomized on another, plus L2 snoops.
5. **DMA Peer Pressure** â€“ Inject BUS_RD/RDX from DMA agents.
6. **Flush In-Motion** â€“ Interleave writebacks with active readers.

## Results Summary
- Regression runs (default 5 seeds per sequence) execute without scoreboard/checker errors.
- esults/coverage_report.txt documents coverage closure for protocol states, transitions, sharer counts, and error bins.
- logs/cache_trace_<test>_<seed>.log.zip retains compressed traces for post-run analysis.

