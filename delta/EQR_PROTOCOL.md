# EQR — Empty-Quadrant Reachability: pre-registered protocol

**Question.** Does a solution exist that is **ERC-clean** *and* at **winner-level TNS**?

**Why it must be asked this way.** The final leaderboard (README) contains no such solution:
every top-3 entry is either ERC-dirty at good TNS (Team33) or ERC-clean at worse TNS
(Team31/29). And the two earlier experiments in this repo cannot answer the question:

| experiment | what it enforced | why it is silent on the question |
|---|---|---|
| `delta/RESULTS.md` (Δ) | ERC repair **after** timing, on the published Resizer | the Resizer is **already cap-clean on 11/12 designs**; the violations it has are **slew**, at weight **0.001** |
| `ERC_SKIP_INITIAL` (TNS-only) | removal of the leading `repair_design` | the design starts at TNS ≈ −3.36 M and `repair_timing` cannot buffer legally; the arm measures a broken flow, not a trade-off |

Both did work on the **slew** axis. The axis that decides the big designs is **capacitance**
(weight 10 vs 0.001), and it was never exercised. EQR exists to exercise it.

---

## Arms

One OpenROAD process per arm; every arm is snapshotted into
`Benchmarks/<design>/<label>/` and scored by the **unmodified** official evaluator
(`scripts/evaluation.tcl`, `FOLDER_NAME=<label>`).

| arm | flow | what it isolates |
|---|---|---|
| `eqr_base` | `repair_design ; repair_timing -setup` | the published flow → **must reproduce the official Resizer** |
| `eqr_pushN` | base + N extra `repair_timing -setup` | TNS bought by re-optimising on a stale electrical state |
| `eqr_relaxN` | base, then **relax `max_transition`/`max_capacitance`/`max_fanout` to 100/100/1000**, then N extra `repair_timing -setup` | **the strong lever**: TNS bought by making the electrical rules non-binding |
| `eqr_restoreP_from_X` | fresh process, library limits active, reads arm X's snapshot, `{repair_design ; repair_timing} × P` | the price of putting ERC back at X's operating point |

`relax` is the arm that matters. `repair_design` enforces the rules *before* timing is
optimised and never again, so an arm that relaxes the rules and then optimises timing is the
closest reproduction, inside a standard flow, of the mechanism the winner used: **good TNS
with unresolved electrical violations**.

Every arm ends with `detailed_placement` if needed, because `evaluation.tcl` exits on
`check_placement` — an illegal snapshot cannot be scored at all.

---

## Pre-registered gates

Written before the numbers are read; the point is that the outcome cannot be rationalised
into a pass afterwards.

| id | criterion | if it fails |
|---|---|---|
| **G-EQR-1** fidelity | `eqr_base` matches the organisers' published Resizer TNS for that design **within 1 %** (workbook `Design Scores`) | the arms are not comparable to the leaderboard; fix before reading anything else |
| **G-EQR-2** lever | some arm reaches `cap_sum > 0` (the relaxation actually creates capacitance violations) | the lever does not bind → EQR cannot answer the question on this design |
| **G-EQR-3** reachability | some arm has `cap_sum == 0` **and** `TNS ≤ winner_TNS` | see verdicts below |
| **G-EQR-4** price | for the most pushed arm X, `\|TNS(restore from X) − TNS(X)\| / \|TNS(X)\|` | this is the ERC price at the pushed operating point — the number the paper reports |

## Verdicts

| verdict | condition | meaning for the paper |
|---|---|---|
| **REACHABLE** | a cap-clean arm with `TNS ≤ winner_TNS` | the quadrant is reachable; the claim *"nobody published a cap-clean solution at winner-level TNS; we construct one"* is empirically supported |
| **NEAR** | cap-clean arm with `TNS ≤ 1.10 × winner_TNS` | the quadrant is within reach; state the residual gap explicitly |
| **GAP** | cap-clean arm between 1.10× and 1.25× winner_TNS | publish the frontier; the claim becomes "the quadrant is approachable and we quantify the gap" |
| **WALL** | best cap-clean arm worse than 1.25× winner_TNS | the trade-off is real for this move set; the ERC-constrained frontier is the contribution, and a stronger optimizer is required to claim dominance |
| **INCOMPLETE** | no cap-clean arm produced | the frontier was traced on the wrong side; add arms |

The verdict is read off `eqr_frontier.csv` / `eqr_verdict.json`, not off a plot.

---

## Falsification

The protocol is wrong, and must be revised rather than reinterpreted, if any of these hold:

