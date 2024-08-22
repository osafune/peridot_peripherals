// (C) 2001-2020 Intel Corporation. All rights reserved.
// Your use of Intel Corporation's design tools, logic functions and other 
// software and tools, and its AMPP partner logic functions, and any output 
// files from any of the foregoing (including device programming or simulation 
// files), and any associated documentation or information are expressly subject 
// to the terms and conditions of the Intel Program License Subscription 
// Agreement, Intel FPGA IP License Agreement, or other applicable 
// license agreement, including, without limitation, that your use is for the 
// sole purpose of programming logic devices manufactured by Intel and sold by 
// Intel or its authorized distributors.  Please refer to the applicable 
// agreement for further details.


// synthesis translate_off
`timescale 1ns / 1ps
// synthesis translate_on

// turn off superfluous verilog processor warnings 
// altera message_level Level1 
// altera message_off 10034 10035 10036 10037 10230 10240 10030 

module altera_sdram_tri_controller
   #(
      parameter                           TRISTATE_EN = 0,
      parameter                           NUM_CHIPSELECTS = 1,
      parameter                           CNTRL_ADDR_WIDTH = 22,                    // width of the Avalon address
      parameter                           SDRAM_BANK_WIDTH = 2,                     // width of the SDRAM bank address (1/2) corresponding to (2/4) banks
      parameter                           SDRAM_ROW_WIDTH = 12,                     // width of the SDRAM address bus (same as the row address width)
      parameter                           SDRAM_COL_WIDTH = 8,                      // width of the SDRAM column
      parameter                           SDRAM_DATA_WIDTH = 32,                    // width of the SDRAM data bus
      parameter                           CAS_LATENCY = 2,                          // CAS Latency period
      parameter                           INIT_REFRESH = 2,                         // Initialization Refresh Cycles
      parameter                           REFRESH_PERIOD = 1563,                    // Refresh period (in clock cycles)
      parameter                           POWERUP_DELAY = 10000,                    // Delay after power-up, before initialization (in clock cycles)
      parameter                           T_RFC = 7,                                // duration of refresh command (in clock cycles)
      parameter                           T_RP = 2,                                 // duration of precharge command (in clock cycles)
      parameter                           T_RCD = 2,                                // ACTIVE to READ/WRITE delay (wait cycles)
      parameter                           T_WR = 5,                                 // time that must elapse after the last write before the row may be closed
      parameter                           MAX_REC_TIME = 1                          // maximum recovery time
   )
   (
      // Clock/Reset (from top-level)
      input wire                                   clk                  ,           // system clock
      input wire                                   rst_n                ,           // system asynchronous reset
      // Avalon-MM Slave Interface
      input wire                                   avs_read             ,
      input wire                                   avs_write            ,
      input wire  [ (SDRAM_DATA_WIDTH/8) - 1 : 0 ] avs_byteenable       ,
      input wire      [ CNTRL_ADDR_WIDTH - 1 : 0 ] avs_address          ,
      input wire      [ SDRAM_DATA_WIDTH - 1 : 0 ] avs_writedata        ,
      output wire     [ SDRAM_DATA_WIDTH - 1 : 0 ] avs_readdata         ,
      output wire                                  avs_readdatavalid    ,
      output wire                                  avs_waitrequest      ,
      // TCM Interface
      input wire                                   tcm_grant            ,        // grant from tri-state conduit slave
      output wire                                  tcm_request          ,        // request to tri-state conduit slave
      // SDRAM Interface
      output wire     [  SDRAM_ROW_WIDTH - 1 : 0 ] sdram_addr           ,
      output wire     [ SDRAM_BANK_WIDTH - 1 : 0 ] sdram_ba             ,
      inout  wire     [ SDRAM_DATA_WIDTH - 1 : 0 ] sdram_dq             ,        // zs_dq
      output wire     [ SDRAM_DATA_WIDTH - 1 : 0 ] sdram_dq_out         ,
      input wire      [ SDRAM_DATA_WIDTH - 1 : 0 ] sdram_dq_in          ,        // tz_data
      output wire                                  sdram_dq_oe          ,
      output wire [ (SDRAM_DATA_WIDTH/8) - 1 : 0 ] sdram_dqm            ,
      output wire                                  sdram_ras_n          ,
      output wire                                  sdram_cas_n          ,
      output wire                                  sdram_we_n           ,
      output wire      [ NUM_CHIPSELECTS - 1 : 0 ] sdram_cs_n           ,
      output wire                                  sdram_cke
   );

   // ------------------------------------------------------------------
   // Ceil(log2()) function log2ceil of 4 = 2
   // ------------------------------------------------------------------
   function integer log2ceil;
     input reg[63:0] val;
     reg [63:0] i;
     begin
       i = 1;
       log2ceil = 0;
       while (i < val) begin
         log2ceil = log2ceil + 1;
         i = i << 1;
       end
     end
   endfunction
   
   function integer max_2;
     input reg[63:0] val0;
     input reg[63:0] val1;
     begin
       if (val0 > val1)
         max_2 = val0;
       else
         max_2 = val1;
      end
   endfunction
   
   function integer max_5;
     input reg[63:0] val0;
     input reg[63:0] val1;
     input reg[63:0] val2;
     input reg[63:0] val3;
     input reg[63:0] val4;
     reg [63:0] i;
     reg [63:0] j;
     begin
       max_5 = 1;
       if (val0 > val1)  max_5 = val0;
       else              max_5 = val1;
       if (val2 > max_5) max_5 = val2;
       if (val3 > max_5) max_5 = val3;
       if (val4 > max_5) max_5 = val4;
     end
   endfunction

   //*************************** Internal Constants ***************************
   //**************************************************************************
   localparam                          SDRAM_ADDR_WIDTH  = SDRAM_ROW_WIDTH;

   // SDRAM commands = {ras, cas, we}
   localparam                          CMD_LMR           = 3'b000;            // Load Mode Register
   localparam                          CMD_REFRESH       = 3'b001;            // Auto Refresh: refresh one row of each bank, using an internal counter; all banks must be precharged
   localparam                          CMD_PRECHARGE     = 3'b010;            // Precharge
   localparam                          CMD_ACTIVE        = 3'b011;            // Active (activate): open a row for Read and Write commands
   localparam                          CMD_WRITE         = 3'b100;            // Write: Write a burst of data to the currently active row
   localparam                          CMD_READ          = 3'b101;            // Read: Read a burst of data from the currently active row
   localparam                          CMD_BURST         = 3'b110;            // Burst Terminate: stop a burst read or burst write in progress
   localparam                          CMD_NOP           = 3'b111;            // No-Operation

   localparam                          T_MRD             = 4;

   // Initialization States
   localparam                          I_RESET           = 3'b000;            // Reset
   localparam                          I_PRECH           = 3'b001;            // Precharge
   localparam                          I_ARF             = 3'b010;            // Auto Refresh
   localparam                          I_WAIT            = 3'b011;            // Wait
   localparam                          I_INIT            = 3'b101;            // Init Done
   localparam                          I_LMR             = 3'b111;            // Load Mode Register

   // Main States
   localparam                          M_IDLE            = 9'b000000001;      // Idle
   localparam                          M_RAS             = 9'b000000010;      // RAS - Row Address
   localparam                          M_WAIT            = 9'b000000100;      // Wait
   localparam                          M_RD              = 9'b000001000;      // Read
   localparam                          M_WR              = 9'b000010000;      // Write
   localparam                          M_REC             = 9'b000100000;      // Recover
   localparam                          M_PRE             = 9'b001000000;      // Precharge
   localparam                          M_REF             = 9'b010000000;      // Refresh
   localparam                          M_OPEN            = 9'b100000000;

   // number of bits required to represent the number of chip select present
   localparam                          NUM_CS_ADDR_WIDTH  = log2ceil(NUM_CHIPSELECTS);
   localparam                          NUM_CS_N_WIDTH = (NUM_CHIPSELECTS == 1) ? 1 : log2ceil(NUM_CHIPSELECTS);
   // number of data mask bits
   localparam                          SDRAM_DQM_WIDTH = SDRAM_DATA_WIDTH / 8;
   // number of pipeline stage introduced in the tristate module
   localparam                          TRISTATE_PIPELINE = TRISTATE_EN ? 2 : 0;
   // Refresh counter width
   localparam                          POWERUP_DELAY_WIDTH = log2ceil(POWERUP_DELAY);
   localparam                          REFRESH_PERIOD_WIDTH = log2ceil(REFRESH_PERIOD);
   localparam                          REFRESH_CNT_WIDTH = max_2(POWERUP_DELAY_WIDTH, REFRESH_PERIOD_WIDTH);
   // delay counter width
   localparam                          T_RP_WIDTH  = log2ceil(T_RP + 1);
   localparam                          T_RFC_WIDTH = log2ceil(T_RFC + 1);
   localparam                          T_MRD_WIDTH = log2ceil(T_MRD + 1);
   localparam                          T_RCD_WIDTH = log2ceil(T_RCD + 1);
   localparam                          T_WR_WIDTH  = log2ceil(T_WR + 1);
   // maximum timing counter bit width
   localparam                          TIM_CNT_WIDTH = max_5(T_RP_WIDTH, T_RFC_WIDTH, T_MRD_WIDTH, T_RCD_WIDTH, T_WR_WIDTH);

   localparam                          TOP_ROW_ADDR    = (SDRAM_BANK_WIDTH == 1) ? CNTRL_ADDR_WIDTH - NUM_CS_ADDR_WIDTH - 1 : CNTRL_ADDR_WIDTH - NUM_CS_ADDR_WIDTH - 2;
   localparam                          BOTTOM_ROW_ADDR = (SDRAM_BANK_WIDTH == 1) ? SDRAM_COL_WIDTH + 1                      : TOP_ROW_ADDR - SDRAM_ADDR_WIDTH + 1;

   // add 1 to col_width {A[...11], 1'b0, A[9:0]}: force A[10] LOW!
   localparam                          CAS_ADDR_WIDTH = (SDRAM_COL_WIDTH < 11) ? SDRAM_COL_WIDTH : SDRAM_COL_WIDTH + 1;

   // read datapath latency
   localparam                          RD_LATENCY = CAS_LATENCY+TRISTATE_PIPELINE;

   //**************************** Internal Signals ****************************
   //**************************************************************************

   wire                                grant                      ;
   reg                                 request                    ;

   wire                                az_rd_n                    ;
   wire                                az_wr_n                    ;
   wire   [  SDRAM_DQM_WIDTH - 1 : 0 ] az_be_n                    ;
   wire   [ CNTRL_ADDR_WIDTH - 1 : 0 ] az_addr                    ;
   wire   [ SDRAM_DATA_WIDTH - 1 : 0 ] az_data                    ;

   reg    [ SDRAM_DATA_WIDTH - 1 : 0 ] za_data                    /* synthesis ALTERA_ATTRIBUTE = "FAST_INPUT_REGISTER=ON"  */;
   reg                                 za_valid                   ;

   wire                                za_waitrequest             ;

   reg                                 ack_refresh_request        ;

   reg     [ CNTRL_ADDR_WIDTH - 
           NUM_CS_ADDR_WIDTH - 1 : 0 ] active_addr                ;
   wire   [ SDRAM_BANK_WIDTH - 1 : 0 ] active_bank                ;
   reg      [ NUM_CS_N_WIDTH - 1 : 0 ] active_cs_n                ;
   reg    [ SDRAM_DATA_WIDTH - 1 : 0 ] active_data                ;
   reg    [  SDRAM_DQM_WIDTH - 1 : 0 ] active_dqm                 ;
   reg                                 active_rnw                 ;

   wire                                almost_empty               ;
   wire                                almost_full                ;

   wire                                bank_match                 ;
   wire     [ CAS_ADDR_WIDTH - 1 : 0 ] cas_addr                   ;
   wire                                clk_en                     ;
   wire     [ NUM_CS_N_WIDTH - 1 : 0 ] cs_n                       ;
   wire    [ NUM_CHIPSELECTS - 1 : 0 ] csn_decode                 ;
   wire                                csn_match                  ;

   wire    [ CNTRL_ADDR_WIDTH - 
           NUM_CS_ADDR_WIDTH - 1 : 0 ] f_addr                     ;
   wire   [ SDRAM_BANK_WIDTH - 1 : 0 ] f_bank                     ;
   wire     [ NUM_CS_N_WIDTH - 1 : 0 ] f_cs_n                     ;
   wire   [ SDRAM_DATA_WIDTH - 1 : 0 ] f_data                     ;
   wire   [  SDRAM_DQM_WIDTH - 1 : 0 ] f_dqm                      ;
   wire                                f_empty                    ;
   reg                                 f_pop                      ;
   wire                                f_rnw                      ;
   wire                                f_select                   ;
   wire    [ CNTRL_ADDR_WIDTH + SDRAM_DQM_WIDTH + 
                SDRAM_DATA_WIDTH : 0 ] fifo_read_data             ;

   reg     [ SDRAM_ADDR_WIDTH - 1 : 0] i_addr                     ;
   reg  [ NUM_CHIPSELECTS + 3 - 1 : 0] i_cmd                      ;
   reg      [  TIM_CNT_WIDTH - 1 : 0 ] i_count                    ;
   reg                      [  2 : 0 ] i_refs                     ;
   reg                                 i_req                      ;
   reg                      [  2 : 0 ] i_state                    ;
   reg                      [  2 : 0 ] i_next                     ;
   reg                                 init_done                  ;

   reg    [ SDRAM_ADDR_WIDTH - 1 : 0 ] m_addr                     /* synthesis ALTERA_ATTRIBUTE = "FAST_OUTPUT_REGISTER=ON"  */;
   reg    [ SDRAM_BANK_WIDTH - 1 : 0 ] m_bank                     /* synthesis ALTERA_ATTRIBUTE = "FAST_OUTPUT_REGISTER=ON"  */;
   reg [ NUM_CHIPSELECTS + 3 - 1 : 0 ] m_cmd                      /* synthesis ALTERA_ATTRIBUTE = "FAST_OUTPUT_REGISTER=ON"  */;
   reg    [ SDRAM_DATA_WIDTH - 1 : 0 ] m_data                     /* synthesis ALTERA_ATTRIBUTE = "FAST_OUTPUT_REGISTER=ON ; FAST_OUTPUT_ENABLE_REGISTER=ON"  */;
   reg    [  SDRAM_DQM_WIDTH - 1 : 0 ] m_dqm                      /* synthesis ALTERA_ATTRIBUTE = "FAST_OUTPUT_REGISTER=ON"  */;
   reg                                 oe                         /* synthesis ALTERA_ATTRIBUTE = "FAST_OUTPUT_ENABLE_REGISTER=ON"  */;

   reg                      [  8 : 0 ] m_state                    ;
   reg                      [  8 : 0 ] m_next                     ;
   reg      [  TIM_CNT_WIDTH - 1 : 0 ] m_count                    ;
   
   reg                                 m_csn                      ;

   wire                                pending                    ;
   wire                                rd_strobe                  ;
   reg           [  RD_LATENCY-1 : 0 ] rd_valid                   ;
   
   reg   [ REFRESH_CNT_WIDTH - 1 : 0 ] refresh_counter            ;
   reg                                 refresh_request            ;
   wire                                rnw_match                  ;
   wire                                row_match                  ;

   reg                                 za_cannotrefresh           ;

   wire   [ SDRAM_DATA_WIDTH - 1 : 0 ] dq                         ;     // tz_data / zs_dq


   //****************************** Architecture ******************************
   //**************************************************************************
   assign clk_en = 1;
   
   assign grant         = TRISTATE_EN ? tcm_grant     : 1'b1;
   assign tcm_request   = TRISTATE_EN ? request       : 1'b0;

   // ------------------------------------------------------------------------------------------------------------------
   // SDRAM Signal Generation
   // ------------------------------------------------------------------------------------------------------------------
   assign {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = m_cmd;
   assign sdram_dq      = oe ? m_data : {SDRAM_DATA_WIDTH{1'bz}};
   assign sdram_dq_out  = m_data;
   assign sdram_dq_oe   = oe;
   assign sdram_addr    = m_addr;
   assign sdram_ba      = m_bank;
   assign sdram_dqm     = m_dqm;
   assign sdram_cke     = clk_en;

   // ------------------------------------------------------------------------------------------------------------------
   // Avalon Slave Interface
   // ------------------------------------------------------------------------------------------------------------------
   assign az_rd_n = ~avs_read;
   assign az_wr_n = ~avs_write;
   assign az_be_n = ~avs_byteenable;
   assign az_addr = avs_address;
   assign az_data = avs_writedata;
   assign avs_readdata = za_data;
   assign avs_readdatavalid = za_valid;
   assign avs_waitrequest = za_waitrequest;

   // buffer input from Avalon
   // all requests are queued inside a fifo first before being executed by the Main FSM
   efifo_module #(
      .DATA_WIDTH    (CNTRL_ADDR_WIDTH + SDRAM_DQM_WIDTH + SDRAM_DATA_WIDTH + 1),
      .DEPTH         (2                                                        )
   ) the_efifo_module 
   (
      .almost_empty  (almost_empty                                         ),
      .almost_full   (almost_full                                          ),
      .clk           (clk                                                  ),
      .empty         (f_empty                                              ),
      .full          (za_waitrequest                                       ),
      .rd            (f_select                                             ),
      .rd_data       (fifo_read_data                                       ),
      .rst_n         (rst_n                                                ),
      .wr            ((~az_wr_n | ~az_rd_n) & !za_waitrequest              ),
      .wr_data       ({az_wr_n, az_addr, az_wr_n ? {SDRAM_DQM_WIDTH{1'b0}} : az_be_n, az_data})
   );

genvar i;
generate
if (NUM_CS_ADDR_WIDTH > 0)
begin: g_FifoReadData
   assign {f_rnw, f_cs_n, f_addr, f_dqm, f_data} = fifo_read_data;
   for (i = 0; i <= NUM_CHIPSELECTS-1; i = i + 1)
   begin: g_CsnDecode
      assign csn_decode[i] = cs_n != i;
   end
end
else
begin: g_FifoReadData
   assign {f_rnw, f_addr, f_dqm, f_data} = fifo_read_data;
   assign f_cs_n     = 1'b0;
   assign csn_decode = cs_n;
end
endgenerate

   assign f_select = f_pop & pending;
   assign cs_n = f_select ? f_cs_n : active_cs_n;

generate
if (SDRAM_BANK_WIDTH == 1)
begin: g_ActiveBank
   assign f_bank = f_addr[SDRAM_COL_WIDTH];
end
else
begin: g_ActiveBank
   assign f_bank = {  f_addr[CNTRL_ADDR_WIDTH-NUM_CS_ADDR_WIDTH-1],
                           f_addr[SDRAM_COL_WIDTH]};
end
endgenerate

   // Refresh/init counter
   always @(posedge clk or negedge rst_n)
   begin
      if (rst_n == 0)
         refresh_counter <= POWERUP_DELAY;
      else if (refresh_counter == 0)
         refresh_counter <= REFRESH_PERIOD - 1;
      else
         refresh_counter <= refresh_counter - 1'b1;
   end

   // Refresh request signal
   always @(posedge clk or negedge rst_n)
   begin
      if (rst_n == 0)
         refresh_request <= 0;
      else if (1)
         refresh_request <= ((refresh_counter == 0) | refresh_request) & ~ack_refresh_request & init_done;
   end

   // Generate an Interrupt if two ref_reqs occur before one ack_refresh_request
   always @(posedge clk or negedge rst_n)
   begin
      if (rst_n == 0)
         za_cannotrefresh <= 0;
      else if (1)
         za_cannotrefresh <= (refresh_counter == 0) & refresh_request;
   end

   // initialization-done flag
   always @(posedge clk or negedge rst_n)
   begin
      if (rst_n == 0)
         init_done <= 0;
      else if (1)
         init_done <= init_done | (i_state == I_INIT);
   end

   // ------------------------------------------------------------------------------------------------------------------
   // Init FSM
   // ------------------------------------------------------------------------------------------------------------------
   always @(posedge clk or negedge rst_n)
   begin
      if (rst_n == 0)
      begin
         i_state  <= I_RESET;
         i_next   <= I_RESET;
         i_cmd    <= {{NUM_CHIPSELECTS{1'b1}}, CMD_NOP};
         i_addr   <= {SDRAM_ADDR_WIDTH{1'b1}};
         i_count  <= {TIM_CNT_WIDTH{1'b0}};
         i_refs   <= 3'b0;
         i_req    <= 1'b0;
      end
      else
      begin
         i_addr <= {SDRAM_ADDR_WIDTH{1'b1}};
         case (i_state) // synthesis parallel_case full_case
            I_RESET:
            begin
               i_cmd  <= {{NUM_CHIPSELECTS{1'b1}}, CMD_NOP};
               i_refs <= 3'b0;
               // wait for refresh count-down after reset
               if (refresh_counter == 0) begin
                  i_state <= I_PRECH;
                  i_req   <= 1'b1;
               end
            end 
            I_PRECH:
            begin
               i_req <= 1'b1;
               if (grant == 1'b1) begin
                  i_state  <= I_WAIT;
                  i_cmd    <= {{NUM_CHIPSELECTS{1'b0}}, CMD_PRECHARGE};
                  // initialize the wait counter with the duration of precharge command
                  i_count  <= T_RP;
                  // initialize the next state after the wait command
                  i_next   <= I_ARF;
               end
            end
            I_ARF:
            begin
               i_req    <= 1'b0;
               i_cmd    <= {{NUM_CHIPSELECTS{1'b0}}, CMD_REFRESH};
               i_refs   <= i_refs + 1'b1;
               i_state  <= I_WAIT;
               i_count  <= T_RFC-1;
               // Count up init_refresh_commands
               if (i_refs == INIT_REFRESH-1) begin
                  i_next <= I_LMR;
                  i_req  <= 1'b1;
               end
               else begin
                  i_next <= I_ARF;
               end
            end
            I_WAIT:
            begin
               i_req <= 1'b0;
               i_cmd <= {{NUM_CHIPSELECTS{1'b0}}, CMD_NOP};
               // wait until safe to proceed ...
               if (i_count > 1)
                  i_count <= i_count - 1'b1;
               else
                  i_state <= i_next;
            end
            I_INIT:
            begin
               i_req   <= 1'b0;
               i_state <= I_INIT;
            end
            I_LMR:
            begin
               i_req <= 1'b1;
               if (grant == 1'b1) begin
                  i_state <= I_WAIT;
                  i_cmd   <= {{NUM_CHIPSELECTS{1'b0}}, CMD_LMR};
                  i_addr  <= {{SDRAM_ADDR_WIDTH-10{1'b0}}, 1'b0, 2'b00, {3{CAS_LATENCY}}, 4'h0};
                  i_count <= T_MRD;
                  i_next  <= I_INIT;
               end
            end
            default:
            begin
               i_state <= I_RESET;
               i_req   <= 1'b0;
            end
         endcase // i_state
      end
   end

generate
if (SDRAM_BANK_WIDTH == 1)
begin: g_ActiveBankOne
   assign active_bank = active_addr[SDRAM_COL_WIDTH];
end
else
begin: g_ActiveBankTwo
   assign active_bank = {  active_addr[CNTRL_ADDR_WIDTH-NUM_CS_ADDR_WIDTH-1],
                           active_addr[SDRAM_COL_WIDTH]};
end
endgenerate

   assign csn_match = active_cs_n == f_cs_n;
   assign rnw_match = active_rnw == f_rnw;
   assign bank_match = active_bank == f_bank;
   assign row_match = { active_addr[TOP_ROW_ADDR : BOTTOM_ROW_ADDR] } == 
                      { f_addr     [TOP_ROW_ADDR : BOTTOM_ROW_ADDR] };
   assign pending = csn_match && rnw_match && bank_match && row_match && !f_empty;

   // generates the cas_addr (which is the column address supplied on the address bus)
   // during this time A10 is used as a special function pin and can't act as an address pin
generate
if (SDRAM_COL_WIDTH < 11)
begin: g_CasAddr
   assign cas_addr = f_select ? { {SDRAM_ADDR_WIDTH-SDRAM_COL_WIDTH{1'b0}}, f_addr     [SDRAM_COL_WIDTH-1 : 0] } : 
                                { {SDRAM_ADDR_WIDTH-SDRAM_COL_WIDTH{1'b0}}, active_addr[SDRAM_COL_WIDTH-1 : 0] } ;
end
else
begin: g_CasAddr
   assign cas_addr = f_select ? { {SDRAM_ADDR_WIDTH-SDRAM_COL_WIDTH-1{1'b0}}, f_addr     [SDRAM_COL_WIDTH-1:10], 1'b0, f_addr     [9 : 0] } : 
                                { {SDRAM_ADDR_WIDTH-SDRAM_COL_WIDTH-1{1'b0}}, active_addr[SDRAM_COL_WIDTH-1:10], 1'b0, active_addr[9 : 0] } ;
end
endgenerate

   // ------------------------------------------------------------------------------------------------------------------
   // Main FSM
   // ------------------------------------------------------------------------------------------------------------------
   always @(posedge clk or negedge rst_n)
   begin
      if (rst_n == 0)
      begin
         m_state  <= M_IDLE;
         m_next   <= M_IDLE;
         m_cmd    <= {{NUM_CHIPSELECTS{1'b1}}, CMD_NOP};
         m_bank   <= {SDRAM_BANK_WIDTH{1'b0}};
         m_addr   <= {SDRAM_ADDR_WIDTH{1'b0}};
         m_data   <= {SDRAM_DATA_WIDTH{1'b0}};
         m_dqm    <= {SDRAM_DQM_WIDTH{1'b0}};
         m_count  <= {TIM_CNT_WIDTH{1'b0}};
         ack_refresh_request <= 1'b0;
         f_pop    <= 1'b0;
         oe       <= 1'b0;
         request  <= 1'b0;
      end
      else
      begin
         // force fifo pop to be a single cycle pulse ...
         f_pop    <= 1'b0;
         oe       <= 1'b0;
         request  <= 1'b0;
         case (m_state) // synthesis parallel_case full_case

            // Idle state
            M_IDLE:
            begin
               // wait for init-fsm to be done ...
               if (init_done == 1'b1) begin
                  // hold bus if another cycle ended to arf
                  if (refresh_request == 1'b1) begin
                     m_cmd <= {{NUM_CHIPSELECTS{1'b0}}, CMD_NOP};
                  end else begin
                     m_cmd <= {{NUM_CHIPSELECTS{1'b1}}, CMD_NOP};
                  end
                  ack_refresh_request <= 1'b0;
                  // check if refresh cycle has been requested ...
                  // if yes, go to Precharge State first, then followed by Refresh State
                  if (refresh_request == 1'b1) begin
                     request     <= 1'b1;
                     m_state     <= M_PRE;
                     m_next      <= M_REF;
                     m_count     <= T_RP;
                     active_cs_n <= {NUM_CS_N_WIDTH{1'b1}};
                  // if no refresh cycle requested ...
                  // read/write cycle will be executed if available
                  end else if (f_empty == 1'b0) begin
                     request     <= 1'b1;
                     f_pop       <= 1'b1;
                     active_cs_n <= f_cs_n;
                     active_rnw  <= f_rnw;
                     active_addr <= f_addr;
                     active_data <= f_data;
                     active_dqm  <= f_dqm;
                     m_state     <= M_RAS;
                  end
               // else, if init_done == 1'b0, then we are still in the init phase ...
               // propagate the command & address generated from the init-fsm ...
               // and keep waiting in the IDLE states
               end else begin
                  request  <= i_req;
                  m_addr   <= i_addr;
                  m_cmd    <= i_cmd;
                  m_state  <= M_IDLE;
                  m_next   <= M_IDLE;
               end
            end 

            // activate a row before a Read/Write operation
            M_RAS:
            begin
               // keep the request asserted until grant is achieved and ...
               // continue for the next Read/Write operation
               request <= 1'b1;
               // wait for grant
               if (grant == 1'b1) begin
                  m_state  <= M_WAIT;
                  m_cmd    <= {csn_decode, CMD_ACTIVE};
                  m_bank   <= active_bank;
                  m_addr   <= active_addr[TOP_ROW_ADDR : BOTTOM_ROW_ADDR];
                  m_data   <= active_data;
                  m_dqm    <= active_dqm;
                  m_count  <= T_RCD;
                  m_next   <= active_rnw ? M_RD : M_WR;
               end
            end 

            // Here we drive a No-Operation command to indicate that we still
            // need the bus (cs_n asserted)
            M_WAIT:
            begin
               // maintain the previous value of request
               request <= request;
               // precharge all if Auto Refresh, else precharge csn_decode
               if (m_next == M_REF) begin
                  m_cmd <= {{NUM_CHIPSELECTS{1'b0}}, CMD_NOP};
               end else begin
                  m_cmd <= {csn_decode, CMD_NOP};
               end
               // count down til safe to proceed ...
               if (m_count > 1) begin
                  m_count <= m_count - 1'b1;
               end else begin
                  m_state <= m_next;
               end
            end 

            M_RD:
            begin
               request  <= 1'b1;
               m_cmd    <= {csn_decode, CMD_READ};
               m_bank   <= f_select ? f_bank : active_bank;
               m_dqm    <= f_select ? f_dqm  : active_dqm;
               m_addr   <= cas_addr;
               // do we have a transaction pending?
               if (pending)
               begin
                  // if we need to Auto Refresh, bail, else spin
                  if (refresh_request)
                  begin
                     m_state  <= M_WAIT;
                     m_next   <= M_IDLE;
                     m_count  <= RD_LATENCY - 1;
                  end
                  else
                  begin
                     f_pop       <= 1'b1;
                     active_cs_n <= f_cs_n;
                     active_rnw  <= f_rnw;
                     active_addr <= f_addr;
                     active_data <= f_data;
                     active_dqm  <= f_dqm;
                  end
               end
               else 
               begin
                  // correctly end RD spin cycle if fifo empty
                  if (~pending & f_pop) begin
                     m_cmd <= {csn_decode, CMD_NOP};
                  end
                  if (TRISTATE_EN == 0)
                  begin
                     m_state  <= M_OPEN;
                  end
                  else
                  begin
                     m_state  <= M_WAIT;
                     m_next   <= M_OPEN;
                     m_count  <= RD_LATENCY - 1;
                  end
               end
            end 
          
            M_WR:
            begin
               request  <= 1'b1;
               m_cmd    <= {csn_decode, CMD_WRITE};
               oe       <= 1'b1;
               m_data   <= f_select ? f_data : active_data;
               m_dqm    <= f_select ? f_dqm  : active_dqm;
               m_bank   <= f_select ? f_bank : active_bank;
               m_addr   <= cas_addr;
               // do we have a transaction pending?
               if (pending)
               begin
                  // if we need to do Auto Refresh, bail, else spin
                  if (refresh_request)
                  begin
                     m_state  <= M_WAIT;
                     m_next   <= M_IDLE;
                     m_count  <= T_WR;
                  end
                  else 
                  begin
                     f_pop       <= 1'b1;
                     active_cs_n <= f_cs_n;
                     active_rnw  <= f_rnw;
                     active_addr <= f_addr;
                     active_data <= f_data;
                     active_dqm  <= f_dqm;
                  end
               end
               else
               begin
                  // correctly end WR spin cycle if fifo empty
                  if (~pending & f_pop)
                  begin
                     m_cmd <= {csn_decode, CMD_NOP};
                     oe <= 1'b0;
                  end
                  m_state <= M_OPEN;
               end
            end 

            // Recover from RD or WR before going to PRECHARGE
            // In essence, a special type of M_WAIT state
            // Here we drive a No Operation command to indicate that we
            // still need the bus (cs_n asserted)
            M_REC:
            begin
               m_cmd <= {csn_decode, CMD_NOP};
               // count down until safe to proceed ...
               if (m_count > 1)
                  m_count <= m_count - 1'b1;
               else 
               begin
                  request <= 1'b1;
                  m_state <= M_PRE;
                  m_count <= T_RP;
               end
            end 

            // Issue a Precharge command
            // You must assign m_next/m_count before entering this
            // since after this state is state M_WAIT which uses the values m_next/m_count
            M_PRE:
            begin
               request <= 1'b1;
               if (grant == 1'b1) begin
                  m_state <= M_WAIT;
                  m_addr  <= {SDRAM_ADDR_WIDTH{1'b1}};
                  // precharge all if Auto Refresh, else precharge csn_decode
                  if (refresh_request)
                     m_cmd <= {{NUM_CHIPSELECTS{1'b0}}, CMD_PRECHARGE};
                  else
                     m_cmd <= {csn_decode, CMD_PRECHARGE};
               end
            end 

            // Issue an Auto Refresh command
            M_REF:
            begin
               ack_refresh_request <= 1'b1;
               m_state  <= M_WAIT;
               m_cmd    <= {{NUM_CHIPSELECTS{1'b0}}, CMD_REFRESH};
               m_count  <= T_RFC-1;
               m_next   <= M_IDLE;
            end 
          
            M_OPEN:
            begin
               // figure out if we need to close/re-open a row
               m_cmd <= {csn_decode, CMD_NOP};
               // if we need to do Auto Refresh, bail, else spin
               if (refresh_request)
               begin
                  if (MAX_REC_TIME > 0)
                  begin
                     m_state  <= M_WAIT;
                     m_next   <= M_IDLE;
                     m_count  <= MAX_REC_TIME;
                  end
                  else
                  begin
                     m_state  <= M_IDLE;
                  end
               end
               // determine one of 3 basic outcomes:
               // if fifo is simply empty, wait for it
               // Can't easily: if fifo is same row&bank,
               //      but different r/w sense, recover and switch sense
               // if fifo is different row|bank, precharge => idle
               else // wait for fifo to have contents
               begin
                  if (!f_empty)
                  begin
                     // are we 'pending' yet?
                     if (csn_match && rnw_match && bank_match && row_match)
                     begin
                        // if matched ...
                        // go back where you came from:
                        m_state     <= f_rnw ? M_RD : M_WR;
                        f_pop       <= 1'b1;
                        active_cs_n <= f_cs_n;
                        active_rnw  <= f_rnw;
                        active_addr <= f_addr;
                        active_data <= f_data;
                        active_dqm  <= f_dqm;
                     end
                     else 
                     begin
                        if (MAX_REC_TIME > 0)
                        begin
                           m_state  <= M_REC;
                           m_next   <= M_IDLE;
                           m_count  <= MAX_REC_TIME;
                        end
                        else
                        begin
                           request  <= 1'b1;
                           m_state  <= M_PRE;
                           m_next   <= M_IDLE;
                           m_count  <= T_RP;
                        end
                     end
                  end
               end
            end 
          
         endcase // m_state

      end
   end

   // asserts rd_strobe each time a READ Command is issued
   assign rd_strobe = m_cmd[2 : 0] == CMD_READ;

generate
if (RD_LATENCY > 1)
begin: g_RdValid
   // track RD req's based on cas_latency w/shift reg
   always @(posedge clk or negedge rst_n)
   begin
      if (rst_n == 0)
         rd_valid <= {RD_LATENCY{1'b0}};
      else
         rd_valid <= (rd_valid << 1) | { {RD_LATENCY-1{1'b0}}, rd_strobe };
   end
end
else
begin: g_RdValid
   // track RD Req's based on cas_latency w/shift reg
   always @(posedge clk or negedge rst_n)
   begin
      if (rst_n == 0)
         rd_valid <= 1'b0;
      else
         rd_valid <= rd_strobe;
   end
end
endgenerate

   assign dq = TRISTATE_EN ? sdram_dq_in : sdram_dq;
   // register dq data
   always @(posedge clk or negedge rst_n)
   begin
      if (rst_n == 0)
         za_data <= 0;
      else
         za_data <= dq;
   end

   // delay za_valid to match registered data
   always @(posedge clk or negedge rst_n)
   begin
      if (rst_n == 0)
         za_valid <= 0;
      else if (1)
         za_valid <= rd_valid[RD_LATENCY- 1];
   end

endmodule
