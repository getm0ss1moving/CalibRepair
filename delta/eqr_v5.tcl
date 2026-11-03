# =============================================================================
# EQR — Empty-Quadrant Reachability.
#
# The question: does a solution exist that is ERC-clean AND at winner-level TNS?
# Neither the published leaderboard nor the Resizer Delta experiment can answer it,
# because the Resizer never violates the axis that carries weight (capacitance,
# w=10) — it only ever violates slew (w=0.001). So the frontier has to be traced
# on a solution family that DOES violate it.
#
# Arms (one process each; every arm is snapshotted and scored by the official
# evaluator, scripts/evaluation.tcl, via FOLDER_NAME=<LABEL>):
#
#   base          the published flow      repair_design ; repair_timing -setup
#   push:P        base, then P extra setup passes. Each pass re-optimises timing
#                 on a design whose electrical state is already stale, which is
#                 the mechanism that lets TNS improve at the cost of ERC.
#   restore:R     a fresh process reads a pushed snapshot and alternates
#                 { repair_design ; repair_timing -setup } R times under the
#                 LIBRARY limits (fresh process => limits restored). This is the
#                 price of putting ERC back at that operating point.
#
# Reading the frontier:
#   TNS(push:P) falls as P grows.  If TNS(restore) stays close to TNS(push),
#   the quadrant is reachable for this family.  If restore gives the TNS back,
#   the trade-off is real for this family.
#
# Environment:
#   TOP_PROJ_DIR PROJ_DIR DESIGN_NAME FOLDER_NAME      (as the contest scripts)
#   BENCH_SDC   path to the benchmark .sdc (for snapshots)
#   ARM         base | push | restore
#   PUSH_ROUNDS extra setup passes after base            (push)
#   RESTORE_PASSES  {repair_design;repair_timing} rounds (restore)
#   IN_DEF IN_VER   inputs for restore (a pushed snapshot)
#   LABEL       snapshot name under Benchmarks/<design>/<LABEL>/
# =============================================================================

set top_proj_dir "$::env(TOP_PROJ_DIR)"
set proj_dir     "$::env(PROJ_DIR)"
set design_name  "$::env(DESIGN_NAME)"
# design_setup.tcl builds every input path as ${top_proj_dir}/Benchmarks/${design_name}/${folder}/
# and sources lib_setup.tcl / design_setup.tcl relative to the cwd, so BOTH
# $folder and $design_name must already exist as variables before it is sourced.
set folder       [expr {[info exists ::env(FOLDER_NAME)] ? $::env(FOLDER_NAME) : ""}]

set ARM          [expr {[info exists ::env(ARM)] ? $::env(ARM) : "base"}]
set SCRIPT_MD5   [expr {[info exists ::env(EQR_SCRIPT_MD5)] ? $::env(EQR_SCRIPT_MD5) : "UNSET"}]
puts "\[EQR\] SCRIPT_MD5=$SCRIPT_MD5"
puts "\[EQR\] EQR_SCRIPT_VERSION=$SCRIPT_MD5"
set PUSH_ROUNDS  [expr {[info exists ::env(PUSH_ROUNDS)] ? $::env(PUSH_ROUNDS) : 1}]
set POWER_PCT   [expr {[info exists ::env(POWER_PCT)] ? $::env(POWER_PCT) : 100}]
set REST_PASSES  [expr {[info exists ::env(RESTORE_PASSES)] ? $::env(RESTORE_PASSES) : 2}]
set LABEL        [expr {[info exists ::env(LABEL)] ? $::env(LABEL) : $ARM}]
set bench_root   "${top_proj_dir}/Benchmarks/${design_name}"
set out_dir      "${bench_root}/${LABEL}"

source "lib_setup.tcl"
source "design_setup.tcl"

proc is_placement_legal {} {
  if {[catch { check_placement -verbose } err]} {
    puts "check_placement reported errors: $err"
    return 0
  }
  return 1
}

proc legalize {} {
  if {![is_placement_legal]} {
    puts "\[EQR\] placement illegal; running detailed_placement"
    detailed_placement
    if {[is_placement_legal]} {
      puts "\[EQR\] placement legalized"
    } else {
      puts stderr "\[EQR\] WARN: placement still illegal"
    }
  } else {
    puts "\[EQR\] placement legal"
  }
}

