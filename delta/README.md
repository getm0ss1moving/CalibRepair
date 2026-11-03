# Δ experiment — what does ERC-clean cost in TNS?

One question, one number, cheap apparatus: **the price of ERC feasibility.**

The published ISPD 2026 leaderboard contains two points that look like a trade-off:

| point | ERC (capacitance violations) | score |
|---|---|---|
| Team33 (1st) | dirty on all 8 ariane/bsg_chip designs | **1438.06** |
| Team31 (2nd) | nearly clean | 1314.93 |
| OpenROAD Resizer | clean-ish | 1107.55 |

You cannot tell from the leaderboard whether the 131-point TNS gap is **caused by the ERC
constraint** or by **optimizer strength**. That confound is the thing to remove, and the
cheapest place to remove it is the OpenROAD Resizer: rerun it with and without a final
ERC-repair pass, on the same design, and measure the TNS difference.

## Why this is nearly free

The contest's own baseline script (`scripts/evaluation_baseline.tcl`) runs

```
repair_design                          # the ERC-repair pass
repair_timing -setup -skip_gate_cloning -skip_pin_swap   # the TNS-optimising pass
```

i.e. **ERC is repaired *before* timing is optimised, and never again.** So:

* `iter_0` = the published flow → TNS, ERC violations (expected: ERC dirty)
* `iter_k` = `iter_0` + k further `repair_design` passes → TNS, ERC violations

`Δ = TNS(iter_k) − TNS(iter_0)` is the price of the ERC constraint, measured with the
contest's own evaluator, with no new modelling and no GPU.

## Run

```sh
ssh <run-host>
cd ~/calibrepair
bash upstream/delta/run_frontier.sh aes_cipher_top TCP_250_UTIL_0.40 3 0
#                                                        design  bench_unit  iters margin
```

For a design with soft placement blockages use its `_v2` unit; the snapshots are written
into `<repo>/Benchmarks/<design>/iter_<k>/{contest.def,contest.v,contest.sdc}`, which is
exactly where `design_setup.tcl` looks when `FOLDER_NAME=iter_<k>`, so the official
evaluator scores each stage **unmodified**.

Artifacts land in `./logs/`:

| file | contents |
|---|---|
| `frontier.log` | resizer + ERC-repair stages, with intermediate `report_tns` / `report_check_types` |
| `eval_iter_<k>.log` | the official evaluator on stage k |
| `iter_<k>_metrics.csv` | official per-stage metrics (contest parser) |
| `frontier.csv` / `frontier.json` / `frontier_table.txt` | the merged Δ table |

## Gates (pre-registered — decide before looking at the numbers)

Fix these **before** the first run; the point of a gate is that the answer cannot be
rationalised into a pass afterwards.

| gate | criterion | pass means | fail action |
|---|---|---|---|
| **G-Δ1** reference | `iter_0` reproduces the published Resizer score for this design **within 1 %** | the apparatus is measuring the right thing | fix the environment; every later number is void |
| **G-Δ2** trend | ERC violation sums fall monotonically over `iter_1..iter_K` | the ERC-repair pass actually binds | the pass does not bind → the premise is wrong, stop |
| **G-Δ3** price | `\|Δ\| / \|TNS(0)\| < 5 %` **and** ERC is zero (or within the leaderboard's best) | **dominating region**: ERC can be had nearly free → the leaderboard trade-off is an optimizer artifact, and the paper's central hypothesis survives | see below |
| **G-Δ4** wall | `\|Δ\| / \|TNS(0)\| > 15 %` | the trade-off is **real** | do not build the differentiable optimizer on this premise; re-frame as "the ERC–TNS frontier" or drop the idea |

Between 5 % and 15 % → partial: the claim becomes the frontier itself (L3 in the
strategy), not dominance.

## What each outcome means for the paper

* **ERC-clears at < 5 % TNS cost.** The strongest possible position: the constraint is
  cheap for a *deliberate* optimizer and expensive only for one that repairs ERC first and
  optimises timing afterwards. The contribution becomes structural ("ERC as a constraint
  inside the loop, not a pass before it") and the result is a point that dominates the
  winner's on ERC while holding its TNS.
* **ERC costs 5–15 %.** Publish the frontier: TNS vs ERC-violation budget, with the three
  published contest points plotted on it. Still a real contribution — nobody has published
  that curve — but it is a trade-off study, not a win.
* **ERC costs > 15 %.** The premise dies cheaply, which is the point of running this first.
  Redirect to Idea 2 (TreeFloor) rather than spending 40 days discovering it.

## Caveats to state in the paper

* The Resizer is one optimizer, not the space of optimizers. A small Δ here bounds the
  price for *this* flow; it does not prove a differentiable optimizer finds it cheaper.
  The honest claim is the conditional one — *for a flow that repairs ERC before timing,
  enforcing ERC afterwards costs x %* — plus the frontier.
* `repair_design` optimises slew/capacitance/fanout against **placement** parasitics;
  the evaluator measures against **global-routing** parasitics. Part of any residual
  violation comes from that mismatch, which is itself a finding worth reporting.
* Run the biggest design too (ariane/bsg_chip): the winner's ERC gap lives in exactly
  those families (bsg_chip holds 55 % of the capacitance points).
