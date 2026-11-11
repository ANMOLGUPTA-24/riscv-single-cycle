#==============================================================================
# Makefile - single-cycle RV32I processor
#------------------------------------------------------------------------------
#   make                 assemble every program, run every test, report
#   make modules         run only the per-module testbenches
#   make programs        assemble every program (.hex + .data.hex + .lst)
#   make run PROG=fib    run one program on the RTL
#   make trace PROG=gcd  same, printing every instruction as it retires
#   make wave PROG=fib   open the waveform in GTKWave
#   make coverage        which instructions the test programs actually execute
#   make lint            structural checks with Verilator / iverilog
#   make synth           synthesise the core with Yosys and report area
#   make clean
#==============================================================================

IVERILOG  := iverilog
VVP       := vvp
YOSYS     := yosys
PYTHON    := python3
IVFLAGS   := -g2005 -Wall -I src

SRC       := $(wildcard src/*.v)
CORE_SRC  := $(filter-out src/riscv_top.v,$(SRC))
BUILD     := build

# per-module tests: name -> module(s) under test
MODULE_TESTS := alu imm_gen reg_file branch_unit control_unit lsu pc data_mem
DEPS_alu           := src/alu.v
DEPS_imm_gen       := src/imm_gen.v
DEPS_reg_file      := src/reg_file.v
DEPS_branch_unit   := src/branch_unit.v
DEPS_control_unit  := src/control_unit.v src/alu_control.v
DEPS_lsu           := src/lsu.v
DEPS_pc            := src/pc.v
DEPS_data_mem      := src/data_mem.v

PROGRAMS  := test_alu test_mem test_branch test_jump fib bubble_sort gcd
PROG      ?= fib
EXPECT_WORDS ?= 32

.PHONY: all modules programs run trace wave lint synth coverage clean help

all: modules programs top coverage
	@echo ""
	@echo "================ all tests complete ================"

#------------------------------------------------------------------ module TBs -
modules: $(addprefix module-,$(MODULE_TESTS))

module-%: tb/tb_%.v | $(BUILD)
	@$(IVERILOG) $(IVFLAGS) -o $(BUILD)/tb_$*.out tb/tb_$*.v $(DEPS_$*)
	@$(VVP) $(BUILD)/tb_$*.out | grep -v '^VCD info'

#-------------------------------------------------------------------- programs --
programs: $(addprefix $(BUILD)/,$(addsuffix .hex,$(PROGRAMS)))

$(BUILD)/%.hex: programs/%.s tools/asm.py | $(BUILD)
	@$(PYTHON) tools/asm.py $< -o $(BUILD)/$*
	@$(PYTHON) tools/iss.py $(BUILD)/$* --expect-words $(EXPECT_WORDS)

#---------------------------------------------------- whole-processor test runs -
top: $(addprefix run-,$(PROGRAMS))

run-%: $(BUILD)/%.hex $(SRC) tb/tb_riscv_top.v | $(BUILD)
	@$(IVERILOG) $(IVFLAGS) -o $(BUILD)/top_$*.out \
	  -Ptb_riscv_top.PROG_NAME=\"$*\" \
	  -Ptb_riscv_top.IMEM_FILE=\"$(BUILD)/$*.hex\" \
	  -Ptb_riscv_top.DMEM_FILE=\"$(BUILD)/$*.data.hex\" \
	  -Ptb_riscv_top.REXP_FILE=\"$(BUILD)/$*.rexp\" \
	  -Ptb_riscv_top.MEXP_FILE=\"$(BUILD)/$*.mexp\" \
	  -Ptb_riscv_top.EXPECT_WORDS=$(EXPECT_WORDS) \
	  -Ptb_riscv_top.VCD_FILE=\"$(BUILD)/$*.vcd\" \
	  tb/tb_riscv_top.v $(SRC)
	@$(VVP) $(BUILD)/top_$*.out | grep -v -e '^VCD info' -e 'Not enough words'

run: run-$(PROG)

trace: $(BUILD)/$(PROG).hex $(SRC) tb/tb_riscv_top.v | $(BUILD)
	@$(IVERILOG) $(IVFLAGS) -o $(BUILD)/trace_$(PROG).out \
	  -Ptb_riscv_top.PROG_NAME=\"$(PROG)\" \
	  -Ptb_riscv_top.IMEM_FILE=\"$(BUILD)/$(PROG).hex\" \
	  -Ptb_riscv_top.DMEM_FILE=\"$(BUILD)/$(PROG).data.hex\" \
	  -Ptb_riscv_top.REXP_FILE=\"$(BUILD)/$(PROG).rexp\" \
	  -Ptb_riscv_top.MEXP_FILE=\"$(BUILD)/$(PROG).mexp\" \
	  -Ptb_riscv_top.TRACE=1 \
	  -Ptb_riscv_top.VCD_FILE=\"$(BUILD)/$(PROG).vcd\" \
	  tb/tb_riscv_top.v $(SRC)
	@$(VVP) $(BUILD)/trace_$(PROG).out | grep -v -e '^VCD info' -e 'Not enough words'

#------------------------------------------------------------------- waveforms --
wave: run-$(PROG)
	gtkwave $(BUILD)/$(PROG).vcd &

#------------------------------------------------------------------------ lint --
lint:
	@echo "--- iverilog strict elaboration ---"
	@$(IVERILOG) -g2005 -Wall -Wno-timescale -I src -o /dev/null -s riscv_top $(SRC) \
	  && echo "iverilog: clean"
	@if command -v verilator >/dev/null 2>&1; then \
	  echo "--- verilator lint ---"; \
	  verilator --lint-only -Wall -Isrc --top-module riscv_core $(CORE_SRC) \
	    && echo "verilator: clean"; \
	else \
	  echo "verilator not installed - skipped"; \
	fi

#--------------------------------------------------------------------- coverage -
coverage: programs
	@echo ""
	@$(PYTHON) tools/coverage.py $(addprefix $(BUILD)/,$(PROGRAMS))

#--------------------------------------------------------------------- synthesis -
synth: | $(BUILD)
	@$(YOSYS) -q -s synth/synth.ys
	@echo "netlist  -> $(BUILD)/riscv_core_netlist.v"
	@echo "report   -> $(BUILD)/synth_report.txt"

#------------------------------------------------------------------------------
$(BUILD):
	@mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)

help:
	@sed -n '2,20p' Makefile
