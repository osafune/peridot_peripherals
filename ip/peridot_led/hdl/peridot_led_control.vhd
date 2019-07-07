-- ===================================================================
-- TITLE : PERIDOT-NGS / WS2812B/SK6812 led controller (全体制御)
--
--     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
--     DATE   : 2018/10/21 -> 2018/11/24
--     MODIFY : 2019/06/08 s.osafune@j7system.jp
--
-- ===================================================================

-- The MIT License (MIT)
-- Copyright (c) 2018,2019 J-7SYSTEM WORKS LIMITED.
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

entity peridot_led_control is
	generic(
		LED_COLOR_TRANSORDER	: string := "GRB";	-- LEDへ転送する色順序 
		LED_CHANNEL_NUMBER		: integer := 12;	-- 1ユニットのLEDチャネル数(1～16) 
		LED_PIXELNUM_WIDTH		: integer := 8;		-- 1チャネル分のピクセルワードアドレス幅(8:256個～12:4096個)
		VRAM_ADDRESS_WIDTH		: integer := 15;	-- VRAMのアドレス幅(11:2kバイト～18:256kバイト) 
		USE_LAYER_BLEND			: string := "ON";	-- レイヤ合成を行う 
--		USE_LAYER_BLEND			: string := "OFF";	-- レイヤ合成を行わない(ov_～のポートは無視) 
		USE_FLUCTUATOR_EFFECT	: string := "ON";	-- レイヤ輝度のゆらぎ効果を行う 
--		USE_FLUCTUATOR_EFFECT	: string := "OFF";	-- レイヤ輝度のゆらぎ効果を行わない(fl_～のポートは無視) 
		BIT_TOTAL_NUNBER		: integer := 13;	-- 1ビットのクロックカウント数
		BIT_SYMBOL0_WIDTH		: integer := 2;		-- シンボル0のパルス幅(BIT_SYMBOL1_WIDTH-1以下であること) 
		BIT_SYMBOL1_WIDTH		: integer := 5;		-- シンボル1のパルス幅(BIT_TOTAL_NUNBER-8以下であること) 
		RES_COUNT_NUMBER		: integer := 3		-- リセット期間のバイトカウント数 
	);
	port(
		test_scan_begin		: out std_logic;
		test_readstart		: out std_logic;
		test_base_address	: out std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);
		test_base_pixel		: out std_logic_vector(17 downto 0);
		test_layer_pixel	: out std_logic_vector(17 downto 0);
		test_pixel_valid	: out std_logic;
		test_led_timing		: out std_logic;
		test_led_load		: out std_logic;
		test_led_data		: out std_logic_vector(7 downto 0);
		test_led_data_valid	: out std_logic;
		test_led_loaded		: out std_logic;
		test_fluct_init		: out std_logic;
		test_fluct_start	: out std_logic;
		test_fluct_valid	: out std_logic;


		clk			: in  std_logic;
		init		: in  std_logic;
		ready		: out std_logic;

		start		: in  std_logic;
		done		: out std_logic;
		scan_num	: in  std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);

		base_offset	: in  std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);
		br_red		: in  std_logic_vector(7 downto 0);
		br_green	: in  std_logic_vector(7 downto 0);
		br_blue		: in  std_logic_vector(7 downto 0);

		ov_mode		: in  std_logic_vector(1 downto 0);
		ov_offset	: in  std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);
		ov_red		: in  std_logic_vector(7 downto 0);
		ov_green	: in  std_logic_vector(7 downto 0);
		ov_blue		: in  std_logic_vector(7 downto 0);

		fl_freerun	: in  std_logic;
		fl_mode		: in  std_logic_vector(1 downto 0);
		fl_seed		: in  std_logic_vector(31 downto 0);
		fl_red		: in  std_logic_vector(7 downto 0);
		fl_green	: in  std_logic_vector(7 downto 0);
		fl_blue		: in  std_logic_vector(7 downto 0);

		led_out		: out std_logic_vector(LED_CHANNEL_NUMBER-1 downto 0);

		-- RAM I/F

		s1_clk		: in  std_logic;
		s1_address	: in  std_logic_vector(VRAM_ADDRESS_WIDTH-1 downto 0);
		s1_read		: in  std_logic;
		s1_readdata	: out std_logic_vector(31 downto 0);
		s1_write	: in  std_logic;
		s1_writedata: in  std_logic_vector(31 downto 0)
	);