1. `eqr_base` does not reproduce the published Resizer → the arm chain is not the official flow.
2. No arm produces capacitance violations → relaxation is not binding; use a different lever
   (per-net capacitance budgets, buffer-count limits) before drawing any conclusion.
3. A cap-clean arm is produced **without** any TNS loss relative to base → the frontier was
   never actually traced (the lever did nothing), so "REACHABLE" would be vacuous, i.e.
   regime ① from `PLAN.md` — a failure dressed as a success.

---

## Threats to validity (state all of these in the paper)

* **Move set.** EQR uses OpenROAD's resizer move set. A REACHABLE verdict is strong
  (existence); a WALL verdict is **not** a proof about other optimizers — it bounds *this*
  family only. This asymmetry must be stated: existence transfers, non-existence does not.
* **Ideal clocks.** The ISPD 2026 evaluation is post-placement with `set_ideal_network
  [all_clocks]`; the ISPD 2027 setting uses propagated clocks and MCMM, so a frontier traced
  here does not transfer to the successor problem unchanged.
* **Single deterministic run.** OpenROAD's resizer is deterministic for a fixed flow, but the
  relaxation value is a hyper-parameter; report a sweep, not a point.
* **Public designs only.** `ariane_h1/h2`, `bsg_chip_h1/h2` were hidden during the contest and
  are public now; Team6 (not Team33) is best on three of them, and its per-design numbers are
  not published, so the "winner TNS" reference for those three is a **lower bound on the best
  published TNS**, which makes REACHABLE conservative and WALL optimistic on them.
* **Score model.** The published `design_score` is reproduced to ~0.7 % from the raw metrics
  (`analysis/SCORING_ANALYSIS.md`); the cap term itself is exact.

---

## Run

```sh
ssh <run-host>
cd ~/calibrepair
# ariane first: cheap, validates the arm chain against the published Resizer
bash upstream/delta/run_eqr.sh ariane TCP_900_UTIL_0.30 \
     "base,push:1,push:2,relax:1,relax:2,restore:2:eqr_relax2,restore:2:eqr_push2"
# then bsg_chip: the family that holds 55 % of the capacitance points
bash upstream/delta/run_eqr.sh bsg_chip TCP_1200_UTIL_0.30 \
     "base,relax:2,restore:2:eqr_relax2"
```

Artifacts: `./logs/<design>/eqr/` — per-arm logs, per-arm official
`*_metrics.csv`, `eqr_frontier.csv`, `eqr_verdict.json`, `eqr_table.txt`.

---

## Addendum: the `loop` arm (M1 minimal core)

Added 2026-10-09 after the corrected decomposition (`EQR_RESULTS.md` Result 1) showed the
ERC axis carries only -12 % of the winner's advantage.  The `loop` arm tests the one
mechanism the measurements say is *structurally* missing, independently of the champion:

> The published flow repairs electrical rules against **placement** parasitics, while the
> official evaluator scores against **global-routing** parasitics.  The constraint is defined
> on an extraction the optimiser never sees, so ERC repair plateaus (ariane: slew 154.48 ->
> 132.15 and stops).

`loop:N` = published base, then N rounds of
`detailed_placement -> global_route -> estimate_parasitics -global_routing -> repair_design
-> repair_timing -setup`.  The optimiser sees the scoring parasitics on every round after the
first.

**Gate G-LOOP.**

| id | criterion | meaning |
|---|---|---|
| **G-LOOP-1** | the arm's own stage report (now on global-routing parasitics) shows `cap_sum == 0` **and** `slew_sum -> 0` within N rounds | ERC feasibility is *certifiable* once the loop is closed on the scoring extraction |
| **G-LOOP-2** | TNS at that point is no worse than `eqr_base`'s official TNS (-12 748.79 on ariane) | closing the loop does not cost timing |

Outcomes:

* **Both pass** -> "close the loop on the scoring extraction" is the paper's minimal core
  mechanism: neither the champion (which abandoned ERC, -43 points) nor the Resizer (which
  cannot see the constraint) does this.  M2 (corner-robust discrete assignment) and M3 (the
  constrained front) then add to it.
* **G-LOOP-1 fails** (slew floors out) -> ERC feasibility genuinely conflicts with TNS at this
  operating point; the paper becomes a constrained-front study, and the novelty rests on the
  front, not on a mechanism.
* **G-LOOP-2 fails** (TNS collapses) -> the loop buys feasibility at the cost of the primary
  objective; report the trade-off explicitly.

**Known threat.** `global_route` is expensive and is called once per round, and the official
5 h envelope is what the contest enforces.  A method built on this loop must show it fits the
envelope, or replace the loop with a fitted model of the global-routing extraction - which is
itself the calibration contribution (M1) and is what makes M1 more than "call the router".
