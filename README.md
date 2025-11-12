# Multi-Level Cache Coherency Verification Environment

---

## Table of Contents
- [Project Overview](#project-overview)
- [Objectives](#objectives)
- [Verification Scope](#verification-scope)
- [Directory Guide](#directory-guide)
- [How to Run the Suite](#how-to-run-the-suite)
- [Results & Reports](#results--reports)
- [Author & Credits](#author--credits)

---

## Project Overview
This project delivers a reusable UVM-based environment for verifying multi-level cache coherency. It brings together MESI/MOESI-aware agents, functional models, scoreboards, coverage, and regression automationâ€”so reviewers can explore every layer from protocol handshakes down to trace logs.

## Objectives
- Validate MESI/MOESI protocol compliance across L1/L2 caches.
- Prove data consistency and single-Modified ownership under contention.
- Exercise racer and corner-case transactions with directed + random sequences.
- Collect coverage for states, transitions, sharers, and error scenarios.

## Verification Scope
The environment models processor, directory, and snoop agents; checks state transitions, invalidates, writebacks, and error responses; and logs transactions for post-run analysis. Functional cache models mirror DUT behavior to catch mismatches early.

## Directory Guide
- tl/ â€” DUT stubs or hardware bindings for quick hook-up.
- uvm_tb/ â€” UVM testbench components (agents, sequences, checkers, coverage, scoreboard).
- models/ â€” Functional cache models and shared state trackers.
- scripts/ â€” Automation scripts, including Powershell regression runner.
- docs/ â€” Verification plan, notes, and supporting documentation.
- logs/ â€” Simulation and trace archives (cache_trace_<test>_<seed>.log.zip).
- esults/ â€” Coverage databases and generated reports (e.g. coverage_report.txt).

## How to Run the Suite
1. Ensure your simulator (Questa, VCS, or Xcelium) variables are set.
2. From the repo root, launch the regression:
   `powershell
   pwsh scripts\run_uvm_regression.ps1 -simTool questa -runs 5 -clean
   `
   Swap -simTool for cs/xcelium as needed. The script factory-registers sequences and passes +COH_SEQ=<sequence> automatically.
3. Coverage is enabled via +cover=bcesf and -coverage; UCDB files merge into esults\regression.ucdb.

## Results & Reports
- Review esults\coverage_report.txt for protocol/state coverage.
- Check logs/ for compressed trace files when debugging.
- Any protocol or data anomalies appear in uvm_error messages within run logs.

## Author & Credits
Created by Teja Raghuveer. Inspired by collaborative verification practices across CPU cache teamsâ€”thanks to colleagues who champion rigorous coherency validation. Feel free to reach out for walkthroughs or integration support.