end peridot_led_control;

architecture RTL of peridot_led_control is
	function CSTD(NUM:integer; WID:integer) return std_logic_vector is
	begin
		return conv_std_logic_vector(NUM, WID);
	end CSTD;

	constant PIPELINE_COUNT		: integer := 7;

	type MAIN_STATE is (IDLE, SETUP1,SETUP2, CH_SYNC, CH_LOOP1, CH_LOOP2, CH_DONE, RES_LOOP);
	signal state	: MAIN_STATE;

	signal done_reg				: std_logic;
	signal load_req_reg			: std_logic;
	signal timing_ena_reg		: std_logic;
	signal led_drive_reg		: std_logic;
	signal ch_count_reg			: std_logic_vector(3 downto 0);
	signal col_sel_reg			: std_logic_vector(1 downto 0);
	signal pix_count_reg		: std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);
	signal scan_num_reg			: std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);
	signal base_offset_reg		: std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);
	signal ov_offset_reg		: std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);
	signal res_count_reg		: integer range 0 to RES_COUNT_NUMBER;
	signal readstart_sig		: std_logic;

	signal timing_count_reg		: integer range 0 to BIT_TOTAL_NUNBER-1;
	signal bit_count_reg		: std_logic_vector(2 downto 0);
	signal scan_begin_sig		: std_logic;
	signal scan_timing_sig		: std_logic;
	signal led_loaded_sig		: std_logic;
	signal fluct_init_sig		: std_logic;
	signal fluct_start_sig		: std_logic;


	component peridot_led_vram is
	generic(
		LED_CHANNEL_NUMBER		: integer;
		LED_PIXELNUM_WIDTH		: integer;
		VRAM_CHUNKWORD_WIDTH	: integer;
		VRAM_ADDRESS_WIDTH		: integer;
		USE_LAYER_BLEND			: string
	);
	port(
		clk				: in  std_logic;
		read_req		: in  std_logic;
		channel_num		: in  std_logic_vector(3 downto 0);
		base_address	: in  std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);
		layer_address	: in  std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0) := (others=>'X');
		valid			: out std_logic;
		base_pixel		: out std_logic_vector(17 downto 0);
		layer_pixel		: out std_logic_vector(17 downto 0);

		s1_clk			: in  std_logic;
		s1_address		: in  std_logic_vector(VRAM_ADDRESS_WIDTH-1 downto 0);
		s1_read			: in  std_logic;
		s1_readdata		: out std_logic_vector(31 downto 0);
		s1_write		: in  std_logic;
		s1_writedata	: in  std_logic_vector(31 downto 0)
	);
	end component;

	signal base_address_sig		: std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);
	signal layer_address_sig	: std_logic_vector(LED_PIXELNUM_WIDTH-1 downto 0);
	signal base_pixel_sig		: std_logic_vector(17 downto 0);
	signal layer_pixel_sig		: std_logic_vector(17 downto 0);
	signal pixel_valid_sig		: std_logic;


	component peridot_led_fluctuator is
	port(
		clk			: in  std_logic;
		init		: in  std_logic;
		ov_red		: in  std_logic_vector(7 downto 0);
		ov_green	: in  std_logic_vector(7 downto 0);
		ov_blue		: in  std_logic_vector(7 downto 0);
		fl_seed		: in  std_logic_vector(31 downto 0);
		fl_mode		: in  std_logic_vector(1 downto 0);
		fl_red		: in  std_logic_vector(7 downto 0);
		fl_green	: in  std_logic_vector(7 downto 0);
		fl_blue		: in  std_logic_vector(7 downto 0);
		start		: in  std_logic;
		pix_red		: out std_logic_vector(7 downto 0);
		pix_green	: out std_logic_vector(7 downto 0);
		pix_blue	: out std_logic_vector(7 downto 0);
		pix_valid	: out std_logic
	);
	end component;

	signal pcol_red_sig			: std_logic_vector(7 downto 0);
	signal pcol_green_sig		: std_logic_vector(7 downto 0);
	signal pcol_blue_sig		: std_logic_vector(7 downto 0);
	signal pcol_valid_sig		: std_logic;


	component peridot_led_colorconv is
	generic(
		LED_COLOR_TRANSORDER	: string;
		USE_LAYER_BLEND			: string
	);
	port(
		clk			: in  std_logic;
		calc_req	: in  std_logic;
		sel			: in  std_logic_vector(1 downto 0);
		br_red		: in  std_logic_vector(7 downto 0);
		br_green	: in  std_logic_vector(7 downto 0);
		br_blue		: in  std_logic_vector(7 downto 0);
		br_pixel_in	: in  std_logic_vector(17 downto 0);
		ov_mode		: in  std_logic_vector(1 downto 0) := "00";
		ov_red		: in  std_logic_vector(7 downto 0) := (others=>'0');
		ov_green	: in  std_logic_vector(7 downto 0) := (others=>'0');
		ov_blue		: in  std_logic_vector(7 downto 0) := (others=>'0');
		ov_pixel_in	: in  std_logic_vector(17 downto 0) := (others=>'0');
		valid		: out std_logic;
		data_out	: out std_logic_vector(7 downto 0)
	);
	end component;

	signal led_data_sig			: std_logic_vector(7 downto 0);
	signal led_data_valid_sig	: std_logic;


	component peridot_led_serializer is
	generic(
		PROPAGATION_DELAY	: integer
	);
	port(
		clk			: in  std_logic;
		init		: in  std_logic := '0';
		timing		: in  std_logic;
		load		: in  std_logic;
		timing_next	: out std_logic;
		load_next	: out std_logic;
		data_in		: in  std_logic_vector(7 downto 0);
		led_out		: out std_logic
	);
	end component;

	signal led_timing_sig		: std_logic_vector(LED_CHANNEL_NUMBER downto 0);
	signal led_load_sig			: std_logic_vector(LED_CHANNEL_NUMBER downto 0);

