# CalibRepair

**A reproducible measurement harness for the ISPD'26 post-placement buffering & sizing contest — and what it found.**

The contest leaderboard looks like a timing-vs-ERC trade-off: the top team reports the best TNS
but leaves capacitance violations on the big designs, the second team is nearly clean but ~130
points behind. This repository asks two questions and answers them with the organisers' own
evaluator:

1. **Where does that trade-off actually come from?** (`analysis/` — scoring forensics on the
   organisers' scoring workbook and the published leaderboard)
2. **Is the "empty quadrant" — cap-clean *at* champion-level TNS — reachable with an open-source
   move set?** (`delta/` — the Δ and EQR arm experiments, every arm scored by the official
   `scripts/evaluation.tcl`)

> Research code, not a contest submission. Not affiliated with the organisers. Every number below
> is traceable to a file in this repository; the negative and self-correcting results are kept.

---

## Findings

### 1. On the big design the TNS term saturates, so the ERC term decides

The scoring model, reverse-engineered from the organisers' workbook and validated against the
published reference row:

```
contribution = w × (m − pre) / |pre|      # TNS
contribution = w × (pre − m) / |pre|      # penalties (cap, slew, ...)
design_score = Σ contributions ;  total = Σ design_weight × design_score
```

Reproducing the `OpenROAD Resizer` row with this model gives **1099.35** against the sheet's
**1107.55** — the 8.2 gap is the runtime/displacement terms, which the analysis excludes.

Because the TNS term is normalised against `pre_opt`, its contribution units are enormous in
nanoseconds — and **saturate**:

| design | pre_opt TNS (ns) | 1 TNS contribution unit |
|---|---:|---:|
| ariane | −1 097 386.88 | **13 717 ns** |
| bsg_chip | −489 273.31 | 6 116 ns |
| aes_cipher_top | −311.27 | 3.9 ns |

On **ariane**, the entire TNS spread among the top three teams is 12 116 ns — **less than one
point**. Team33's TNS is ~3× better than Team31's and buys it **0.89 points**, while its cap
violations cost **2.97**; the cap-clean Team31 wins the design. On **bsg_chip** the TNS term does
not saturate, the trade is real and profitable (+11.68 TNS against −3.49 cap), and the winner
wins.

**So the published data cannot tell you what a cap-clean solution costs.** The winner's choices
are consistent with both "cap-clean is expensive for its method" and "its method simply lacks a
cap-repair move". What the data does bound: if the winner is rational, its cap-cleaning cost is at
least the penalty it forgoes — **≥ 40 700 ns equivalent on ariane**, more than 3× the top-3 TNS
spread.

### 2. The Resizer's ERC residue is a timer-fidelity artefact, not a trade-off

The contest's baseline flow runs `repair_design` (ERC repair) **before** `repair_timing`, and then
never again. Adding another ERC pass *after* timing optimisation changed the reported TNS
(−12 748.79 → improved by 49.16 ns) while cutting slew violations from **154.48 → 132.15**, and
then **plateaued at a fixed residual** — consistent with the optimiser repairing against
*placement* parasitics while the evaluator scores *global-routing* parasitics. The pass optimises
a timer that is not the timer being scored.

Two implementation defects were found **by running rather than reasoning**, and both are recorded
because they silently manufacture conclusions:
- `estimate_parasitics -placement` was missing; without it every arm optimises a zero-wire model
  and degenerates (`eqr_base` returned −68.22 ns instead of −19.55; push/restore arms produced *no
  change at all*).
- an arm ordering that made the ERC constraint unreachable before the score was taken.

### 3. The empty quadrant: one design gap, one design wall

Every arm is scored with the official evaluator at OpenROAD `v2.0-26487-gb84a4ac3ae`, and
`eqr_base` reproduces the published Resizer row **bit for bit** (ariane −12 748.79 ns, aes
−19.55 ns, ariane slew 154.48) — so comparisons to the leaderboard are on the same footing.

| design | best cap-clean arm | vs published reference | vs champion | verdict |
|---|---:|---:|---:|---|
| ariane | −7 849.30 ns | **+38.4 %** | 23 % worse | **GAP** |
| bsg_chip | −104 677.16 ns | +12.2 % | 133 % worse (2.33×) | **WALL** |

On ariane the route-aware closed loop reaches a point that is cap-clean (0.0000), slew 6.44 (from
154.48), **+38.4 % TNS over the published reference**, and **2.36× better in TNS magnitude than
the best published ERC-clean entry** (Team31 ariane, −18 493.99). So an ERC-feasible solution
substantially better than anything published *as feasible* exists and is constructed here. On
bsg_chip the same move set hits a wall: the best cap-clean arm is 2.33× worse than the champion.

**Conclusion.** The published empty region is **not** closed by OpenROAD's resizer move set, and
the honest statement is not "ERC is cheap". It is: *no published solution is both cap-clean and at
winner-level TNS; on ariane we construct a much better ERC-feasible point, and on bsg_chip the
open-source move set cannot reach the champion's TNS while staying clean.* The extrapolated value
of that quadrant on the organisers' own weights is ≈ +30 score points, about a quarter of the
123-point gap between 1st and 2nd — which is what makes it worth a paper, not a claim that
constraints are free.

### 4. What I got wrong first

- **Wrong solution family.** I measured Δ on the Resizer (cap-clean on 11 of 12 designs) and
  generalised to the winner (cap-dirty: ariane 15.13, bsg_chip 98.01). The experiment enforced ERC
  on a solution that had already satisfied it — **the constraint was never exercised.**
- **Comparing absolute TNS.** "0.8 % of the TNS headroom to the winner" is meaningless when the
  TNS term is normalised against `pre_opt` — 1 point is 13 717 ns on ariane.
- Both are documented in `analysis/SCORING_ANALYSIS.md` §0 rather than deleted.

---

## Repository layout

| Path | Contents |
|---|---|
| `analysis/SCORING_ANALYSIS.md` | The scoring forensics: model reconstruction, per-design decomposition, the saturated-TNS argument, the quadrant valuation |
| `analysis/workbook.json`, `leaderboard_raw.json`, `baseline.xlsx` | Inputs: the organisers' scoring workbook and the published leaderboard snapshot |
| `analysis/design_scores.csv`, `metric_contributions.csv` | Extracted per-design / per-metric tables used by the analysis |
| `delta/README.md` | The Δ experiment: what does ERC-clean cost in TNS? |
| `delta/EQR_PROTOCOL.md`, `PLAN.md` | Pre-declared protocol and plan for the EQR arm chain |
| `delta/RESULTS.md`, `EQR_RESULTS.md` | Arm-by-arm results, defects found, and the GAP/WALL verdict |
| `delta/*.tcl`, `delta/run_*.sh` | OpenROAD arm chain and driver scripts |
| `delta/*.py` | Collection/parsing/power-table utilities (standard library only) |

## Reproducing

Requirements:

- The **ISPD'26 contest package** (BSD-3-Clause, `ABKGroup/ISPD26-Contest`), including the
  benchmarks, `scripts/evaluation.tcl` and the required OpenROAD fork
  `v2.0-26487-gb84a4ac3ae`.
- A Singularity/Apptainer container with that fork (`ispd26.sif`); the driver scripts default to
  `${SIF:-/dev/shm/ispd26.sif}` and accept `SIF=` to override.
- No Python dependencies beyond the standard library.

```bash
# 1) clone the contest package and fetch the public benchmarks (see its README)
# 2) build the arm chain and score every arm with the official evaluator
delta/run_eqr.sh <design> <bench_unit> "<arm spec>"
# 3) collect the per-arm CSV/JSON
python3 delta/collect_eqr.py ...
python3 delta/parse_eqr.py ...
```

The analysis in `analysis/` needs only the workbook / leaderboard JSON in that directory.

## Data and attribution

- `analysis/baseline.xlsx` is the **organisers'** scoring workbook, linked from the ISPD'26 contest
  description; `analysis/leaderboard_raw.json` is a snapshot of the published leaderboard from
  `ABKGroup/ISPD26-Contest`. They are included here for verifiability and remain the organisers'
  work.
- The contest package itself is **BSD-3-Clause (© 2025 ABKGroup)** and is **not vendored** in this
  repository; only its published results are used.
- Large run artifacts, container images and per-arm logs are excluded.

## Citation

```bibtex
@misc{calibrepair2026,
  title  = {CalibRepair: reproducible measurement and scoring forensics for the ISPD'26 post-placement buffering and sizing contest},
  author = {Duan, Zeyu},
  year   = {2026},
  note   = {https://github.com/getm0ss1moving/CalibRepair}
}
```

## License

MIT — see [LICENSE](LICENSE). The organisers' workbook, leaderboard and contest package keep their
own terms (contest package: BSD-3-Clause).