# One line per field so the parser never guesses.  report_tns/report_wns emit the
# contest's own "tns max <f>" form and report_check_types the sections the contest
# parser reads, so the intermediate numbers stay comparable with the official ones.
proc stage_report {label} {
  puts "===== EQR_STAGE $label ====="
  report_tns
  report_wns
  puts "--- slew ---"
  report_check_types -max_slew        -violators
  puts "--- cap ---"
  report_check_types -max_capacitance -violators
  puts "--- fanout ---"
  report_check_types -max_fanout      -violators
  puts "===== EQR_END $label ====="
}

proc snapshot {label} {
  global out_dir design_name
  file mkdir $out_dir
  write_def     "${out_dir}/contest.def"
  write_verilog "${out_dir}/contest.v"
  if {[info exists ::env(BENCH_SDC)]} {
    file copy -force $::env(BENCH_SDC) "${out_dir}/contest.sdc"
  }
  puts "\[EQR\] SNAPSHOT ${label} -> ${out_dir}"
}

# ------------------------------------------------------------------ read -----
foreach lef_file ${lefs}    { read_lef     $lef_file }
foreach lib_file ${libbest} { read_liberty $lib_file }

if {$ARM eq "restore" && [info exists ::env(IN_DEF)] && $::env(IN_DEF) ne ""} {
  puts "\[EQR\] restore reads $::env(IN_DEF)"
  read_def     $::env(IN_DEF)
  read_verilog $::env(IN_VER)
} else {
  read_def     $def_file
  read_verilog $verilog_netlist
}
read_sdc $sdc_file
set_ideal_network [all_clocks]
source $rc_file
# estimate_parasitics -placement is NOT optional: without it repair_design and
# repair_timing optimise against a zero-wire model, the arms become degenerate
# (observed: aes base returned -68.22 ns instead of the official -19.55 ns, and
# push/restore produced no change at all).  This mirrors evaluation_baseline.tcl
# exactly, which is what makes arm 'base' a reproduction of the published Resizer.
estimate_parasitics -placement
set_cmd_units -time ns -capacitance pF -current mA -voltage V -resistance kOhm -distance um
set_units -power mW

# ------------------------------------------------------------------ arms -----
set t0 [clock seconds]
puts "\[EQR\] ARM=$ARM LABEL=$LABEL design=$design_name"

