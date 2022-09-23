// ===================================================================
// TITLE : PERIDOT Ethernet I/O Extender / Memory FIFO
//
//     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
//     DATE   : 2022/07/31 -> 2022/08/08
//            : 2022/09/08 (FIXED)
//
// ===================================================================
//
// The MIT License (MIT)
// Copyright (c) 2022 J-7SYSTEM WORKS LIMITED.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is furnished to do
// so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

// Verilog-2001 / IEEE 1364-2001
`default_nettype none

module peridot_ethio_memfifo #(
	parameter FIFO_BLOCKNUM_BITWIDTH	= 6,	// FIFOブロック数のビット値 (2^nで個数を指定) : 4～
	parameter FIFO_BLOCKSIZE_BITWIDTH	= 6,	// ブロックサイズ幅ビット値 (2^nでバイトサイズを指定) : MEM_ADDRESS_LSB～
	parameter MEM_ADDRESS_BITWIDTH		= 11,	// メモリウィンドウアドレス幅ビット値 (2^nでバイトサイズを指定) : 6～FIFO_BLOCKNUM_BITWIDTH+FIFO_BLOCKSIZE_BITWIDTH
	parameter MEM_WORDSIZE_BITWIDTH		= 4,	// メモリワードサイズ幅ビット値 (2^nでビット幅を指定) : 1,2,4,8
	parameter RAM_READOUT_REGISTER		= "ON",	// 読み出しレジスタの有無 "ON"=あり(リードレイテンシ2) / "OFF"=なし(リードレイテンシ1)
	parameter RAM_OVERRUN_PROTECTION	= "ON",	// 書き込みオーバーラン保護 "ON"=あり(オーバーラン部分の書き込みを抑止) / "OFF"=なし
	parameter TEST_WPTR_INITVALUE		= 0,	// ライト側ポインタの初期値(テスト用)
	parameter TEST_RPTR_INITVALUE		= 0		// リード側ポインタの初期値(テスト用)
) (
	// ライト側 
	input wire			reset_a,
	input wire			clk_a,

	output wire			ready_a,
	input wire			update_a,
	input wire  [FIFO_BLOCKNUM_BITWIDTH-1:0] blocknum_a,	// 更新するブロック数 
	output wire [FIFO_BLOCKNUM_BITWIDTH-1:0] free_a,		// 空いてるブロック数 
	output wire			full_a,								// FIFOフル(空きブロック数=0)

	input wire			enable_a,							// メモリアクセスパイプラインのイネーブル 
	input wire  [MEM_ADDRESS_BITWIDTH-1   :0] address_a,	// メモリウィンドウ内のバイトアドレスオフセット 
	input wire  [MEM_WORDSIZE_BITWIDTH*8-1:0] writedata_a,
	input wire  [MEM_WORDSIZE_BITWIDTH  -1:0] writeenable_a,
	output wire [MEM_WORDSIZE_BITWIDTH*8-1:0] readdata_a,
	output wire			writeerror_a,						// 1=使っているブロックに書き込みを行った 

	// リード側 
	input wire			reset_b,
	input wire			clk_b,

	output wire			ready_b,
	input wire			update_b,
	input wire  [FIFO_BLOCKNUM_BITWIDTH-1:0] blocknum_b,	// 更新するブロック数 
	output wire [FIFO_BLOCKNUM_BITWIDTH-1:0] remain_b,		// 残っているブロック数 
	output wire			empty_b,							// FIFOエンプティ(残りのブロック数=0)

	input wire			enable_b,							// メモリアクセスパイプラインのイネーブル 
	input wire  [MEM_ADDRESS_BITWIDTH-1   :0] address_b,	// メモリウィンドウ内のバイトアドレスオフセット 
	output wire [MEM_WORDSIZE_BITWIDTH*8-1:0] readdata_b
);


/* ===== 外部変更可能パラメータ ========== */



/* ----- 内部パラメータ ------------------ */

	localparam MEM_ADDRESS_LSB =	(MEM_WORDSIZE_BITWIDTH == 8)? 3 :
									(MEM_WORDSIZE_BITWIDTH == 4)? 2 :
									(MEM_WORDSIZE_BITWIDTH == 2)? 1 :
									0;

	localparam RAM_NUMWORD_BITWIDTH = FIFO_BLOCKNUM_BITWIDTH + FIFO_BLOCKSIZE_BITWIDTH - MEM_ADDRESS_LSB;

	localparam MEM_ADDR_PADDING  = {(FIFO_BLOCKNUM_BITWIDTH + FIFO_BLOCKSIZE_BITWIDTH - MEM_ADDRESS_BITWIDTH){1'b0}};
	localparam MEM_BLOCK_PADDING = {(FIFO_BLOCKSIZE_BITWIDTH){1'b0}};


/* ※以降のパラメータ宣言は禁止※ */

/* ===== ノード宣言 ====================== */
				/* ライト側クロックドメイン */
	wire			reset_write_sig = reset_a;		// ライト側非同期リセット 
	wire			clock_write_sig = clk_a;		// ライト側クロック 

				/* リード側クロックドメイン */
	wire			reset_read_sig = reset_b;		// リート側非同期リセット 
	wire			clock_read_sig = clk_b;			// リード側クロック 

	wire			ready_a_sig, ready_b_sig;
	reg  [FIFO_BLOCKNUM_BITWIDTH-1:0] wptr_reg, rptr_reg;
	wire [FIFO_BLOCKNUM_BITWIDTH-1:0] ref_wptr_sig, free_blocknum_sig, adder_a_sig, new_wptr_sig;
	wire [FIFO_BLOCKNUM_BITWIDTH-1:0] ref_rptr_sig, remain_blocknum_sig, adder_b_sig, new_rptr_sig;

	wire [FIFO_BLOCKNUM_BITWIDTH+FIFO_BLOCKSIZE_BITWIDTH-1:0] byte_addr_sig;
	wire [FIFO_BLOCKNUM_BITWIDTH-1:0] block_addr_sig;
	wire			wena_sig;

	wire [FIFO_BLOCKNUM_BITWIDTH+FIFO_BLOCKSIZE_BITWIDTH-1:0] address_a_sig, address_b_sig;
	genvar	i;


/* ※以降のwire、reg宣言は禁止※ */

/* ===== テスト記述 ============== */

//	assign test_wena = wena_sig;
//	assign test_address_a = address_a_sig;
//	assign test_address_b = address_b_sig;


/* ===== モジュール構造記述 ============== */

	// ライト側FIFOブロック制御 

	always @(posedge clock_write_sig or posedge reset_write_sig) begin
		if (reset_write_sig) begin
			wptr_reg <= TEST_WPTR_INITVALUE[FIFO_BLOCKNUM_BITWIDTH-1:0];
		end
		else begin
			if (ready_a_sig && update_a) begin
				wptr_reg <= new_wptr_sig;
			end
		end
	end

	peridot_ethio_cdb_stream #(
		.USE_PORT_DATA		("ON"),
		.DATA_BITWIDTH		(FIFO_BLOCKNUM_BITWIDTH),
		.DATA_INITVALUE		(TEST_WPTR_INITVALUE)
	)
	u_cdb_write (
		.reset_a	(reset_write_sig),
		.clk_a		(clock_write_sig),
		.in_ready	(ready_a_sig),
		.in_valid	(update_a),
		.in_data	(new_wptr_sig),

		.reset_b	(reset_read_sig),
		.clk_b		(clock_read_sig),
		.out_ready	(1'b1),
		.out_valid	(),
		.out_data	(ref_wptr_sig)
	);

	assign free_blocknum_sig = ref_rptr_sig - wptr_reg - 1'd1;
	assign adder_a_sig = (blocknum_a > free_blocknum_sig)? free_blocknum_sig : blocknum_a;
	assign new_wptr_sig = wptr_reg + adder_a_sig;

	assign ready_a = ready_a_sig;
	assign free_a = free_blocknum_sig;
	assign full_a = (!free_blocknum_sig);


	// リード側FIFOブロック制御 

	always @(posedge clock_read_sig or posedge reset_read_sig) begin
		if (reset_read_sig) begin
			rptr_reg <= TEST_RPTR_INITVALUE[FIFO_BLOCKNUM_BITWIDTH-1:0];
		end
		else begin
			if (ready_b_sig && update_b) begin
				rptr_reg <= new_rptr_sig;
			end
		end
	end

	peridot_ethio_cdb_stream #(
		.USE_PORT_DATA		("ON"),
		.DATA_BITWIDTH		(FIFO_BLOCKNUM_BITWIDTH),
		.DATA_INITVALUE		(TEST_RPTR_INITVALUE)
	)
	u_cdb_read (
		.reset_a	(reset_read_sig),
		.clk_a		(clock_read_sig),
		.in_ready	(ready_b_sig),
		.in_valid	(update_b),
		.in_data	(new_rptr_sig),

		.reset_b	(reset_write_sig),
		.clk_b		(clock_write_sig),
		.out_ready	(1'b1),
		.out_valid	(),
		.out_data	(ref_rptr_sig)
	);

	assign remain_blocknum_sig = ref_wptr_sig - rptr_reg;
	assign adder_b_sig = (blocknum_b > remain_blocknum_sig)? remain_blocknum_sig : blocknum_b;
	assign new_rptr_sig = rptr_reg + adder_b_sig;

	assign ready_b = ready_b_sig;
	assign remain_b = remain_blocknum_sig;
	assign empty_b = (!remain_blocknum_sig);


	// DPRAM制御 

	assign byte_addr_sig = {MEM_ADDR_PADDING, address_a};
	assign block_addr_sig = byte_addr_sig[FIFO_BLOCKNUM_BITWIDTH+FIFO_BLOCKSIZE_BITWIDTH-1:FIFO_BLOCKSIZE_BITWIDTH];
	assign wena_sig = (RAM_OVERRUN_PROTECTION == "ON" && block_addr_sig >= free_blocknum_sig)? 1'b0 : 1'b1;
	assign writeerror_a = (writeenable_a && !wena_sig);

	assign address_a_sig = byte_addr_sig + {wptr_reg, MEM_BLOCK_PADDING};
	assign address_b_sig = {MEM_ADDR_PADDING, address_b} + {rptr_reg, MEM_BLOCK_PADDING};

	generate
	for(i=0 ; i<MEM_WORDSIZE_BITWIDTH ; i=i+1) begin : u_mem
		peridot_ethio_dpram #(
			.RAM_NUMWORD_BITWIDTH	(RAM_NUMWORD_BITWIDTH),
			.RAM_READOUT_REGISTER	(RAM_READOUT_REGISTER)
		)
		u (
			.clk_a			(clock_write_sig),
			.clkena_a		(enable_a),
			.address_a		(address_a_sig[FIFO_BLOCKNUM_BITWIDTH+FIFO_BLOCKSIZE_BITWIDTH-1:MEM_ADDRESS_LSB]),
			.writedata_a	(writedata_a[(i+1)*8-1 -: 8]),
			.writeenable_a	(writeenable_a[i] & wena_sig),
			.readdata_a		(readdata_a[(i+1)*8-1 -: 8]),

			.clk_b			(clock_read_sig),
			.clkena_b		(enable_b),
			.address_b		(address_b_sig[FIFO_BLOCKNUM_BITWIDTH+FIFO_BLOCKSIZE_BITWIDTH-1:MEM_ADDRESS_LSB]),
			.writedata_b	({8{1'bx}}),
			.writeenable_b	(1'b0),
			.readdata_b		(readdata_b[(i+1)*8-1 -: 8])
		);
	end
	endgenerate


endmodule

`default_nettype wire
