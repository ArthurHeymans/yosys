// Block RAM shapes for bram.sh, which compares the synthesised netlist
// against this RTL. Every memory has initial contents so reads are defined.

module bram_sp #(parameter W = 8, AW = 10, MODE = 0) (
	input clk, rst, we,
	input [AW-1:0] a,
	input [W-1:0] d,
	output reg [W-1:0] q
);
	reg [W-1:0] mem [0:(1<<AW)-1];
	integer i;
	initial for (i = 0; i < (1<<AW); i = i + 1) mem[i] = i * 37 + 5;
	always @(posedge clk) begin
		if (we)
			mem[a] <= d;
		if (rst)
			q <= 0;
		else if (MODE == 0 && !we) // output unchanged on write
			q <= mem[a];
		else if (MODE == 1) // shows the written data
			q <= we ? d : mem[a];
		else if (MODE == 2) // shows the old data
			q <= mem[a];
	end
endmodule

// True dual port with byte enables, in 8- or 9-bit bytes. The output keeps
// its value on a write, and the two ports never collide.
module bram_dp #(parameter B = 8, N = 2, AW = 9) (
	input clk, rst,
	input [N-1:0] we_a, we_b,
	input [AW-1:0] a, b,
	input [B*N-1:0] da, db,
	output reg [B*N-1:0] qa, qb
);
	(* no_rw_check *)
	reg [B*N-1:0] mem [0:(1<<AW)-1];
	integer i, j, k;
	initial for (i = 0; i < (1<<AW); i = i + 1) mem[i] = i * 1234567;
	always @(posedge clk) begin
		for (j = 0; j < N; j = j + 1)
			if (we_a[j])
				mem[a][j*B +: B] <= da[j*B +: B];
		if (rst)
			qa <= 0;
		else if (!we_a)
			qa <= mem[a];
	end
	always @(posedge clk) begin
		for (k = 0; k < N; k = k + 1)
			if (we_b[k])
				mem[b][k*B +: B] <= db[k*B +: B];
		if (rst)
			qb <= 0;
		else if (!we_b)
			qb <= mem[b];
	end
endmodule

// Simple dual port, reads K times as wide as writes, asynchronous reset.
module bram_sdp #(parameter W = 4, K = 8, AW = 9) (
	input clk, arst, we,
	input [AW+$clog2(K)-1:0] wa,
	input [AW-1:0] ra,
	input [W-1:0] d,
	output reg [W*K-1:0] q
);
	reg [W-1:0] mem [0:(K<<AW)-1];
	integer i;
	initial for (i = 0; i < (K<<AW); i = i + 1) mem[i] = i * 13;
	always @(posedge clk)
		if (we)
			mem[wa] <= d;
	always @(posedge clk or posedge arst)
		if (arst)
			q <= 0;
		else
			for (i = 0; i < K; i = i + 1)
				q[i*W +: W] <= mem[ra * K + i];
endmodule

module bram(
	input clk, rst, arst,
	input [3:0] we_a, we_b,
	input [13:0] a, b,
	input [35:0] da, db,
	output [327:0] q
);
	bram_sp #(.W(1), .AW(13), .MODE(0)) sp1 (clk, rst, we_a[0], a[12:0], da[0], q[0]);
	bram_sp #(.W(4), .AW(11), .MODE(1)) sp4 (clk, rst, we_a[0], a[10:0], da[3:0], q[4:1]);
	bram_sp #(.W(9), .AW(10), .MODE(2)) sp9 (clk, rst, we_a[0], a[9:0], da[8:0], q[13:5]);
	bram_sp #(.W(32), .AW(9), .MODE(1)) sp32 (clk, rst, we_a[0], a[8:0], da[31:0], q[45:14]);
	bram_dp #(.B(8), .N(2), .AW(10)) dp16 (clk, rst, we_a[1:0], we_b[1:0], a[9:0], b[9:0],
		da[15:0], db[15:0], q[61:46], q[77:62]);
	bram_dp #(.B(9), .N(2), .AW(10)) dp18 (clk, rst, we_a[1:0], we_b[1:0], a[9:0], b[9:0],
		da[17:0], db[17:0], q[95:78], q[113:96]);
	// Whole-word writes: when a byte-enabled port that keeps its output on
	// writes is split over two block RAMs, the half that is not written
	// reads, and its half of the output changes.
	bram_dp #(.B(9), .N(4), .AW(9)) dp36 (clk, rst, {4{we_a[0]}}, {4{we_b[0]}}, a[8:0], b[8:0],
		da, db, q[149:114], q[185:150]);
	bram_sdp #(.W(4), .K(8), .AW(9)) sdp32 (clk, arst, we_a[0], a[11:0], b[8:0], da[3:0], q[217:186]);
	bram_sdp #(.W(36), .K(1), .AW(9)) sdp36 (clk, arst, we_a[0], a[8:0], b[8:0], da, q[253:218]);
	// GW5A designs also use single-byte 9-bit true dual-port blocks.
	bram_dp #(.B(9), .N(1), .AW(11)) dp9 (clk, rst, we_a[0], we_b[0], a[10:0], b[10:0],
		da[8:0], db[8:0], q[262:254], q[271:263]);
	assign q[327:272] = 0;
endmodule