if {$ARM eq "base"} {
  repair_design
  repair_timing -setup -skip_gate_cloning -skip_pin_swap

} elseif {$ARM eq "push"} {
  repair_design
  repair_timing -setup -skip_gate_cloning -skip_pin_swap
  for {set r 1} {$r <= $PUSH_ROUNDS} {incr r} {
    set ts [clock seconds]
    puts "\[EQR\] push round $r"
    repair_timing -setup -skip_gate_cloning -skip_pin_swap
    puts "\[EQR\] push round $r took [expr {[clock seconds] - $ts}] s"
  }

} elseif {$ARM eq "relax"} {
  # Published base first, so the arm differs from 'base' only in the push phase.
  repair_design
  repair_timing -setup -skip_gate_cloning -skip_pin_swap
  # Relax the electrical rules to effectively disable them, then push setup again.
  # This is the direct test of "what does ERC freedom buy": repair_timing now has
  # no reason to spend effort on slew/cap/fanout, so whatever TNS it gains is
  # bought with violations the official evaluator will still count.
  set rt 100.0
  set rc 100.0
  set rf 1000.0
  if {[info exists ::env(RELAX_TRANS)] && $::env(RELAX_TRANS) ne ""} { set rt $::env(RELAX_TRANS) }
  if {[info exists ::env(RELAX_CAP)]   && $::env(RELAX_CAP)   ne ""} { set rc $::env(RELAX_CAP) }
  if {[info exists ::env(RELAX_FAN)]   && $::env(RELAX_FAN)   ne ""} { set rf $::env(RELAX_FAN) }
  # Guarded: a missing or renamed command must fail loudly here, not silently
  # leave the limits in place and produce a fake "the lever does nothing" result.
  # NOTE set_max_* take TWO positional arguments (value AND objects) in this
  # OpenROAD (STA-0567 otherwise), and a bare value silently does nothing.
  if {[catch {set_max_transition  $rt [current_design]} e]} { puts stderr "\[EQR\] set_max_transition failed: $e"; exit 4 }
  if {[catch {set_max_capacitance $rc [current_design]} e]} { puts stderr "\[EQR\] set_max_capacitance failed: $e"; exit 4 }
  if {[catch {set_max_fanout      $rf [current_design]} e]} { puts stderr "\[EQR\] set_max_fanout failed: $e"; exit 4 }
  puts "\[EQR\] relaxed limits: trans=$rt cap=$rc fan=$rf"
  for {set r 1} {$r <= $PUSH_ROUNDS} {incr r} {
    set ts [clock seconds]
    puts "\[EQR\] relax push round $r"
    repair_timing -setup -skip_gate_cloning -skip_pin_swap
    puts "\[EQR\] relax push round $r took [expr {[clock seconds] - $ts}] s"
  }

} elseif {$ARM eq "power"} {
  # The published reference never calls recover_power (0 occurrences in
  # evaluation_baseline.tcl and evaluation.tcl), yet the winner's advantage over
  # the Resizer is 56 % leakage power.  This arm tests whether that is simply an
  # unused standard move: published base, then power recovery, then re-fix timing.
  repair_design
  repair_timing -setup -skip_gate_cloning -skip_pin_swap
  for {set r 1} {$r <= $PUSH_ROUNDS} {incr r} {
    puts "\[EQR\] power arm: setup pass $r"
    repair_timing -setup -skip_gate_cloning -skip_pin_swap
  }
  puts "\[EQR\] power arm: repair_timing -recover_power $POWER_PCT"
  repair_timing -recover_power $POWER_PCT
  puts "\[EQR\] power arm: re-fix setup after power recovery"
  repair_timing -setup -skip_gate_cloning -skip_pin_swap

} elseif {$ARM eq "full"} {
  # Everything the reference script explicitly disables, plus power recovery:
  # the published flow passes -skip_gate_cloning -skip_pin_swap, so gate cloning
  # and pin swapping are never used in the reference numbers.
  repair_design
  repair_timing -setup
  repair_timing -recover_power $POWER_PCT
  for {set r 1} {$r <= $PUSH_ROUNDS} {incr r} {
    puts "\[EQR\] full arm: setup pass $r"
    repair_timing -setup
  }

} elseif {$ARM eq "loop"} {
  # M1 minimal core: close the loop on the SCORING extraction.
  #
  # The published flow repairs electrical rules against PLACEMENT parasitics, while
  # the official evaluator scores against GLOBAL-ROUTING parasitics.  That is why
  # ERC repair plateaus (ariane: slew 154.48 -> 132.15 and stops).  This arm
  # re-routes, re-extracts and repairs again, PUSH_ROUNDS times, so the constraint
  # becomes visible to the optimiser.  If ERC can be driven to zero this way while
  # TNS holds, then "close the loop on the scoring extraction" is the minimal
  # mechanism the paper needs; if it cannot, the objective/constraint conflict is real.
  repair_design
  repair_timing -setup -skip_gate_cloning -skip_pin_swap
  if {[info exists route_signal_layers]} { set sig_layers $route_signal_layers } else { set sig_layers "M2-M9" }
  if {[info exists route_clock_layers]}  { set clk_layers $route_clock_layers }  else { set clk_layers "M2-M9" }
  set_routing_layers -signal $sig_layers -clock $clk_layers
  for {set r 1} {$r <= $PUSH_ROUNDS} {incr r} {
    set ts [clock seconds]
    puts "\[EQR\] loop round $r: legalize -> global_route -> estimate_parasitics -global_routing -> repair"
    if {![is_placement_legal]} { detailed_placement }
    if {[catch {global_route -skip_large_fanout_nets 300 -allow_congestion} e]} {
      puts "\[EQR\] global_route failed in round $r: $e -- legalizing and retrying"
      detailed_placement
      global_route -skip_large_fanout_nets 300 -allow_congestion
    }
    estimate_parasitics -global_routing
    repair_design
    repair_timing -setup -skip_gate_cloning -skip_pin_swap
    puts "\[EQR\] loop round $r took [expr {[clock seconds] - $ts}] s"
  }
  # After the loop the active parasitics ARE the global-routing ones, i.e. the same
  # model the evaluator scores on -- so this arm's stage report is directly
  # comparable to the official numbers, unlike the other arms.
  puts "\[EQR\] parasitics=global_routing (this arm reports on the scoring model)"

} elseif {$ARM eq "restore"} {
  for {set p 1} {$p <= $REST_PASSES} {incr p} {
    set ts [clock seconds]
    puts "\[EQR\] restore pass $p (library limits active)"
    repair_design
    repair_timing -setup -skip_gate_cloning -skip_pin_swap
    puts "\[EQR\] restore pass $p took [expr {[clock seconds] - $ts}] s"
  }
} else {
  puts stderr "\[EQR\] unknown ARM=$ARM"
  exit 3
}

legalize
puts "\[EQR\] arm wall time [expr {[clock seconds] - $t0}] s"

stage_report $LABEL
snapshot $LABEL
puts "EQR_DONE $LABEL"
