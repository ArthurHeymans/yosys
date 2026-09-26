set -e
for family in gw1n gw2a gw5a; do
	define=""
	if [ "$family" = gw5a ]; then define="-DGOWIN_GW5A"; fi
	${YOSYS} -qp "synth_gowin -family $family -nolutram -top bram; rename -top bram_uut" -o bram_uut.v bram.v
	iverilog $define -o test_bram bram_tb.v bram_uut.v bram.v ../../../techlibs/gowin/cells_sim.v
	vvp -N ./test_bram | tee test_bram.log
	grep -q "All tests passed" test_bram.log
	iverilog $define -s positional_bram_tb -o test_bram_ports bram_ports_tb.v ../../../techlibs/gowin/cells_sim.v
	vvp -N ./test_bram_ports | tee test_bram_ports.log
	grep -q "All tests passed" test_bram_ports.log
	iverilog $define -s bram_controls_tb -o test_bram_ports bram_controls_tb.v ../../../techlibs/gowin/cells_sim.v
	vvp -N ./test_bram_ports
done
