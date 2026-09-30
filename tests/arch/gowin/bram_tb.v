`timescale 1ns / 1ps

// Random reads and writes, compared cycle by cycle against the RTL. The
// two ports of a dual-port memory never access the same word at once.
module testbench;
	reg clk = 0, rst = 0, arst = 0;
	reg [3:0] we_a = 0, we_b = 0;
	reg [13:0] a = 0, b = 1;
	reg [35:0] da = 0, db = 0;
	wire [327:0] ref_q, uut_q;
	integer i, errcount = 0;

	bram ref (clk, rst, arst, we_a, we_b, a, b, da, db, ref_q);
	bram_uut uut (clk, rst, arst, we_a, we_b, a, b, da, db, uut_q);

	initial begin
		for (i = 0; i < 20000; i = i + 1) begin
			#5 clk = 1;
			#5 clk = 0;
			if (uut_q !== ref_q) begin
				if (errcount < 10)
					$display("ERROR at cycle %0d: ref %h uut %h", i, ref_q, uut_q);
				errcount = errcount + 1;
			end
			we_a = $random;
			we_b = $random;
			a = $random;
			b = {$random, ~a[0]};
			da = {$random, $random};
			db = {$random, $random};
			rst = ($random & 63) == 0;
			arst = ($random & 127) == 0;
		end
		if (errcount == 0) begin
			$display("All tests passed.");
			$finish;
		end
		$display("Caught %1d errors.", errcount);
		$stop;
	end
endmodule
