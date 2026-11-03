# Idea 1 — the ERC-price experiment plan (executable)

Scope: answer, **before** any differentiable timer or GPU work, whether "ERC as a hard
constraint" is a *cheap* constraint or a *wall*. This is the load-bearing assumption of
Idea 1 and it is the only one that can be tested with the contest's own tools in days.

Baseline date 2026-10-09. DAC 2027: abstract **11 Nov**, manuscript **18 Nov**.
Existing gates it must plug into (`idea_review/idea1_tasklist.md` §P10): 14 Oct evaluator
smoke, 17 Oct resizer reproduction, **20 Oct go/no-go**.

---

## The question, stated so it can fail

Let `TNS*_U` be the best setup TNS the flow reaches with ERC unconstrained, and `TNS*_C`
the best with ERC enforced. Define

> **Δ = TNS*_C − TNS*_U**  (the shadow price of ERC feasibility)

Three regimes, and only one of them is a paper:

| regime | `|Δ| / |TNS*_U|` | ERC state | verdict |
|---|---|---|
| ① vacuous | ≈ 0 | already clean | **no contribution** — the constraint is decoration |
| ② binding + degrading | > 15 % | clean | the trade-off is real → re-frame or drop |
| ③ **binding + non-degrading** | **< 5 %** | clean | **the target**: dominance, and the constraint is the novelty |

Regime ③ is what the paper needs. Note that ① is a *failure*, not a success: a constraint
that changes nothing cannot carry a contribution.

---

## Stages

| # | Stage | Apparatus | Days | Output | Gate |
|---|---|---|---|---|---|
| **a** | **Δ on the Resizer** | `delta/run_frontier.sh` (this kit) — the contest's own flow, + k `repair_design` passes | 1–2 | `frontier.csv`, Δ per design | **G-Δ3** `\|Δ\|<5 %` with ERC 0 |
| **b** | **ε-sweep frontier** | vary the ERC budget (margin / violation cap) instead of iteration count; plot TNS vs ERC | 2–3 | `frontier.png` with Team33 / Team31 / RSZ plotted | frontier passes through ERC≈0 |
| **c** | **λ diagnostics** | augmented-Lagrangian multipliers on slew / cap / fanout during *our* optimizer | 1–2 | λ table + the TNS each one costs | λ_slew≈0, λ_cap>0 as predicted by the weights |
| **d** | **Ablation** | penalty vs projection vs augmented Lagrangian, at matched ERC | 2–3 | 3-row table | the *form* of the constraint is what matters, not its presence |

Stage (a) needs no new code and can start today. Stages (b) reuse (a)'s harness. Stages
(c)–(d) need the optimizer, so they belong to the DAC-2027 critical path only if (a) passes.

---

## Why (a) is decisive and cheap

The contest baseline does

```
repair_design                                            # ERC repaired here
repair_timing -setup -skip_gate_cloning -skip_pin_swap   # ... and never again
```

so the published flow **already pays the price of ERC once, in the wrong place**. Adding a
second `repair_design` after timing measures exactly what the constraint costs when it is
enforced *after* the TNS decisions rather than before. One extra pass per design.

If Δ is small, the leaderboard's ERC/TNS trade-off is an **optimizer artifact** (evidence:
Team31 is nearly ERC-clean and still beats the Resizer by 207 points), and the paper's
thesis — enforce ERC as a constraint *inside* the loop — has a measurable, cheap win.

If Δ is large, **stop**, and say so on 20 Oct rather than on 4 Nov.

---

## Pre-registered gates (write these down before the first run)

| id | when | criterion | fail action |
|---|---|---|---|
| **G-Δ1** | stage a, run 1 | `iter_0` reproduces the published Resizer score within 1 % | environment is wrong; nothing else counts until it passes |
| **G-Δ2** | stage a | ERC violation sums decrease monotonically over `iter_1..K` | the repair pass does not bind → the premise is void |
| **G-Δ3** | stage a | ERC 0 **and** `\|Δ\|/\|TNS(0)\| < 5 %` | → stage (b), publish the frontier (L3 claim) |
| **G-Δ4** | stage a | `\|Δ\|/\|TNS(0)\| > 15 %` | the trade-off is a wall → **drop Idea 1**, people move to Idea 2 |
| **G-Δ5** | 20 Oct, with the above | winner-level TNS headroom visible on ≥1 ariane design | switch the headline to the ERC-clean fallback, or pivot |

G-Δ1 and G-Δ2 are apparatus checks. G-Δ3/G-Δ4 are the decision — they must be read off
`frontier.csv`, not off a plot or an impression.

---

## Headline consequences (decide now, not after the numbers)

Whichever way it lands, the title claim should be the one that survives the *worst*
plausible outcome of this experiment:

* **Claim L3 (always true, weakest):** we publish the first TNS-vs-ERC frontier for this
  problem, with every submitted contest point plotted on it, and quantify the shadow price
  of ERC feasibility.
* **Claim L2 (needs G-Δ3):** ERC-clean on the large designs at winner-level TNS on at least
  half of the 12.
* **Claim L1 (needs dominance):** zero ERC at winner-level TNS everywhere.

Write the abstract to **L3’s** shape and upgrade as the data allows. Do not write it to L1
and hope.

---

## Artifacts

| path | role |
|---|---|
| `delta/frontier.tcl` | resizer + k ERC-repair passes, stage snapshots |
| `delta/run_frontier.sh` | driver: frontier → official evaluation per stage → parse |
| `delta/collect.py` | merged Δ table (`frontier.csv` / `.json`) |
| `delta/parse_frontier.py` | per-stage parser for the intermediate (placement-parasitic) numbers |
| `delta/README.md` | the experiment itself, gates, and paper caveats |

Remote staging (verified): `./upstream` (ISPD 2026 repo + `Benchmarks/aes_cipher_top/TCP_250_UTIL_0.40`)
scored inside `./containers/ispd26.sif` (OpenROAD `v2.0-26487-gb84a4ac3ae`).
