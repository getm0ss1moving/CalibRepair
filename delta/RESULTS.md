# Δ results — the price of ERC feasibility

Apparatus: `delta/` — stage snapshots scored by the contest's own `evaluation.tcl` inside
`./containers/ispd26.sif` (OpenROAD `v2.0-26487-gb84a4ac3ae`, the required fork).
Stage 0 = the published OpenROAD Resizer flow; stage k = + k `repair_design` (ERC-repair)
passes. Official numbers: global route → `estimate_parasitics -global_routing` → OpenSTA.

---

## Headline

**On ariane, making the flow ERC-clean does not cost TNS — it *gains* 49 ns. What blocks
ERC-clean is not the constraint's price but the timer's fidelity to the scoring timer.**

| stage | TNS (ns) | ΔTNS | Δ% | slew over (count) | cap over (count) | fanout | GR ovf |
|---|---:|---:|---:|---:|---:|---:|---:|
| 0 resizer | −12 748.79 | — | — | **154.48 (3798)** | 0.01 (1) | 0.000 | 0 |
| 1 +ERC | −12 699.63 | **+49.16** | **+0.386 %** | **132.15 (3619)** | 0.00 (0) | 0.000 | 0 |
| 2 +ERC | −12 699.63 | +49.16 | +0.386 % | 132.15 (3619) | 0.00 (0) | 0.000 | 0 |

ariane / `TCP_900_UTIL_0.30`, 138 762 instances, flow runtime 102 s per stage.

**Reading.**

1. **G-Δ3 passes on price.** `|Δ|/|TNS₀| = 0.386 %`, far inside the 5 % band, and the sign is
   favorable: repairing electrical rules *improved* setup TNS. The ERC constraint is not a
   wall on this design.
2. **But ERC does not reach zero** — it plateaus at 132.15 of slew violation after the first
   pass, and the second pass changes nothing. `repair_design` optimises against **placement**
   parasitics; the evaluator scores against **global-routing** parasitics. The loop cannot
   see the violations it is being judged on, so it cannot close them.
3. **The residual is cheap in the 2026 metric and expensive in the 2027 metric.** ISPD 2026
   weights slew at `w_slew = 0.001` (capacitance is 10), so 3619 residual slew violations are
   worth almost nothing there. ISPD 2027 raises slew to `0.1`, i.e. ~100× relative to TNS.
   The residual is exactly the thing that becomes first-order next year.

**The sentence this buys the paper:**

