`timescale 1ns / 1ps
module bram_controls_tb;
	GSR GSR (.GSRI(1'b1));
	reg clk = 0, ce = 1, oce = 0, reset = 0;
	reg [13:0] addr = 0;
	wire [31:0] q;
	SP #(.BIT_WIDTH(8), .READ_MODE(1), .INIT_RAM_00(256'hcdab)) uut (
		.CLK(clk), .CE(ce), .OCE(oce), .RESET(reset), .WRE(1'b0),
		.AD(addr), .DI(32'b0), .BLKSEL(3'b0), .DO(q));
	task tick;
		begin #5; clk = 1; #1; clk = 0; end
	endtask
	initial begin
		tick;
		ce = 0; oce = 1;
		tick;
		if (q !== 32'hab) $fatal(1, "OCE with CE low: %h", q);
		ce = 1; oce = 0; addr = 14'd8;
		tick;
		if (q !== 32'hab) $fatal(1, "OCE hold: %h", q);
		ce = 0; oce = 1;
		tick;
		if (q !== 32'hcd) $fatal(1, "second pipeline word: %h", q);
		reset = 1; oce = 0;
		tick;
		if (q !== 0) $fatal(1, "reset with CE and OCE low: %h", q);
		$display("All tests passed.");
		$finish;
	end
endmodule
