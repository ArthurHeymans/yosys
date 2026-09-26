`timescale 1ns / 1ps

// Exercise vendor positional ports and GW5A's 9-bit, async-reset DPX9B.
module positional_bram_tb;
	reg clk = 0, write_en = 1, reset = 0;
	reg [13:0] read_addr = 14'h20;
	wire [31:0] sdp8_out;
	wire [35:0] sdp9_out;
	wire [17:0] dp9_out, dp9_write_out;

	always #5 clk = ~clk;

`ifdef GOWIN_GW5A
	SDPB sdp8(clk, write_en, clk, 1'b1, 1'b1, reset,
		14'hf, read_addr, 32'h89abcdef, 3'd0, 3'd0, sdp8_out);
	SDPX9B sdp9(clk, write_en, clk, 1'b1, 1'b1, reset,
		14'hf, read_addr, 3'd0, 3'd0, 36'habc123456, sdp9_out);
`else
	SDPB sdp8(clk, write_en, clk, 1'b1, 1'b1, 1'b0, reset,
		14'hf, read_addr, 32'h89abcdef, 3'd0, 3'd0, sdp8_out);
	SDPX9B sdp9(clk, write_en, clk, 1'b1, 1'b1, 1'b0, reset,
		14'hf, read_addr, 3'd0, 3'd0, 36'habc123456, sdp9_out);
`endif
	DPX9B #(.BIT_WIDTH_0(9), .BIT_WIDTH_1(9), .WRITE_MODE0(1),
		.RESET_MODE("ASYNC")) dp9(clk, 1'b1, clk, 1'b1, 1'b1, 1'b1, 1'b0, reset,
		write_en, 1'b0, 14'd0, read_addr, 18'h001a5, 18'd0,
		3'd0, 3'd0, dp9_write_out, dp9_out);

	initial begin
		// Write address zero, then read it back from the other port.
		#6;
		if (dp9_write_out !== 18'h001a5)
			$fatal(1, "9-bit BRAM write-through: %h", dp9_write_out);
		write_en = 0; read_addr = 0;
		#10;
		if (sdp8_out !== 32'h89abcdef || sdp9_out !== 36'habc123456 || dp9_out !== 18'h001a5)
			$fatal(1, "positional BRAM write/read: %h %h %h", sdp8_out, sdp9_out, dp9_out);
		reset = 1;
		#1;
		if (dp9_out !== 0)
			$fatal(1, "9-bit BRAM async reset: %h", dp9_out);
		#9;
		if (sdp8_out !== 0 || sdp9_out !== 0)
			$fatal(1, "positional BRAM sync reset: %h %h", sdp8_out, sdp9_out);
		$display("All tests passed.");
		$finish;
	end
endmodule
