# =============================================================================
# ISPD 2026 Delta / frontier experiment.
#
# Question: what does it COST in setup TNS to make the design ERC-clean?
#
#   stage iter_0 : the published OpenROAD Resizer flow
#                  (repair_design ; repair_timing -setup -skip_gate_cloning -skip_pin_swap)
#   stage iter_k : iter_0 followed by k passes of repair_design (the ERC-repair pass)
#
# Each stage is snapshotted into
#     $TOP_PROJ_DIR/Benchmarks/$DESIGN/iter_$k/{contest.def,contest.v,contest.sdc}
# so that the *official* evaluator (scripts/evaluation.tcl) can score each stage by
# setting FOLDER_NAME=iter_$k, with no edit to design_setup.tcl at all.
#
# Environment:
#   TOP_PROJ_DIR, PROJ_DIR, DESIGN_NAME, FOLDER_NAME, CONGESTION_REPORT  (as eval.sh)
#   ERC_ITERS   number of ERC-repair passes after the resizer   (default 3)
#   ERC_MARGIN  slew/cap margin passed to repair_design, percent (default 0)
#
# Run from $PROJ_DIR/$DESIGN_NAME (lib_setup.tcl / design_setup.tcl are sourced
# relative to the cwd, exactly as the contest's own scripts do).
# =============================================================================

set top_proj_dir "$::env(TOP_PROJ_DIR)"
set proj_dir     "$::env(PROJ_DIR)"
set design_name  "$::env(DESIGN_NAME)"
set crfile       [expr {[info exists ::env(CONGESTION_REPORT)] ? $::env(CONGESTION_REPORT) : ""}]
set folder       "$::env(FOLDER_NAME)"

set K        [expr {[info exists ::env(ERC_ITERS)]  ? $::env(ERC_ITERS)  : 3}]
set margin   [expr {[info exists ::env(ERC_MARGIN)] ? $::env(ERC_MARGIN) : 0}]
set tag0     [expr {[info exists ::env(ERC_SKIP_INITIAL)] && $::env(ERC_SKIP_INITIAL) ? "tns_only" : "resizer"}]

set lib_setup_file    "lib_setup.tcl"
set design_setup_file "design_setup.tcl"
set bench_root "${top_proj_dir}/Benchmarks/${design_name}"

set start [clock seconds]
source $lib_setup_file
source $design_setup_file

# ---------------------------------------------------------------- helpers ----
proc is_placement_legal {} {
  if {[catch { check_placement -verbose } err]} {
    puts "check_placement reported errors: $err"
    return 0
  }
  return 1
}

# Machine-readable stage report. Everything a parser needs, one line per field,
# interleaved with the standard OpenROAD reports so the numbers stay auditable.
proc stage_report {k tag} {
  puts "===== STAGE $k $tag ====="
  # report_tns / report_wns emit "tns max <float>" / "wns max <float>", the exact
  # format the contest's own scripts/parse_log.py matches -- so the intermediate
  # numbers here are read by the same parser as the official ones.
  report_tns
  report_wns
  puts "--- slew ---"
  report_check_types -max_slew        -violators
  puts "--- cap ---"
  report_check_types -max_capacitance -violators
  puts "--- fanout ---"
  report_check_types -max_fanout      -violators
  puts "===== END STAGE $k ====="
}

# Snapshot a stage where the official evaluator will find it.
proc snapshot {k} {
  global bench_root design_name
  set d "${bench_root}/iter_${k}"
  file mkdir $d
  write_def     "${d}/contest.def"
  write_verilog "${d}/contest.v"
  if {![file exists "${d}/contest.sdc"]} {
    file copy -force "$::env(BENCH_SDC)" "${d}/contest.sdc"
  }
  puts "SNAPSHOT iter_${k} -> ${d}"
}

# ------------------------------------------------------------------ flow -----
foreach lef_file ${lefs}    { read_lef     $lef_file }
foreach lib_file ${libbest} { read_liberty $lib_file }

read_def      $def_file
read_verilog  $verilog_netlist
read_sdc      $sdc_file
set_ideal_network [all_clocks]

source $rc_file
set_cmd_units -time ns -capacitance pF -current mA -voltage V -resistance kOhm -distance um
set_units -power mW
estimate_parasitics -placement

# ---- stage 0: the published resizer flow -----------------------------------
# ERC_SKIP_INITIAL=1 drops the published flow's leading repair_design, i.e. it
# removes the ERC repair entirely and lets repair_timing optimise setup alone.
# That is the mirror of the Delta measurement: not "what does enforcing ERC cost"
# but "what does ERC freedom buy". If cap/slew violations appear and TNS improves,
# the resulting point is a cap-dirty high-TNS solution whose repair cost can then
# be measured against stage 0.
set skip_initial [expr {[info exists ::env(ERC_SKIP_INITIAL)] ? $::env(ERC_SKIP_INITIAL) : 0}]

set start_rsz [clock seconds]
puts "\[INFO\] Start OpenROAD RSZ ... (skip_initial_erc=$skip_initial)"
if {!$skip_initial} {
  repair_design
} else {
  puts "\[INFO\] ERC_SKIP_INITIAL=1: published leading repair_design omitted"
}
repair_timing -setup -skip_gate_cloning -skip_pin_swap
puts "\[INFO\] OR RSZ runtime: [expr {[clock seconds] - $start_rsz}] second"

# The published flow legalizes before it writes _baseline.def, and the official
# evaluator exits unless check_placement passes -- so stage 0 must be legalized
# here too, or iter_0 cannot be scored at all.
if {![is_placement_legal]} {
  puts "\[INFO\] stage 0 placement illegal after RSZ; running detailed_placement"
  detailed_placement
  if {[is_placement_legal]} {
    puts "\[INFO\] stage 0 placement legalized"
  } else {
    puts stderr "WARN: stage 0 placement still illegal after detailed_placement"
  }
}

stage_report 0 $tag0
snapshot 0

# ---- stages 1..K: ERC repair ------------------------------------------------
for {set k 1} {$k <= $K} {incr k} {
  set t0 [clock seconds]
  if {$margin > 0} {
    repair_design -slew_margin $margin -cap_margin $margin
  } else {
    repair_design
  }
  detailed_placement
  puts "\[INFO\] ERC repair pass $k runtime: [expr {[clock seconds] - $t0}] second"
  stage_report $k erc_repair
  snapshot $k
}

puts "\[INFO\] frontier flow wall time: [expr {[clock seconds] - $start}] second"
puts "FRONTIER_DONE"
