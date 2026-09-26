module bidir(input [4:0] s, inout [4:0] p, output [4:0] q);
	// Plain tri-state pad
	assign p[0] = s[0] ? s[1] : 1'bz;

	// Tri-state nested below an override, as for a #HOLD pin
	assign p[1] = s[2] ? 1'b0 : (s[0] ? s[1] : 1'bz);

	// z default of a case statement ($pmux)
	reg r;
	always @*
		case (s[3:2])
			2'b00: r = s[1];
			2'b01: r = 1'b1;
			default: r = 1'bz;
		endcase
	assign p[2] = r;

	// Two levels deep
	assign p[3] = s[4] ? s[1] : (s[3] ? (s[2] ? s[0] : 1'bz) : 1'b0);

	assign p[4] = s[4] ? p[0] : 1'b0;

	assign q = p;
endmodule
