SHELL=/bin/bash -o pipefail
.SHELLFLAGS += -e

PKG_SRCS  := $(PWD)/../pkg/types.sv
HDL_SRCS  := $(shell find $(PWD)/../hdl -name '*.sv')
COMM_HVL  := $(shell find $(PWD)/../hvl/common                -name '*.sv' -o -name '*.v' -o -name '*.o' -o -name '*.so')
VCS_HVL   := $(COMM_HVL) $(shell find $(PWD)/../hvl/vcs       -name '*.sv' -o -name '*.v' -o -name '*.o' -o -name '*.so')
VER_HVL   := $(COMM_HVL) $(shell find $(PWD)/../hvl/verilator -name '*.sv' -o -name '*.v' -o -name '*.o' -o -name '*.so' -o -name '*.cpp')
SRAM_SRCS := $(shell find $(PWD)/../sram/output -name '*.v')
HDRS      := $(shell find $(PWD)/../hvl -name '*.svh') $(PWD)/../hvl/common/rvfi_reference.json
DW_IP     := $(shell python3 $(PWD)/../bin/get_options.py dw_ip)
VCS_SRCS  := $(PKG_SRCS) $(HDL_SRCS) $(VCS_HVL) $(SRAM_SRCS) $(DW_IP)
VER_SRCS  := $(PKG_SRCS) $(HDL_SRCS) $(VER_HVL) $(SRAM_SRCS) $(DW_IP)

TIMEOUT   ?= 10000000

ECE411_NO_FLOAT = $(shell python3 $(PWD)/../bin/get_options.py no_float)

export VCS_ARCH_OVERRIDE=linux
COMMON_FLAGS = +incdir+$(PWD)/../hvl/common  $(ECE411_NO_FLOAT) +define+DW_SUPPRESS_WARN +incdir+$(DW)/sim_ver
VCS_FLAGS    = $(COMMON_FLAGS) +incdir+$(PWD)/../hvl/vcs -licqueue -full64 -lca -sverilog -timescale=1ps/1ps -debug_acc+all -kdb -suppress=LCA_FEATURES_ENABLED -msg_config=../vcs_warn.config -xprop=../xprop.config -xprop=flowctrl -assert svaext
VER_FLAGS    = $(COMMON_FLAGS) +incdir+$(PWD)/../hvl/verilator -Wall --timescale 1ps/1ps -Mdir build -O3 -CFLAGS "-Ofast -march=native" --x-assign fast --x-initial fast --noassert --cc --exe ../verilator_warn.vlt --trace-fst --trace-structs --trace-max-array 1048576 --trace-max-width 1048576 +define+ECE411_VERILATOR

vcs/top_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 8 $(ECE411_NO_FLOAT)
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top top_tb -o top_tb
	bash check_compile_error.sh

.PHONY: run_vcs_top_tb
run_vcs_top_tb: vcs/top_tb $(PROG)
	mkdir -p spike
	python3 ../bin/generate_memory_file.py -32 $(PROG)
	rm -f vcs/dump.fsdb
	python3 $(PWD)/../bin/get_options.py clock
	python3 $(PWD)/../bin/get_options.py bmem_x
	cd vcs && ./top_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(PWD)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(PWD)/bin/memory_32.lst" \
		+ELF_ECE411="$(PWD)/bin/spike_dpi.elf"

verilator/build/Vtop_tb: $(VER_SRCS) $(HDRS)
	mkdir -p verilator/build
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 8 $(ECE411_NO_FLOAT)
	cd verilator ;\
	verilator $(VER_FLAGS) $(VER_SRCS) --top-module top_tb |& tee build/compile.log
	cd verilator/build ;\
	$(MAKE) --jobs=$(shell echo $(shell nproc)-2 | bc) -f Vtop_tb.mk |& tee -a compile.log

.PHONY: run_verilator_top_tb
run_verilator_top_tb: verilator/build/Vtop_tb $(PROG)
	mkdir -p spike
	find ./verilator -maxdepth 1 -type f -delete
	python3 ../bin/generate_memory_file.py -32 $(PROG)
	python3 $(PWD)/../bin/get_options.py clock
	python3 $(PWD)/../bin/get_options.py bmem_x
	cd verilator && ./build/Vtop_tb \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(PWD)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(PWD)/bin/memory_32.lst" \
		+ELF_ECE411="$(PWD)/bin/spike_dpi.elf" \
		|& tee simulation.log

.PHONY: covrep
covrep: vcs/top_tb.vdb
	cd vcs && urg -dir top_tb.vdb

.PHONY: verdi
verdi:
	mkdir -p verdi
	cd verdi && timeout $(ECE411_GUI_TIMEOUT) $(VERDI_HOME)/bin/verdi -ssf $(PWD)/vcs/dump.fsdb

