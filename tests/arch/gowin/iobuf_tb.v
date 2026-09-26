module iobuf_tb;
	reg i = 0, oen = 1, ext_en = 0, ext_data = 0;
	wire io, o;
	assign io = ext_en ? ext_data : 1'bz;
	IOBUF uut (.I(i), .OEN(oen), .IO(io), .O(o));
	initial begin
		#1;
		if (io !== 1'bz || o !== 1'bz) $fatal(1, "released pad");
		ext_en = 1; ext_data = 1;
		#1;
		if (o !== 1'b1) $fatal(1, "external high");
		ext_data = 0;
		#1;
		if (o !== 1'b0) $fatal(1, "external low");
		ext_en = 0; oen = 0; i = 1;
		#1;
		if (io !== 1'b1 || o !== 1'b1) $fatal(1, "output high");
		i = 0;
		#1;
		if (io !== 1'b0 || o !== 1'b0) $fatal(1, "output low");
		$finish;
	end
endmodule