begin

	-- テスト入出力 

	test_scan_begin <= scan_begin_sig;
	test_readstart <= readstart_sig;
	test_base_address <= base_address_sig;
	test_base_pixel <= base_pixel_sig;
	test_layer_pixel <= layer_pixel_sig;
	test_pixel_valid <= pixel_valid_sig;
	test_led_timing <= led_timing_sig(0);
	test_led_load <= led_load_sig(0);
	test_led_data <= led_data_sig;
	test_led_data_valid <= led_data_valid_sig;
	test_led_loaded <= led_loaded_sig;
	test_fluct_init <= fluct_init_sig;
	test_fluct_start <= fluct_start_sig;
	test_fluct_valid <= pcol_valid_sig;


	----------------------------------------------------------------------
	-- Main control
	----------------------------------------------------------------------

	-- ステートマシン 

	process (clk) begin
		if rising_edge(clk) then
			if (init = '1') then
				state <= IDLE;
				done_reg <= '0';
				timing_ena_reg <= '0';
				led_drive_reg <= '0';
				load_req_reg <= '0';

			else
				-- メインFSM
				case (state) is
				when IDLE =>
					done_reg <= '0';

					if (start = '1') then
						state <= SETUP1;
						col_sel_reg <= "00";
						pix_count_reg <= (others=>'0');
						scan_num_reg <= scan_num;
						base_offset_reg <= base_offset;
						ov_offset_reg <= ov_offset;
					end if;

				-- 開始シンクロ（暫定、あとで増やす） 
				when SETUP1 =>
					state <= SETUP2;

				when SETUP2 =>
					state <= CH_SYNC;
					timing_ena_reg <= '1';
					led_drive_reg <= '1';

				-- LED送出信号のタイミングを待つ 
				when CH_SYNC =>
					if (scan_begin_sig = '1') then
						state <= CH_LOOP1;
						ch_count_reg <= "0000";
					end if;

				-- ピクセル色要素読み出し・計算ループ 
				when CH_LOOP1 =>
					state <= CH_LOOP2;

				when CH_LOOP2 =>
					if (ch_count_reg = LED_CHANNEL_NUMBER-1) then
						state <= CH_DONE;
					else
						ch_count_reg <= ch_count_reg + 1;
						state <= CH_LOOP1;
					end if;

				-- 全チャネルの色要素を送信終了 
				when CH_DONE =>
					if (led_loaded_sig = '1') then

						-- 色要素カウンタとピクセルカウンタを更新 
						if (col_sel_reg = "10") then
							col_sel_reg <= "00";
							pix_count_reg <= pix_count_reg + 1;
						else
							col_sel_reg <= col_sel_reg + 1;
						end if;

						-- 全てのピクセルを処理し終わったらリセットシーケンスへ 
						if (col_sel_reg = "10" and pix_count_reg = scan_num_reg) then
							state <= RES_LOOP;
							res_count_reg <= RES_COUNT_NUMBER;
						else
							state <= CH_SYNC;
						end if;
					end if;

				-- RESコードを送出 
				when RES_LOOP =>
					if (scan_begin_sig = '1') then
						led_drive_reg <= '0';

						if (res_count_reg = 0) then
							state <= IDLE;
							done_reg <= '1';
							timing_ena_reg <= '0';
						else
							res_count_reg <= res_count_reg - 1;
						end if;
					end if;

				when others =>
				end case;


				-- LEDへのデータロード要求信号を生成
				if (state = CH_SYNC and scan_begin_sig = '1') then
					load_req_reg <= '1';
				elsif (scan_timing_sig = '1') then
					load_req_reg <= '0';
				end if;

			end if;
		end if;
	end process;

	ready <= '1' when(state = IDLE and init = '0') else '0';
	done <= done_reg;


	-- タイミング信号生成 

	process (clk) begin
		if rising_edge(clk) then
			if (timing_ena_reg = '0') then
				timing_count_reg <= 0;
				bit_count_reg <= "000";

			else
				if (timing_count_reg = BIT_TOTAL_NUNBER-1) then
					timing_count_reg <= 0;
					bit_count_reg <= bit_count_reg + 1;
				else
					timing_count_reg <= timing_count_reg + 1;
				end if;

			end if;
		end if;
	end process;

	-- ステートマシン用タイミング信号 
	scan_begin_sig <= timing_ena_reg when(timing_count_reg = 0 and bit_count_reg = "000") else '0';

	-- 計算処理開始タイミング信号 
	readstart_sig <= '1' when(state = CH_LOOP1) else '0';

	-- LED駆動用タイミング信号(処理パイプライン分の遅延を入れる) 
	scan_timing_sig <= '1' when(timing_count_reg = PIPELINE_COUNT or
								timing_count_reg = PIPELINE_COUNT + BIT_SYMBOL0_WIDTH or
								timing_count_reg = PIPELINE_COUNT + BIT_SYMBOL1_WIDTH
							) else '0';

	led_timing_sig(0) <= led_drive_reg when(scan_timing_sig = '1') else '0';
	led_load_sig(0) <= load_req_reg when(scan_timing_sig = '1') else '0';

	-- 最後のLEDチャネルにピクセルデータがロードされた 
	led_loaded_sig <= led_load_sig(LED_CHANNEL_NUMBER);

	-- ゆらぎ効果演算開始タイミング信号 
	fluct_init_sig <= '1' when(fl_freerun = '0' and start = '1' and state = IDLE) else '0';
	fluct_start_sig <= '1' when((led_loaded_sig = '1' and col_sel_reg = "10") or state = SETUP1) else '0';



	----------------------------------------------------------------------
	-- Instance of sub module
	----------------------------------------------------------------------

	-- レイヤー合成を使う場合 
	use_blend : if (USE_LAYER_BLEND = "ON") generate

		-- ピクセルメモリ 
		base_address_sig <= base_offset_reg + pix_count_reg;
		layer_address_sig <= ov_offset_reg + pix_count_reg;

		u_vram : peridot_led_vram
		generic map(
			LED_CHANNEL_NUMBER		=> LED_CHANNEL_NUMBER,
			LED_PIXELNUM_WIDTH		=> LED_PIXELNUM_WIDTH,
			VRAM_CHUNKWORD_WIDTH	=> LED_PIXELNUM_WIDTH + 1,
			VRAM_ADDRESS_WIDTH		=> VRAM_ADDRESS_WIDTH,
			USE_LAYER_BLEND			=> "ON"
		)
		port map(
			clk				=> clk,

			read_req		=> readstart_sig,
			channel_num		=> ch_count_reg,
			base_address	=> base_address_sig,
			layer_address	=> layer_address_sig,

			valid			=> pixel_valid_sig,
			base_pixel		=> base_pixel_sig,
			layer_pixel		=> layer_pixel_sig,

			s1_clk			=> s1_clk,
			s1_address		=> s1_address,
			s1_read			=> s1_read,
			s1_readdata		=> s1_readdata,
			s1_write		=> s1_write,
			s1_writedata	=> s1_writedata
		);


		-- レイヤーゆらぎ効果を使う場合 
		use_fluct : if (USE_FLUCTUATOR_EFFECT = "ON") generate
			u_fluct : peridot_led_fluctuator
			port map(
				clk			=> clk,
				init		=> fluct_init_sig,
				start		=> fluct_start_sig,

				ov_red		=> ov_red,
				ov_green	=> ov_green,
				ov_blue		=> ov_blue,
				fl_seed		=> fl_seed,
				fl_mode		=> fl_mode,
				fl_red		=> fl_red,
				fl_green	=> fl_green,
				fl_blue		=> fl_blue,

				pix_red		=> pcol_red_sig,
				pix_green	=> pcol_green_sig,
				pix_blue	=> pcol_blue_sig,
				pix_valid	=> pcol_valid_sig
			);
		end generate;

		-- レイヤーゆらぎ効果を使わない場合 
		no_fluct : if (USE_FLUCTUATOR_EFFECT /= "ON") generate
			pcol_red_sig <= ov_red;
			pcol_green_sig <= ov_green;
			pcol_blue_sig <= ov_blue;
			pcol_valid_sig <= '0';
		end generate;


		-- 輝度変換・レイヤー合成・γ変換 
		u_conv : peridot_led_colorconv
		generic map(
			LED_COLOR_TRANSORDER	=> LED_COLOR_TRANSORDER,
			USE_LAYER_BLEND			=> "ON"
		)
		port map(
			clk			=> clk,

			calc_req	=> pixel_valid_sig,
			sel			=> col_sel_reg,

			br_red		=> br_red,
			br_green	=> br_green,
			br_blue		=> br_blue,
			br_pixel_in	=> base_pixel_sig,

			ov_mode		=> ov_mode,
			ov_red		=> pcol_red_sig,
			ov_green	=> pcol_green_sig,
			ov_blue		=> pcol_blue_sig,
			ov_pixel_in	=> layer_pixel_sig,

			valid		=> led_data_valid_sig,
			data_out	=> led_data_sig
		);
	end generate;

	-- レイヤー合成を使わない場合 
	no_blend : if (USE_LAYER_BLEND /= "ON") generate

		-- ピクセルメモリ 
		base_address_sig <= base_offset_reg + pix_count_reg;

		u_vram : peridot_led_vram
		generic map(
			LED_CHANNEL_NUMBER		=> LED_CHANNEL_NUMBER,
			LED_PIXELNUM_WIDTH		=> LED_PIXELNUM_WIDTH,
			VRAM_CHUNKWORD_WIDTH	=> LED_PIXELNUM_WIDTH,
			VRAM_ADDRESS_WIDTH		=> VRAM_ADDRESS_WIDTH,
			USE_LAYER_BLEND			=> "OFF"
		)
		port map(
			clk				=> clk,

			read_req		=> readstart_sig,
			channel_num		=> ch_count_reg,
			base_address	=> base_address_sig,

			valid			=> pixel_valid_sig,
			base_pixel		=> base_pixel_sig,

			s1_clk			=> s1_clk,
			s1_address		=> s1_address,
			s1_read			=> s1_read,
			s1_readdata		=> s1_readdata,
			s1_write		=> s1_write,
			s1_writedata	=> s1_writedata
		);

		-- 輝度変換・γ変換 
		u_conv : peridot_led_colorconv
		generic map(
			LED_COLOR_TRANSORDER	=> LED_COLOR_TRANSORDER,
			USE_LAYER_BLEND			=> "OFF"
		)
		port map(
			clk			=> clk,

			calc_req	=> pixel_valid_sig,
			sel			=> col_sel_reg,

			br_red		=> br_red,
			br_green	=> br_green,
			br_blue		=> br_blue,
			br_pixel_in	=> base_pixel_sig,

			valid		=> led_data_valid_sig,
			data_out	=> led_data_sig
		);
	end generate;


	-- LEDシリアライザ 

	gen_led : for i in 0 to LED_CHANNEL_NUMBER-1 generate
		u_led : peridot_led_serializer
		generic map(
			PROPAGATION_DELAY	=> 2
		)
		port map(
			clk			=> clk,
			init		=> init,

			timing		=> led_timing_sig(i),
			load		=> led_load_sig(i),
			timing_next	=> led_timing_sig(i+1),
			load_next	=> led_load_sig(i+1),

			data_in		=> led_data_sig,
			led_out		=> led_out(i)
		);
	end generate;



end RTL;
