#!/usr/bin/env python3
"""Collect EQR arms into the TNS-vs-ERC frontier and read the reachability verdict.

Usage: collect_eqr.py <logs_dir> <design>

Reads <logs_dir>/<label>_metrics.csv (written by the contest's scripts/parse_log.py
over the official evaluator log).  Prints the frontier and the verdict against the
published winner's TNS for that design.

Verdict logic (pre-registered in delta/EQR_PROTOCOL.md):
  REACHABLE   an arm has cap_sum == 0 AND TNS <= winner_TNS
  NEAR        an arm has cap_sum == 0 AND TNS <= winner_TNS * 1.10
  WALL        the best cap-clean arm is worse than winner_TNS * 1.25
  INCOMPLETE  no cap-clean arm at all
"""
import csv
import json
import sys
from pathlib import Path

# published best TNS per design (ISPD26 final leaderboard, README)
WINNER_TNS = {
    "ariane": -6377.76, "ariane_v2": -4277.14, "ariane_h1": -4368.32, "ariane_h2": -3271.86,
    "bsg_chip": -44875.21, "bsg_chip_v2": -18877.64,
    "bsg_chip_h1": -21542.37, "bsg_chip_h2": -21505.02,
    "aes_cipher_top": -44.42, "aes_cipher_top_v2": -43.69,
    "jpeg_encoder": -488.89, "jpeg_encoder_v2": -474.07,
}
COLS = ["tns", "wns", "slew_over_sum", "cap_over_sum", "fanout_over_sum",
        "max_gr_overflow", "total_gr_overflow", "flow_runtime"]


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def arm_order(label):
    """base, push1..N, then restores — the order the frontier is traced in."""
    if label.endswith("_base"):
        return (0, 0, label)
    if "_push" in label:
        try:
            n = int(label.split("_push")[1].split("_")[0])
        except ValueError:
            n = 0
        return (1, n, label)
    if "_restore" in label:
        try:
            n = int(label.split("_restore")[1].split("_")[0])
        except ValueError:
            n = 0
        return (2, n, label)
    return (3, 0, label)


def load(p):
    with open(p, newline="") as fh:
        rows = [r for r in csv.DictReader(fh) if any(v not in (None, "") for v in r.values())]
    return rows[-1] if rows else {}


def main():
    logs = Path(sys.argv[1])
    design = sys.argv[2]
    recs = []
    for p in sorted(logs.glob("*_metrics.csv")):
        label = p.name[: -len("_metrics.csv")]
        d = load(p)
        if not d:
            continue
        r = {"label": label}
        for c in COLS:
            r[c] = num(d.get(c))
        recs.append(r)
    if not recs:
        sys.exit(f"no arm metrics found in {logs}")

    recs.sort(key=lambda r: arm_order(r["label"]))
    base = next((r for r in recs if r["label"].endswith("_base")), recs[0])
    for r in recs:
        r["d_tns"] = (None if base.get("tns") is None or r.get("tns") is None
                      else round(r["tns"] - base["tns"], 4))
        r["erc_sum"] = sum(x for x in (r["slew_over_sum"], r["cap_over_sum"],
                                       r["fanout_over_sum"]) if x is not None)
        r["cap_clean"] = (r["cap_over_sum"] is not None and r["cap_over_sum"] <= 1e-9)

    win = WINNER_TNS.get(design)
    clean = [r for r in recs if r["cap_clean"] and r["tns"] is not None]
    # TNS is negative -> the BEST cap-clean arm is the MAXIMUM (closest to zero).
    # An earlier version used min() and reported the worst clean arm as the best.
    best_clean = max(clean, key=lambda r: r["tns"]) if clean else None
    # TNS is NEGATIVE: "better" means larger (closer to zero).  An earlier version
    # compared with <= and reported REACHABLE for an arm that was 31% WORSE than the
    # winner (-8347.64 vs -6377.76).  The comparisons below are in the correct
    # direction: win * 1.10 is 10% MORE negative, i.e. a 10% allowance.
    verdict = "INCOMPLETE"
    if win is not None and best_clean is not None:
        if best_clean["tns"] >= win:
            verdict = "REACHABLE"
        elif best_clean["tns"] >= win * 1.10:
            verdict = "NEAR"
        elif best_clean["tns"] < win * 1.25:
            verdict = "WALL"
        else:
            verdict = "GAP"

    hdr = (f"{'arm':<26}{'TNS(ns)':>12}{'dTNS':>11}{'cap_clean':>10}"
           f"{'cap_sum':>10}{'slew_sum':>11}{'fanout':>9}{'GRovf':>8}")
    print(f"\n=== EQR frontier: {design} ===")
    print(f"published winner TNS = {win} ns" if win is not None else "no winner reference")
    print(hdr)
    print("-" * len(hdr))
    for r in recs:
        t = f"{r['tns']:>12.2f}" if isinstance(r["tns"], float) else f"{'-':>12}"
        d = f"{r['d_tns']:>11.2f}" if isinstance(r["d_tns"], float) else f"{'-':>11}"
        cc = "yes" if r["cap_clean"] else "no"
        c = f"{r['cap_over_sum']:>10.4f}" if isinstance(r["cap_over_sum"], float) else f"{'-':>10}"
        s = f"{r['slew_over_sum']:>11.2f}" if isinstance(r["slew_over_sum"], float) else f"{'-':>11}"
        f_ = f"{r['fanout_over_sum']:>9.2f}" if isinstance(r["fanout_over_sum"], float) else f"{'-':>9}"
        g = f"{r['total_gr_overflow']:>8.2f}" if isinstance(r["total_gr_overflow"], float) else f"{'-':>8}"
        print(f"{r['label']:<26}{t}{d}{cc:>10}{c}{s}{f_}{g}")

    print(f"\nbest cap-clean arm : "
          + (f"{best_clean['label']}  TNS={best_clean['tns']:.2f} ns" if best_clean else "none"))
    print(f"required for winner: TNS <= {win} ns")
    print(f"VERDICT            : {verdict}")
    if verdict == "REACHABLE":
        print("  -> the empty quadrant is reachable with this move set: a cap-clean")
        print("     solution at winner-level TNS exists.  The paper's target is real.")
    elif verdict == "WALL":
        print("  -> cap-cleanness costs more TNS than the gap to the winner: the")
        print("     trade-off is real for this family.  Publish the frontier, not a win.")
    elif verdict == "INCOMPLETE":
        print("  -> no cap-clean arm produced; the frontier was traced on the wrong side.")

    with open(logs / "eqr_frontier.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(recs[0].keys()))
        w.writeheader()
        w.writerows(recs)
    (logs / "eqr_verdict.json").write_text(json.dumps(
        {"design": design, "winner_tns_ns": win, "verdict": verdict,
         "best_cap_clean": best_clean, "arms": recs}, indent=2) + "\n")


if __name__ == "__main__":
    main()
