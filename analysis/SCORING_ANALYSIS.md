# Does the winner keep its effect under an ERC constraint? — the published data says no, and why

Written 2026-10-09. Sources: the organisers' own scoring workbook
(`Baseline.xlsx`, linked from the ISPD 2026 contest description; sheets *Ranking /
Design Scores / Metric Contributions / Scoring Config / Design Weights*), the final
leaderboard in `ABKGroup/ISPD26-Contest/README.md`, and our own runs in
`./containers/ispd26.sif`.

---

## 0. The two errors in my earlier claim

**Error 1 — wrong solution family.** I measured Δ on the **OpenROAD Resizer** and
generalised to the winner. But the Resizer is **cap-clean on 11 of 12 designs** (ariane cap =
0.0, bsg_chip cap = 0.0). The winner is **cap-dirty** (ariane 15.13, bsg_chip 98.01). The two
sit on opposite sides of the only ERC axis that carries weight. My experiment enforced ERC on
a solution that had already satisfied it — the constraint was never exercised.

**Error 2 — comparing absolute TNS.** I framed the cost as "0.8 % of the TNS headroom to the
winner". That is meaningless here: the TNS term is normalised against `pre_opt`, whose TNS on
ariane is **−1 097 386.88 ns**. Any solution that repairs timing at all lands near the ceiling.

| design | pre_opt TNS (ns) | 1 contribution unit of TNS |
|---|---:|---:|
| ariane | −1 097 386.88 | **13 717 ns** |
| bsg_chip | −489 273.31 | 6 116 ns |
| aes_cipher_top | −311.27 | 3.9 ns |

On ariane, **13 717 ns of TNS is worth one point** (out of 80). The entire TNS spread among
the top three teams on that design is 12 116 ns — less than one point.

---

## 1. What the winner's advantage is actually made of

Scoring model, reverse-engineered from the workbook and validated:
`contribution = w × (m − pre)/|pre|` for TNS and `w × (pre − m)/|pre|` for the penalties;
`design score = Σ contributions`; `total = Σ design_weight × design score`
(ariane ×1.2, bsg_chip ×1.5, aes/jpeg ×1.0). Reproducing the Resizer row by row gives
**1099.35** against the sheet's published **1107.55** — the 8.2 difference is the
runtime/displacement terms, which I exclude here.

### ariane — the TNS term is saturated, the cap term decides

| method | TNS (ns) | TNS contrib | cap sum | cap contrib | others | **sum** | published score |
|---|---:|---:|---:|---:|---:|---:|---:|
| Team33 (1st) | −6 377.76 | **79.54** | 15.13 | **7.03** | 8.67 | **95.24** | 94.33 |
| Team31 (2nd) | −18 493.99 | **78.65** | 0.00 | **10.00** | 7.72 | **96.37** | 95.94 |
| Team29 (3rd) | −18 254.21 | 78.67 | 0.00 | 10.00 | 7.79 | 96.46 | 96.04 |
| Resizer | −12 748.79 | 79.07 | 0.00 | 10.00 | — | 89.81 | — |

**Team33's TNS is 3× better than Team31's and buys it 0.89 points. Its cap violations
cost it 2.97 points.** Net: the cap-clean Team31 wins ariane, exactly as the published
design scores say (95.94 > 94.33).

### bsg_chip — the TNS term does not saturate, so the trade is real there

| method | TNS (ns) | TNS contrib | cap sum | cap contrib | others | **sum** | published |
|---|---:|---:|---:|---:|---:|---:|---:|
| Team33 | −44 875.21 | **72.66** | 98.01 | **6.51** | 10.10 | **89.28** | 88.55 |
| Team31 | −116 298.92 | **60.98** | 0.00 | **10.00** | 8.96 | **79.95** | 80.12 |
| Team29 | −120 350.04 | 60.32 | 0.01 | 10.00 | 8.91 | 79.24 | 78.41 |

Here the winner's TNS buys **11.68 points** and its cap violations cost **3.49**. The trade
is profitable, and it wins.

---

## 2. The answer to the question

> Can the winner's method be trusted to keep this effect under an ERC constraint?

**It depends on the design family, and on the big designs the answer is "the question is
malformed" — because on ariane the winner is already losing to a cap-clean solution.**

* **ariane family.** The winner does not gain its ariane position from ERC slack; the TNS term
  is saturated, so 3× better TNS is worth 0.89 points while cap-cleanliness is worth 2.97. The
  winner is *leaving points on the table* here. Forcing ERC would change nothing about its
  relative position — it already loses ariane.
