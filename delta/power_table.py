#!/usr/bin/env python3
"""Power table for EQR arms: leakage and total power from the official metrics CSVs.

Usage: power_table.py <logs_dir> [design]

scripts/parse_log.py writes power in picowatts (the log's own unit); divide by 1e9
for mW.  The organisers' workbook keeps the same picowatt convention.
"""
import csv
import glob
import os
import sys


def num(v, div=1.0):
    try:
        return float(v) / div
    except (TypeError, ValueError):
        return None


def main():
    logs = sys.argv[1]
    design = sys.argv[2] if len(sys.argv) > 2 else ""
    print("%-34s %11s %14s %13s" % ("arm", "TNS(ns)", "leakage(mW)", "total(mW)"))
    print("-" * 74)
    for p in sorted(glob.glob(os.path.join(logs, "*_metrics.csv"))):
        lab = os.path.basename(p)[:-len("_metrics.csv")]
        rows = [r for r in csv.DictReader(open(p))
                if any(v not in (None, "") for v in r.values())]
        if not rows:
            continue
        r = rows[-1]
        tns = num(r.get("tns"))
        lk = num(r.get("leakage_power"), 1e9)
        tp = num(r.get("total_power"), 1e9)
        print("%-34s %11s %14s %13s" % (
            lab,
            "%.2f" % tns if tns is not None else "-",
            "%.5f" % lk if lk is not None else "-",
            "%.3f" % tp if tp is not None else "-"))
    if design == "aes_cipher_top":
        print("\nreference: Team33 aes leakage 0.0078 mW, dynamic 51.69 mW (README)")
        print("organisers' Resizer aes leakage = 1.21E8 pW = 0.121 mW (workbook)")


if __name__ == "__main__":
    main()
