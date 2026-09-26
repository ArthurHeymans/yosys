set -e
iverilog -s iobuf_tb -o test_bidir iobuf_tb.v ../../../techlibs/gowin/cells_sim.v
vvp -N ./test_bidir
${YOSYS} -qp "synth_gowin -top bidir; rename -top bidir_uut" -o bidir_uut.v bidir.v
iverilog -o test_bidir bidir_tb.v bidir_uut.v bidir.v ../../../techlibs/gowin/cells_sim.v
vvp -N ./test_bidir | tee test_bidir.log
grep -q "All tests passed" test_bidir.log
