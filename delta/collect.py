#!/usr/bin/env python3
"""Merge the per-stage official evaluations into the Delta frontier table.

Usage: collect.py <logs_dir> <iters> <design>

Reads  <logs_dir>/iter_<k>_metrics.csv   (written by the contest's scripts/parse_log.py)
Writes <logs_dir>/frontier.csv and prints the table.

Column names come from the contest parser, so the numbers are the contest's own
(official evaluator: global route -> global-routing parasitics -> OpenSTA reports).
"""
import csv
import json
import sys
from pathlib import Path

COLS = ["tns", "wns", "slew_over_sum", "cap_over_sum", "fanout_over_sum",
        "max_gr_overflow", "total_gr_overflow", "tool_runtime", "flow_runtime"]


def load(p):
    """Last row wins.

    The contest's scripts/parse_log.py opens the --csv target in append mode, so a
    re-parse of the same stage appends rather than replaces. Taking the first row
    silently returns a stale design (this bug reported AES numbers under the ariane
    table). The driver also removes the file before parsing; this is belt and braces.
    """
    with open(p, newline="") as fh:
        rows = [r for r in csv.DictReader(fh) if any(v not in (None, "") for v in r.values())]
    return rows[-1] if rows else {}


def num(d, k):
    v = d.get(k)
    if v in (None, "", "None"):
        return None
    try:
        return float(v)
    except ValueError:
        return None


def main():
    logs = Path(sys.argv[1])
    iters = int(sys.argv[2])
    design = sys.argv[3]

    out = []
    for k in range(iters + 1):
        p = logs / f"iter_{k}_metrics.csv"
        if not p.exists():
            print(f"WARNING: {p} missing", file=sys.stderr)
            continue
        d = load(p)
        row = {"stage": k}
        for c in COLS:
            row[c] = num(d, c)
        out.append(row)

    if not out:
        sys.exit("no stage metrics found")

    base = out[0]
    for r in out:
        if base["tns"] is not None and r["tns"] is not None:
            r["d_tns"] = round(r["tns"] - base["tns"], 6)
            r["d_tns_pct"] = (round(100.0 * (r["tns"] - base["tns"]) / abs(base["tns"]), 3)
                              if base["tns"] else None)
        else:
            r["d_tns"] = r["d_tns_pct"] = None
        r["erc_sum"] = sum(x for x in (r["slew_over_sum"], r["cap_over_sum"],
                                       r["fanout_over_sum"]) if x is not None)

    with open(logs / "frontier.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(out[0].keys()))
        w.writeheader()
        w.writerows(out)
    (logs / "frontier.json").write_text(json.dumps(
        {"design": design, "stages": out}, indent=2) + "\n")

    hdr = f"{'stage':>5} {'TNS(ns)':>12} {'dTNS(ns)':>11} {'dTNS%':>8} {'slew':>10} {'cap':>10} {'fanout':>8} {'maxGRovf':>9}"
    print(f"\n=== Delta frontier: {design} ===")
    print(hdr)
    print("-" * len(hdr))
    for r in out:
        def f(v, w=10, p=4):
            return f"{v:>{w}.{p}f}" if isinstance(v, float) else f"{'-':>{w}}"
        print(f"{r['stage']:>5} {f(r['tns'],12)} "
              f"{(f'{r[chr(100)+chr(95)+chr(116)+chr(110)+chr(115)]:>11.4f}' if isinstance(r['d_tns'],float) else f'{chr(45):>11}')} "
              f"{(f'{r[chr(100)+chr(95)+chr(116)+chr(110)+chr(115)+chr(95)+chr(112)+chr(99)+chr(116)]:>8.3f}' if isinstance(r['d_tns_pct'],float) else f'{chr(45):>8}')} "
              f"{f(r['slew_over_sum'])} {f(r['cap_over_sum'])} {f(r['fanout_over_sum'],8)} {f(r['total_gr_overflow'],9)}")

    print("\nReading: stage 0 = published OR Resizer; stage k = after k ERC-repair passes.")
    print("Delta = TNS(stage k) - TNS(stage 0).  ERC = slew+cap+fanout violation sums.")
    print("Gate A (dominating): ERC(0 violations) reached while |dTNS| stays small.")
    print("Gate B (wall): the ERC-repair cost exceeds 15% of |TNS| -> the trade-off is real.")


if __name__ == "__main__":
    main()