.PHONY: spike
spike: $(ELF)
	mkdir -p spike
	spike --isa=$(shell python3 $(PWD)/../bin/get_options.py arch) -m0xaaaaa000:0x55556000 --log-commits $(ELF) |& tail -n +6 > spike/spike.log

.PHONY: interactive_spike
interactive_spike: $(ELF)
	spike --isa=$(shell python3 $(PWD)/../bin/get_options.py arch) -m0xaaaaa000:0x55556000 --log-commits -d $(ELF)

.PHONY: clean
clean:
	rm -rf bin vcs verdi verilator spike

run_vcs_fifo:
	@mkdir -p vcs
	vcs -full64 -sverilog -timescale=1ns/1ps \
	  -debug_access+r+w-memcbk -debug_region+cell \
	  +incdir+../hdl \
	  ../hdl/fifo.sv ../hvl/vcs/fifo_tb.sv \
	  -top fifo_tb \
	  -o vcs/fifo_simv
	./vcs/fifo_simv

.PHONY: verdi_fifo
verdi_fifo:
	mkdir -p verdi
	cd verdi && $(VERDI_HOME)/bin/verdi -ssf $(PWD)/vcs/dump.fsdb

# -------------------------------------------------------------------
# Adapter testbench (read-only cacheline_adapter)
# -------------------------------------------------------------------
.PHONY: run_vcs_adapter
run_vcs_adapter:
	@mkdir -p vcs
	vcs -full64 -sverilog -timescale=1ns/1ps \
	  -debug_access+r+w -debug_region+cell +vpi \
	  +incdir+../hdl +incdir+../hvl/common \
	  ../hdl/cache_adapter.sv \
	  ../hvl/vcs/top_tb_adapter.sv \
	  -top top_tb_adapter \
	  -l vcs/adapter_compile.log \
	  -o vcs/adapter_simv
	@echo "---- Compilation done. Running simulation ----"
	cd vcs && ./adapter_simv -l adapter_sim.log \
		+TIMEOUT_ECE411=1000000 \
		+CLOCK_PERIOD_PS_ECE411=10000
	@echo "---- Simulation done. To view in Verdi, run: make verdi_adapter ----"

.PHONY: verdi_adapter
verdi_adapter:
	mkdir -p verdi
	cd verdi && $(VERDI_HOME)/bin/verdi -ssf $(PWD)/vcs/dump.fsdb

# LB testbench
.PHONY: run_vcs_lb
run_vcs_lb:
	@mkdir -p vcs
	vcs -full64 -sverilog -timescale=1ns/1ps \
	  -debug_access+r+w -debug_region+cell +vpi \
	  +incdir+../hdl +incdir+../hvl/common \
	  ../hdl/linebuffer.sv \
	  ../hvl/vcs/lb_tb.sv \
	  -top lb_tb \
	  -l vcs/lb_compile.log \
	  -o vcs/lb_simv
	@echo "---- Compilation done. Running simulation ----"
	cd vcs && ./lb_simv -l lb_sim.log \
		+TIMEOUT_ECE411=1000000 \
		+CLOCK_PERIOD_PS_ECE411=10000
	@echo "---- Simulation done. To view in Verdi, run: make verdi_lb ----"

.PHONY: verdi_lb
verdi_lb:
	mkdir -p verdi
	cd verdi && $(VERDI_HOME)/bin/verdi -ssf $(PWD)/vcs/dump.fsdb

#rob testbench
.PHONY: run_vcs_rob
run_vcs_rob:
	@mkdir -p vcs
	vcs -full64 -sverilog -timescale=1ns/1ps \
	  -debug_access+r+w -debug_region+cell +vpi \
	  +incdir+../hdl +incdir+../hvl/common \
	  ../hdl/rob_module.sv \
	  ../hvl/vcs/top_tb_rob.sv \
	  -top top_tb_rob \
	  -l vcs/rob_compile.log \
	  -o vcs/rob_simv
	@echo "---- Compilation done. Running simulation ----"
	cd vcs && ./rob_simv -l rob_sim.log \
		+TIMEOUT_ECE411=1000000 \
		+CLOCK_PERIOD_PS_ECE411=10000
	@echo "---- Simulation done. To view in Verdi, run: make verdi_rob ----"
	

.PHONY: verdi_rob
verdi_rob:
	mkdir -p verdi
	cd verdi && $${VERDI_HOME}/bin/verdi -ssf $$(pwd -P)/../vcs/dump.fsdb

run_vcs_pcsb:
	@mkdir -p vcs
	vcs -full64 -sverilog -timescale=1ns/1ps \
	  -debug_access+r+w-memcbk -debug_region+cell \
	  +incdir+../hdl \
	  ../pkg/types.sv \
	  ../hdl/pcsb.sv ../hvl/vcs/pcsb_tb.sv \
	  -top pcsb_tb \
	  -o vcs/pcsb_simv
	./vcs/pcsb_simv
