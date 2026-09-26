`timescale 1ns / 1ps

// Compare synthesised bidirectional pads against the RTL for every input.
// Pads the design releases are also driven from outside, to check that
// the value read back comes from the pad.
module testbench;
	localparam S = 5, P = 5;

	reg [S-1:0] s;
	reg [P-1:0] ext_en, ext_val;
	wire [P-1:0] ref_p, uut_p, ref_q, uut_q;
	integer i, j, errcount = 0;

	genvar k;
	generate for (k = 0; k < P; k = k + 1) begin : ext
		assign ref_p[k] = ext_en[k] ? ext_val[k] : 1'bz;
		assign uut_p[k] = ext_en[k] ? ext_val[k] : 1'bz;
	end endgenerate

	bidir ref (.s(s), .p(ref_p), .q(ref_q));
	bidir_uut uut (.s(s), .p(uut_p), .q(uut_q));

	task check;
		begin
			// A floating pad read has no hardware-defined logic value.
			if (s[4] && !s[0]) ext_en[0] = 1'b1;
			#1;
			if (uut_p !== ref_p || uut_q !== ref_q) begin
				$display("ERROR: s=%b ext_en=%b ext_val=%b: p %b/%b q %b/%b (ref/uut)",
					s, ext_en, ext_val, ref_p, uut_p, ref_q, uut_q);
				errcount = errcount + 1;
			end
		end
	endtask

	initial begin
		for (i = 0; i < (1 << S); i = i + 1) begin
			s = i;
			ext_en = 0;
			ext_val = 0;
			check;
			// Drive only the pads the design releases.
			for (j = 0; j < P; j = j + 1)
				ext_en[j] = ref_p[j] === 1'bz;
			ext_val = 0; check;
			ext_val = ~0; check;
		end
		if (errcount == 0) begin
			$display("All tests passed.");
			$finish;
		end
		$display("Caught %1d errors.", errcount);
		$stop;
	end
endmodule