> Closing the ERC gap costs about **0.8 %** of the TNS headroom that separates the Resizer
> from the contest winner on ariane (49.16 ns of the 6 371 ns gap between our Resizer run,
> −12 748.79 ns, and Team33's published −6 377.76 ns). The obstacle to ERC-clean is not the
> price of the constraint; it is that the optimiser cannot see the timer it is scored by.

That is the calibration thesis, now *measured* rather than assumed — and it is a
substantially better result than "the constraint is free".

---

## Result 1 — AES: the published flow is already ERC-clean (regime ①, vacuous)

`aes_cipher_top / TCP_250_UTIL_0.40`, 15 141 instances (official evaluator count).

| quantity | value |
|---|---:|
| setup TNS | −19.55 ns |
| setup WNS | −0.09 ns |
| slew / cap / fanout violation sums | 0.0 / 0.0 / 0.0 |
| max / total GR overflow | 0 / 0 |
| OR RSZ runtime / flow runtime | 70 s / 10 s |
| stage 1, 2 TNS | −19.55 ns (Δ = 0.000) |

**Regime ① is a failure, not a success:** on AES the ERC pass is a no-op, so a "Δ = 0" there
would have read as "ERC is free" while proving nothing. Any AES-only experiment would have
produced a misleading conclusion. This confirms, by measurement, the note already in
`idea_review/idea1_tasklist.md` §P10 (*"不建议用 aes/aes_v2/jpeg/jpeg_v2 作判据"*).

**Consequence:** Δ must be measured on ariane and bsg_chip, where the violations live.

---

## Result 2 — the apparatus, and the two bugs it caught

Verified end to end on two designs: the SIF runs the required fork; `evaluation_baseline.tcl`
and `evaluation.tcl` both complete; the contest's own `scripts/parse_log.py` reads our logs;
`delta/run_frontier.sh` produced 3 stage snapshots per design, scored each with the
**unmodified** official evaluator (stage snapshots are written into
`Benchmarks/<design>/iter_<k>/`, so `design_setup.tcl` needs no edit), and merged them.

Two real defects were found by running rather than reasoning:

1. **Stage 0 was not legalized before snapshotting.** `evaluation.tcl` exits on
   `check_placement` (DPL-0033), so `iter_0` could not be scored at all. Without the fix,
   every Δ would have read as "no data". Fixed in `frontier.tcl`.
2. **`parse_log.py --csv` appends.** A re-parse left an old design's row ahead of the new
   one, and the collector reported AES numbers under the ariane table. Fixed in three
   places: the driver removes the CSV before parsing, `collect.py` takes the last row, and
   the driver now writes per-design artifacts (`logs/<design>/`) so two designs can no
   longer clobber each other's stage metrics.

Both are the class of error that a plan cannot catch and a run always does. The ariane
table above was regenerated with the fixed path and re-derived from the three official
evaluator logs on the run host (`./logs/iter_*.csv`, `frontier.csv`).

---

## Gates, as read

| gate | criterion | verdict on ariane |
|---|---|---|
| **G-Δ1** reference | `iter_0` reproduces the published Resizer within 1 % | **partial** — our Resizer ariane run is self-consistent and uses the sanctioned evaluator, but the organizers publish only the aggregate Resizer score (1107.55), not per-design; per-design verification needs the organizers' baseline spreadsheet |
| **G-Δ2** trend | ERC sums fall monotonically over stages | **partial** — falls 154.48 → 132.15, then **plateaus**. The pass binds once and then cannot see the residual |
| **G-Δ3** price | ERC 0 **and** \|Δ\| < 5 % | **price passes (0.386 %); ERC ≠ 0** → not full dominance, but the failure mode is informative rather than fatal |
| **G-Δ4** wall | \|Δ\| > 15 % | **not triggered** — the trade-off is not a wall |

Note G-Δ3 as originally written conflated two things: *the price of the constraint* (cheap,
measured) and *reachability of ERC 0* (blocked, by estimator mismatch). They are separate
findings and the second one is the better paper.

---

## What this changes in the plan

1. **The claim moves from "ERC as a hard constraint" to "close the loop on the scoring
   timer".** The measured obstacle is estimator mismatch, not constraint cost. That is
   precisely the differentiable-timer-plus-calibration contribution (idea.md §P4/P5 T4.x),
   and it now has a two-line empirical justification from the contest's own flow.
2. **Design selection is settled.** Δ/ERC claims belong on ariane and bsg_chip; AES, jpeg
   and their `_v2` variants are control cases (the constraint is inactive there). AES must
   never be the sole evidence.
3. **The 20 Oct gate should be re-cut.** `idea1_tasklist.md` gates 20 Oct on "ERC 0 and score
   ≥ 89.81 on ariane". Add the measured pair: *Δ on ariane ≤ 5 %* (already satisfied,
   0.386 %) **and** *residual ERC explainable by timer fidelity, not by constraint cost*.
   A repair pass that plateaus is evidence for the method, not against it — provided the
   distinction is measured, which it now is.
4. **The weight asymmetry is a motivation asset.** ISPD 2026 pays 0.001 for slew; ISPD 2027
   pays 0.1 and 1.0 for overflow. The residual violations we cannot close today become
   first-order next year. Cite the contest description; claim only the method.

---

## Pending — bsg_chip

`bsg_chip / TCP_1200_UTIL_0.30` (829 MB staged, ~1.4 M instances, the family holding 55 % of
the capacitance points) is running with 1 ERC-repair pass. Expect hours, not minutes:
the contest teams' tool runtimes on this design were 2 200–6 300 s. Artifacts will land in
`./logs/` on the run host exactly as for ariane.
