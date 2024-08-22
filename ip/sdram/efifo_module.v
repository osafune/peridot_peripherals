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

module efifo_module
   #(
      parameter                           DATA_WIDTH = 16,
      parameter                           DEPTH = 2
   )(
                                                                  // inputs:
                                                                   clk,
                                                                   rd,
                                                                   rst_n,
                                                                   wr,
                                                                   wr_data,

                                                                  // outputs:
                                                                   almost_empty,
                                                                   almost_full,
                                                                   empty,
                                                                   full,
                                                                   rd_data
                                                                )
;

  output                         almost_empty;
  output                         almost_full;
  output                         empty;
  output                         full;
  output  [ DATA_WIDTH - 1 : 0 ] rd_data;
  input                          clk;
  input                          rd;
  input                          rst_n;
  input                          wr;
  input   [ DATA_WIDTH - 1 : 0 ] wr_data;

  wire             almost_empty;
  wire             almost_full;
  wire             empty;
  reg     [      DEPTH - 1 : 0 ] entries;
  reg     [ DATA_WIDTH - 1 : 0 ] entry_0;
  reg     [ DATA_WIDTH - 1 : 0 ] entry_1;
  wire             full;
  reg              rd_address;
  reg     [ DATA_WIDTH - 1 : 0 ] rd_data;
  wire    [  1: 0] rdwr;
  reg              wr_address;
  assign rdwr = {rd, wr};
  assign full = entries == DEPTH;
  assign almost_full = entries >= DEPTH - 1;
  assign empty = entries == 0;
  assign almost_empty = entries <= DEPTH - 1;
  always @(entry_0 or entry_1 or rd_address)
    begin
      case (rd_address) // synthesis parallel_case full_case
      
          1'd0: begin
              rd_data = entry_0;
          end // 1'd0 
      
          1'd1: begin
              rd_data = entry_1;
          end // 1'd1 
      
          default: begin
          end // default
      
      endcase // rd_address
    end


  always @(posedge clk or negedge rst_n)
    begin
      if (rst_n == 0)
        begin
          wr_address <= 0;
          rd_address <= 0;
          entries <= 0;
        end
      else 
        case (rdwr) // synthesis parallel_case full_case
        
            2'd1: begin
                // Write data
                if (!full)
                  begin
                    entries <= entries + 1;
                    wr_address <= (wr_address == 1) ? 0 : (wr_address + 1);
                  end
            end // 2'd1 
        
            2'd2: begin
                // Read data
                if (!empty)
                  begin
                    entries <= entries - 1;
                    rd_address <= (rd_address == 1) ? 0 : (rd_address + 1);
                  end
            end // 2'd2 
        
            2'd3: begin
                wr_address <= (wr_address == 1) ? 0 : (wr_address + 1);
                rd_address <= (rd_address == 1) ? 0 : (rd_address + 1);
            end // 2'd3 
        
            default: begin
            end // default
        
        endcase // rdwr
    end


  always @(posedge clk)
    begin
      //Write data
      if (wr & !full)
          case (wr_address) // synthesis parallel_case full_case
          
              1'd0: begin
                  entry_0 <= wr_data;
              end // 1'd0 
          
              1'd1: begin
                  entry_1 <= wr_data;
              end // 1'd1 
          
              default: begin
              end // default
          
          endcase // wr_address
    end



endmodule


