module bidir(input [1:0] s, inout p, output q);
	assign p = s[0] ? s[1] : 1'bz;
	assign q = p;
endmodule
