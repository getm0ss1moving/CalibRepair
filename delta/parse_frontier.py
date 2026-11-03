#!/usr/bin/env python3
"""Parse a frontier.tcl log into one row per stage.

Mirrors the contest's own scripts/parse_log.py violation logic (over = value - limit,
summed only over rows flagged "(VIOLATED)"), but keeps the numbers separated per stage
so that stage 0 (resizer) and stages 1..K (ERC repair) can be compared.

Usage: parse_frontier.py <frontier.log> [--csv out.csv]
"""
import csv
import json
import re
import sys
from pathlib import Path

FLOAT = r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?"
ANSI = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")


def last_floats(line, n):
    vals = re.findall(FLOAT, line)
    if len(vals) < n:
        return None
    try:
        return [float(v) for v in vals[-n:]]
    except ValueError:
        return None


def parse(log_path):
    stages = {}
    cur = None
    section = None
    in_table = False

    def stage(k, tag):
        if k not in stages:
            stages[k] = {
                "stage": k, "tag": tag, "tns_ns": None, "wns_ns": None,
                "slew_over_sum": 0.0, "slew_over_count": 0,
                "cap_over_sum": 0.0, "cap_over_count": 0,
                "fanout_over_sum": 0.0, "fanout_over_count": 0,
            }
        return stages[k]

    for raw in Path(log_path).read_text(encoding="utf-8", errors="ignore").splitlines():
        line = ANSI.sub("", raw).rstrip()
        s = line.strip()

        m = re.match(r"^=====\s*STAGE\s+(\d+)\s+(\S+)\s*=====$", s)
        if m:
            cur = stage(int(m.group(1)), m.group(2))
            section, in_table = None, False
            continue
        if re.match(r"^=====\s*END STAGE\s+\d+\s*=====$", s):
            section, in_table = None, False
            cur = None
            continue
        if cur is None:
            continue

        m = re.match(rf"^STAGE_FIELD\s+\d+\s+(\w+)\s+({FLOAT})\s*$", s)
        if m:
            key = m.group(1)
            if key in ("tns_ns", "wns_ns"):
                cur[key] = float(m.group(2))
            continue

        # the contest's own format: "tns max <float>" / "wns max <float>"
        m = re.match(rf"^tns\s+max\s+({FLOAT})\s*$", s, re.I)
        if m:
            cur["tns_ns"] = float(m.group(1))
            continue
        m = re.match(rf"^wns\s+max\s+({FLOAT})\s*$", s, re.I)
        if m:
            cur["wns_ns"] = float(m.group(1))
            continue

        if s.lower() in ("--- slew ---", "--- cap ---", "--- fanout ---"):
            section = s.strip("- ").strip()
            section = {"slew": "slew", "cap": "cap", "fanout": "fanout"}[section]
            in_table = False
            continue
        # the OpenROAD report header is the real section marker
        if re.match(r"^max\s+slew$", s, re.I):
            section, in_table = "slew", False
            continue
        if re.match(r"^max\s+capacitance$", s, re.I):
            section, in_table = "cap", False
            continue
        if re.match(r"^max\s+fanout$", s, re.I):
            section, in_table = "fanout", False
            continue

        if section and (s.lower().startswith("pin ") or s.lower() == "pin"):
            in_table = True
            continue
        if section and in_table and s == "":
            section, in_table = None, False
            continue
        if section and in_table and "(VIOLATED)" in line:
            v = last_floats(line, 3)
            if v:
                limit, value, _slack = v
                over = value - limit
                if over > 0:
                    cur[f"{section}_over_sum"] += over
                    cur[f"{section}_over_count"] += 1

    return [stages[k] for k in sorted(stages)]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    log = sys.argv[1]
    rows = parse(log)
    base = rows[0] if rows else None
    for r in rows:
        r["d_tns_ns"] = None if not base or base["tns_ns"] is None or r["tns_ns"] is None \
            else round(r["tns_ns"] - base["tns_ns"], 6)
        r["erc_over_sum"] = round(
            r["slew_over_sum"] + r["cap_over_sum"] + r["fanout_over_sum"], 6)
    print(json.dumps(rows, indent=2))
    if "--csv" in sys.argv:
        out = sys.argv[sys.argv.index("--csv") + 1]
        with open(out, "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
        print(f"wrote {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
