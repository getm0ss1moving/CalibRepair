#!/bin/bash
# =============================================================================
# EQR driver — build the arm chain, then score every arm with the OFFICIAL
# evaluator.  Run on the host that has ispd26.sif (or wherever ispd26.sif lives).
#
#   run_eqr.sh <design> <bench_unit> "<arm spec>"
#
# arm spec is a comma-separated list:
#   base                     the published flow
#   push:N                   published flow + N extra setup passes
#   restore:N:FROM_LABEL     fresh process; alternate repair_design/repair_timing
#                            N times under library limits, starting from FROM_LABEL
#
# example:
#   run_eqr.sh ariane TCP_900_UTIL_0.30 "base,push:1,push:2,push:3,restore:2:eqr_push3"
#
# Every arm snapshots into Benchmarks/<design>/<label>/, which is exactly where
# design_setup.tcl looks when FOLDER_NAME=<label>, so evaluation.tcl scores it
# unmodified.  Artifacts: $WORK/logs/<design>/eqr/
# =============================================================================
set -euo pipefail

SIF=${SIF:-/dev/shm/ispd26.sif}
WORK=${WORK:-$HOME/calibrepair}
REPO="$WORK/upstream"
DESIGN=${1:?design}
UNIT=${2:?bench_unit}
SPEC=${3:?arm spec}

LOGS="$WORK/logs/$DESIGN/eqr"
mkdir -p "$LOGS"
RUN() { singularity exec --bind "$REPO:/ISPD26-Contest" "$SIF" bash -c "$1"; }
# provenance: every arm log records the hash of the frozen script that ran it
SCRIPT_MD5=$(md5sum "$REPO/delta/eqr_v4.tcl" | cut -d" " -f1)
echo "### frozen script eqr_v4.tcl md5=$SCRIPT_MD5"

echo "### EQR design=$DESIGN unit=$UNIT"
echo "### spec=$SPEC"
IFS=',' read -ra ARMS <<< "$SPEC"

# --------------------------------------------------------------- phase 1 ----
for spec in "${ARMS[@]}"; do
  kind=${spec%%:*}
  rest=${spec#*:}; [ "$rest" = "$spec" ] && rest=""
  case "$kind" in
    base)
      label=eqr_base; arm=base; push=0; restp=0; ind=""; inv=""
      ;;
    push)
      n=${rest:-1}; label="eqr_push$n"; arm=push; push=$n; restp=0; ind=""; inv=""
      ;;
    relax)
      n=${rest:-1}; label="eqr_relax$n"; arm=relax; push=$n; restp=0; ind=""; inv=""
      ;;
    power)
      n=${rest:-1}; label="eqr_power$n"; arm=power; push=$n; restp=0; ind=""; inv=""
      ;;
    full)
      n=${rest:-1}; label="eqr_full$n"; arm=full; push=$n; restp=0; ind=""; inv=""
      ;;
    restore)
      n=${rest%%:*}; from=${rest#*:}; [ "$from" = "$rest" ] && from=eqr_push1
      label="eqr_restore${n}_from_${from}"; arm=restore; push=0; restp=$n
      ind="/ISPD26-Contest/Benchmarks/$DESIGN/$from/contest.def"
      inv="/ISPD26-Contest/Benchmarks/$DESIGN/$from/contest.v"
      ;;
    *) echo "unknown arm '$spec'"; exit 2 ;;
  esac
  echo "### arm $label (arm=$arm push=$push restore=$restp)"
  RUN "
set -e
export TOP_PROJ_DIR=/ISPD26-Contest
export PROJ_DIR=\$TOP_PROJ_DIR/scripts
export DESIGN_NAME=$DESIGN
export FOLDER_NAME=$UNIT
export BENCH_SDC=/ISPD26-Contest/Benchmarks/$DESIGN/$UNIT/contest.sdc
export ARM=$arm
export POWER_PCT=${POWER_PCT:-100}
export EQR_SCRIPT_MD5='$SCRIPT_MD5'
export PUSH_ROUNDS=$push
export RESTORE_PASSES=$restp
export LABEL=$label
export IN_DEF=$ind
export IN_VER=$inv
cd \$PROJ_DIR/$DESIGN
/OpenROAD/build/bin/openroad -exit /ISPD26-Contest/delta/eqr_v4.tcl
" > "$LOGS/$label.log" 2>&1 || { echo "  ARM FAILED: $label"; tail -25 "$LOGS/$label.log"; continue; }
  echo "  ok: $(grep -c '^\[EQR\] SNAPSHOT' "$LOGS/$label.log" || true) snapshot(s)"
done

# --------------------------------------------------------------- phase 2 ----
echo "### phase 2: official evaluation per arm"
for spec in "${ARMS[@]}"; do
  kind=${spec%%:*}; rest=${spec#*:}; [ "$rest" = "$spec" ] && rest=""
  case "$kind" in
    base) label=eqr_base ;;
    push) n=${rest:-1}; label="eqr_push$n" ;;
    relax) n=${rest:-1}; label="eqr_relax$n" ;;
    power) n=${rest:-1}; label="eqr_power$n" ;;
    full) n=${rest:-1}; label="eqr_full$n" ;;
    restore) n=${rest%%:*}; from=${rest#*:}; [ "$from" = "$rest" ] && from=eqr_push1; label="eqr_restore${n}_from_${from}" ;;
  esac
  [ -d "$REPO/Benchmarks/$DESIGN/$label" ] || { echo "--- $label missing, skip"; continue; }
  echo "--- eval $label"
  RUN "
export TOP_PROJ_DIR=/ISPD26-Contest
export PROJ_DIR=\$TOP_PROJ_DIR/scripts
export DESIGN_NAME=$DESIGN
export FOLDER_NAME=$label
export CONGESTION_REPORT=$LOGS/congestion_$label.rpt
cd \$PROJ_DIR/$DESIGN
/OpenROAD/build/bin/openroad -exit \$PROJ_DIR/evaluation.tcl
" > "$LOGS/eval_$label.log" 2>&1 || echo "  (evaluation returned non-zero for $label)"
  L="$LOGS/eval_$label.log"
  if [ -s "$L" ]; then
    rm -f "$LOGS/${label}_metrics.csv"
    python3 "$REPO/scripts/parse_log.py" "$L" --csv "$LOGS/${label}_metrics.csv" >/dev/null 2>&1 || echo "  (parse failed for $label)"
  fi
done

# --------------------------------------------------------------- phase 3 ----
echo "### phase 3: collect"
python3 "$REPO/delta/collect_eqr.py" "$LOGS" "$DESIGN" | tee "$LOGS/eqr_table.txt"
echo "### done; artifacts in $LOGS"