* **bsg_chip family.** The winner's cap violations are a **profitable, rational trade**
  (+11.68 TNS against −3.49 cap). Force cap-cleanliness and its margin over Team31 falls from
  8.19 to roughly 4.7 points — still ahead, *provided the TNS survives*. Whether it survives is
  exactly what is unknown.

So the honest statement is not "ERC is cheap, the winner could have been clean". It is:

> The published leaderboard contains **no cap-clean solution at winner-level TNS**, and it
> contains **no evidence either way** about what such a solution would cost. The winner's own
> choices are consistent with *both* "cap-clean is expensive for its method" and "its method
> simply lacks a cap-repair move". The data cannot separate them.

### What the winner's own optimality does bound

The winner's objective already contains the cap penalty (weight 10, capped at its weight).
It chose to stay dirty. Setting aside the capability explanation, its cap-cleaning cost must
therefore be **at least the penalty it forgoes**:

| design | penalty forgone (contribution units) | equivalent TNS |
|---|---:|---:|
| ariane | 2.97 | **≥ 40 700 ns** |
| bsg_chip | 3.49 | ≥ 21 300 ns |

On ariane that threshold is more than three times the entire TNS spread of the top three teams.
So **if the winner is rational and capable, ERC is very expensive for its method** — the
opposite of what I claimed. If it is merely incapable, ERC is cheap and a large opportunity is
open. Both readings are defensible from the data; neither is established.

---

## 3. The quadrant that the whole field left empty — and what it is worth

Define the target point: **cap-clean at the best published TNS.** It appears nowhere in the
leaderboard. Its value, computed with the organisers' own weights:

| design | Team33 sum | best-TNS + cap-clean | gain | × design weight |
|---|---:|---:|---:|---:|
| ariane | 95.24 | 98.21 | +2.97 | **+3.56** |
| bsg_chip | 89.28 | 92.76 | +3.49 | **+5.23** |

Extrapolated over the eight ariane/bsg_chip designs: roughly **+30 score points**, about a
quarter of the 123-point gap between 1st and 2nd. That is the paper's target, and it is
defensible without any claim about the winner's internals:

> *No published solution is both cap-clean and at winner-level TNS. We construct one. On the
> organisers' own scoring model that quadrant is worth ≈30 points.*

This is a stronger claim than "we added a constraint and did not lose performance", and unlike
that claim it does not require an unproven extrapolation.

---

## 4. What the Δ experiment was still worth, and what it was not

Kept:

* **G-Δ1 is exact.** Our Resizer run reproduces the organisers' reference bit for bit
  (ariane TNS −12 748.79, aes −19.55, ariane slew 154.48). The apparatus is the official one.
* **The Resizer's ERC residue is a timer-fidelity artefact, not a trade-off**: adding an ERC
  repair pass after `repair_timing` *improved* TNS by 49.16 ns on ariane while cutting slew
  violations from 154.48 to 132.15, then plateaued — because `repair_design` optimises against
  placement parasitics and the evaluator scores global-routing parasitics.

Retracted:

* The "0.8 % of headroom" sentence, and the inference that the winner could be made cap-clean
  cheaply.
* The claim that the Δ experiment supports the paper. **It cannot.** The residue it addresses
  is *slew*, at weight 0.001, worth 0.001 points. The axis that decides the big designs is
  *capacitance*, at weight 10 — and the Resizer never violates it, so the experiment never
  touched it.

The timer-fidelity finding survives as a **method argument** (you need the loop closed on the
scoring timer), not as a **result**.

---

## 5. The experiment that would actually settle it

Remove the ERC constraint from the flow and see what TNS freedom buys:

* **stage 0′** = `repair_timing -setup` **without** the published leading `repair_design`
  (ERC repair omitted entirely) → a cap-dirty, higher-TNS point;
* **stage k′** = `repair_design` passes applied to it → the price of putting cap back.

* If stage 0′ gains a lot of TNS and stage k′ costs little → **cap-clean is cheap at high TNS**
  → the empty quadrant is real and reachable → the paper's claim stands on its own.
* If stage k′ gives back most of stage 0′'s TNS → **the trade is real for this solution family**
  → ERC constraint work must be sold as the frontier, not as a win.

Running now on ariane (`ERC_SKIP_INITIAL=1`, `delta/frontier.tcl`), evaluated by the official
`evaluation.tcl`.

**Limit of this experiment, stated up front:** it still uses the Resizer's move set. It answers
"is ERC a wall for *this* family", not "would the winner's family hit the wall". Only a
constructed optimizer can answer the second, which is why the paper has to build one.
