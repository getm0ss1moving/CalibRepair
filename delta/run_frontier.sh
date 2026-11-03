#!/bin/bash
# =============================================================================
# ISPD 2026 Delta experiment driver.  Run on the host that has ispd26.sif (or wherever ispd26.sif is).
#
#   run_frontier.sh <design> <bench_unit> [erc_iters] [margin]
#   e.g.  run_frontier.sh aes_cipher_top TCP_250_UTIL_0.40 3 0
#
# Phase 1  frontier.tcl    published resizer, then K passes of ERC repair;
#                          snapshots each stage into Benchmarks/<design>/iter_<k>/
# Phase 2  evaluation.tcl  the *official* evaluator, once per stage
# Phase 3  parse           per-stage metrics.csv + the merged Delta frontier
#
# NOTE FOLDER_NAME is the *benchmark unit* name, not an output directory: the
# contest's design_setup.tcl builds every input path as
#     ${top_proj_dir}/Benchmarks/${design_name}/${folder}/
# so phase 1 must use the real unit (TCP_250_UTIL_0.40) while the snapshots live
# in iter_<k>/ units that phase 2 evaluates by name.
# =============================================================================
set -euo pipefail

SIF=${SIF:-/dev/shm/ispd26.sif}
WORK=${WORK:-$HOME/calibrepair}
REPO="$WORK/upstream"
DESIGN=${1:-aes_cipher_top}
UNIT=${2:-}
ITERS=${3:-3}
MARGIN=${4:-0}

if [ -z "$UNIT" ]; then
  UNIT=$(basename "$(ls -d "$REPO"/Benchmarks/"$DESIGN"/*/ | head -1)")
fi
# Per-design artifact directory: two designs sharing $LOGS clobber each other's
# iter_<k>_metrics.csv, which is how an AES row ended up under an ariane table.
LOGS="$WORK/logs/$DESIGN"
mkdir -p "$LOGS"

RUN() { singularity exec --bind "$REPO:/ISPD26-Contest" "$SIF" bash -c "$1"; }

echo "### design=$DESIGN bench_unit=$UNIT iters=$ITERS margin=$MARGIN"

# ---------------------------------------------------------------- phase 1 ----
echo "### phase 1: frontier (resizer + ERC repair)"
RUN "
set -e
export TOP_PROJ_DIR=/ISPD26-Contest
export PROJ_DIR=\$TOP_PROJ_DIR/scripts
export DESIGN_NAME=$DESIGN
export FOLDER_NAME=$UNIT
export ERC_ITERS=$ITERS
export ERC_MARGIN=$MARGIN
export BENCH_SDC=/ISPD26-Contest/Benchmarks/$DESIGN/$UNIT/contest.sdc
cd \$PROJ_DIR/$DESIGN
/OpenROAD/build/bin/openroad -exit /ISPD26-Contest/delta/frontier.tcl
" > "$LOGS/frontier.log" 2>&1 || { echo "frontier FAILED"; tail -40 "$LOGS/frontier.log"; exit 1; }
echo "snapshots: $(grep -c '^SNAPSHOT' "$LOGS/frontier.log" || true)"

# ---------------------------------------------------------------- phase 2 ----
echo "### phase 2: official evaluation per stage"
for k in $(seq 0 "$ITERS"); do
  [ -d "$REPO/Benchmarks/$DESIGN/iter_$k" ] || { echo "--- iter_$k missing, skip"; continue; }
  echo "--- iter_$k ---"
  RUN "
export TOP_PROJ_DIR=/ISPD26-Contest
export PROJ_DIR=\$TOP_PROJ_DIR/scripts
export DESIGN_NAME=$DESIGN
export FOLDER_NAME=iter_$k
export CONGESTION_REPORT=$LOGS/congestion_iter_$k.rpt
cd \$PROJ_DIR/$DESIGN
/OpenROAD/build/bin/openroad -exit \$PROJ_DIR/evaluation.tcl
" > "$LOGS/eval_iter_$k.log" 2>&1 || echo "  (evaluation.tcl returned non-zero for iter_$k)"
done

# ---------------------------------------------------------------- phase 3 ----
echo "### phase 3: parse"
for k in $(seq 0 "$ITERS"); do
  L="$LOGS/eval_iter_$k.log"
  [ -s "$L" ] || continue
  # scripts/parse_log.py opens --csv in append mode: clear it or a previous design's
  # row survives and gets picked up by collect.py.
  rm -f "$LOGS/iter_${k}_metrics.csv"
  python3 "$REPO/scripts/parse_log.py" "$L" --csv "$LOGS/iter_${k}_metrics.csv" >/dev/null
done

python3 "$REPO/delta/collect.py" "$LOGS" "$ITERS" "$DESIGN" | tee "$LOGS/frontier_table.txt"
echo "### done; artifacts in $LOGS"
