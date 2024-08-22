# (C) 2001-2020 Intel Corporation. All rights reserved.
# Your use of Intel Corporation's design tools, logic functions and other 
# software and tools, and its AMPP partner logic functions, and any output 
# files from any of the foregoing (including device programming or simulation 
# files), and any associated documentation or information are expressly subject 
# to the terms and conditions of the Intel Program License Subscription 
# Agreement, Intel FPGA IP License Agreement, or other applicable 
# license agreement, including, without limitation, that your use is for the 
# sole purpose of programming logic devices manufactured by Intel and sold by 
# Intel or its authorized distributors.  Please refer to the applicable 
# agreement for further details.


package require -exact qsys 13.1
source $env(QUARTUS_ROOTDIR)/../ip/altera/sopc_builder_ip/common/embedded_ip_hwtcl_common.tcl

#-------------------------------------------------------------------------------
# module properties
#-------------------------------------------------------------------------------

set_module_property DESCRIPTION                    "Altera SDRAM Tri-State Controller"
set_module_property NAME                           altera_sdram_tri_controller
set_module_property VERSION                        20.1
set_module_property INTERNAL                       false
set_module_property HIDE_FROM_QUARTUS              true
set_module_property OPAQUE_ADDRESS_MAP             true
set_module_property GROUP                          "Memory Interfaces and Controllers/SDRAM"
set_module_property AUTHOR                         "Intel Corporation"
set_module_property DISPLAY_NAME                   "SDRAM Tri-State Controller Intel FPGA IP"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE   true
set_module_property EDITABLE                       true
set_module_property ANALYZE_HDL                    false
set_module_property REPORT_TO_TALKBACK             false
set_module_property ALLOW_GREYBOX_GENERATION       false
set_module_property ELABORATION_CALLBACK           elaboration
set_module_property VALIDATION_CALLBACK            validation

# 
# file sets
# 
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL altera_sdram_tri_controller
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
add_fileset_file altera_sdram_tri_controller.v VERILOG PATH altera_sdram_tri_controller.v TOP_LEVEL_FILE
add_fileset_file efifo_module.v VERILOG PATH efifo_module.v

add_fileset SIM_VERILOG SIM_VERILOG "" ""
set_fileset_property SIM_VERILOG TOP_LEVEL altera_sdram_tri_controller
set_fileset_property SIM_VERILOG ENABLE_RELATIVE_INCLUDE_PATHS false
add_fileset_file altera_sdram_tri_controller.v VERILOG PATH altera_sdram_tri_controller.v TOP_LEVEL_FILE
add_fileset_file efifo_module.v VERILOG PATH efifo_module.v

# 
# documentation links
# 
add_documentation_link {Data Sheet } http://www.altera.com/literature/hb/nios2/n2cpu_nii51005.pdf


#-------------------------------------------------------------------------------
# module parameters
#-------------------------------------------------------------------------------

add_parameter TAC FLOAT
set_parameter_property TAC DEFAULT_VALUE           5.5
set_parameter_property TAC DISPLAY_NAME            "Access time (t_ac)"
set_parameter_property TAC UNITS                   Nanoseconds
set_parameter_property TAC DESCRIPTION "Access time"
set_parameter_property TAC ALLOWED_RANGES          0.0:999.0
set_parameter_property TAC HDL_PARAMETER           false

add_parameter TRCD FLOAT
set_parameter_property TRCD DEFAULT_VALUE          20.0
set_parameter_property TRCD DISPLAY_NAME           "ACTIVE to READ or WRITE delay (t_rcd)"
set_parameter_property TRCD TYPE                   FLOAT
set_parameter_property TRCD DESCRIPTION "ACTIVE to READ or WRITE delay"
set_parameter_property TRCD UNITS                  Nanoseconds
set_parameter_property TRCD ALLOWED_RANGES         0.0:200.0
set_parameter_property TRCD HDL_PARAMETER          false

add_parameter TRFC FLOAT
set_parameter_property TRFC DEFAULT_VALUE          70.0
set_parameter_property TRFC DISPLAY_NAME           "Duration of refresh command (t_rfc)"
set_parameter_property TRFC TYPE                   FLOAT
set_parameter_property TRFC DESCRIPTION "Duration of refresh command"
set_parameter_property TRFC UNITS                  Nanoseconds
set_parameter_property TRFC ALLOWED_RANGES         0.0:700.0
set_parameter_property TRFC HDL_PARAMETER          false

add_parameter TRP FLOAT 
set_parameter_property TRP DEFAULT_VALUE           20.0
set_parameter_property TRP DISPLAY_NAME            "Duration of precharge command (t_rp)"
set_parameter_property TRP TYPE                    FLOAT
set_parameter_property TRP DESCRIPTION "Duration of precharge command"
set_parameter_property TRP UNITS                   Nanoseconds
set_parameter_property TRP ALLOWED_RANGES          0.0:200.0
set_parameter_property TRP HDL_PARAMETER           false

add_parameter TWR FLOAT 
set_parameter_property TWR DEFAULT_VALUE           14.0
set_parameter_property TWR DISPLAY_NAME            "Write recovery time (t_wr, no auto precharge)"
set_parameter_property TWR TYPE                    FLOAT
set_parameter_property TWR DESCRIPTION "Write recovery time"
set_parameter_property TWR UNITS                   Nanoseconds
set_parameter_property TWR ALLOWED_RANGES          0.0:140.0
set_parameter_property TWR HDL_PARAMETER           false

add_parameter CAS_LATENCY INTEGER
set_parameter_property CAS_LATENCY DEFAULT_VALUE         3
set_parameter_property CAS_LATENCY DISPLAY_NAME          "CAS latency cycles"
set_parameter_property CAS_LATENCY TYPE                  INTEGER
set_parameter_property CAS_LATENCY DESCRIPTION "CAS latency cycles"
set_parameter_property CAS_LATENCY UNITS                 None
set_parameter_property CAS_LATENCY ALLOWED_RANGES        {1 2 3}
set_parameter_property CAS_LATENCY HDL_PARAMETER         true

add_parameter SDRAM_COL_WIDTH INTEGER
set_parameter_property SDRAM_COL_WIDTH DEFAULT_VALUE     8
set_parameter_property SDRAM_COL_WIDTH DISPLAY_NAME      "Column"
set_parameter_property SDRAM_COL_WIDTH TYPE              INTEGER
set_parameter_property SDRAM_COL_WIDTH DESCRIPTION "Column width"
set_parameter_property SDRAM_COL_WIDTH UNITS             None
set_parameter_property SDRAM_COL_WIDTH ALLOWED_RANGES    8:14
set_parameter_property SDRAM_COL_WIDTH HDL_PARAMETER     true

add_parameter SDRAM_DATA_WIDTH INTEGER
set_parameter_property SDRAM_DATA_WIDTH DEFAULT_VALUE    32
set_parameter_property SDRAM_DATA_WIDTH DISPLAY_NAME     Bits
set_parameter_property SDRAM_DATA_WIDTH TYPE             INTEGER
set_parameter_property SDRAM_DATA_WIDTH DESCRIPTION "Data width"
set_parameter_property SDRAM_DATA_WIDTH UNITS            None
set_parameter_property SDRAM_DATA_WIDTH ALLOWED_RANGES   {8 16 32 64}
set_parameter_property SDRAM_DATA_WIDTH HDL_PARAMETER    true

add_parameter generateSimulationModel BOOLEAN
set_parameter_property generateSimulationModel DEFAULT_VALUE {false}
set_parameter_property generateSimulationModel DISPLAY_NAME {Include a functional memory model in the system testbench}
set_parameter_property generateSimulationModel DESCRIPTION "Generate of simulation model"
set_parameter_property generateSimulationModel HDL_PARAMETER {0}

add_parameter INIT_REFRESH INTEGER
set_parameter_property INIT_REFRESH DEFAULT_VALUE        2
set_parameter_property INIT_REFRESH DISPLAY_NAME         "Initialization refresh cycles"
set_parameter_property INIT_REFRESH TYPE                 INTEGER
set_parameter_property INIT_REFRESH DESCRIPTION "Initialization refresh cycles"
set_parameter_property INIT_REFRESH UNITS                None
set_parameter_property INIT_REFRESH ALLOWED_RANGES       1:8
set_parameter_property INIT_REFRESH HDL_PARAMETER        true

# unused preset parameter: model
add_parameter model STRING
set_parameter_property model DEFAULT_VALUE               {single_Micron_MT48LC4M32B2_7_chip}
set_parameter_property model DISPLAY_NAME                {model}
set_parameter_property model ALLOWED_RANGES              {custom Micron_MT8LSDT1664HG_module Four_SDR100_8MByte_x16_chips single_Micron_MT48LC2M32B2_7_chip single_Micron_MT48LC4M32B2_7_chip single_NEC_D4564163_A80_chip_64Mb_x_16 single_Alliance_AS4LC1M16S1_10_chip single_Alliance_AS4LC2M8S0_10_chip}
set_parameter_property model HDL_PARAMETER               false
set_parameter_property model VISIBLE                     false

add_parameter numberOfBanks INTEGER
set_parameter_property numberOfBanks DEFAULT_VALUE       4
set_parameter_property numberOfBanks DISPLAY_NAME        "Banks"
set_parameter_property numberOfBanks TYPE                INTEGER
set_parameter_property numberOfBanks DESCRIPTION "Number of banks"
set_parameter_property numberOfBanks UNITS               None
set_parameter_property numberOfBanks ALLOWED_RANGES      {2 4}
set_parameter_property numberOfBanks HDL_PARAMETER       false

add_parameter NUM_CHIPSELECTS INTEGER
set_parameter_property NUM_CHIPSELECTS DEFAULT_VALUE     1
set_parameter_property NUM_CHIPSELECTS DISPLAY_NAME      "Chip select"
set_parameter_property NUM_CHIPSELECTS TYPE              INTEGER
set_parameter_property NUM_CHIPSELECTS DESCRIPTION "Number of chip select"
set_parameter_property NUM_CHIPSELECTS UNITS             None
set_parameter_property NUM_CHIPSELECTS ALLOWED_RANGES    {1 2 4 8}
set_parameter_property NUM_CHIPSELECTS HDL_PARAMETER     true

add_parameter TRISTATE_EN BOOLEAN
set_parameter_property TRISTATE_EN DEFAULT_VALUE         true
set_parameter_property TRISTATE_EN DISPLAY_NAME          "Controller shares dq/dqm/addr I/O pins"
set_parameter_property TRISTATE_EN TYPE                  BOOLEAN
set_parameter_property TRISTATE_EN DESCRIPTION "Enable the tri state"
set_parameter_property TRISTATE_EN UNITS                 None
set_parameter_property TRISTATE_EN HDL_PARAMETER         true
set_parameter_property TRISTATE_EN VISIBLE               false

add_parameter powerUpDelay FLOAT
set_parameter_property powerUpDelay DEFAULT_VALUE        100.0
set_parameter_property powerUpDelay DISPLAY_NAME         "Delay after powerup, before initialization"
set_parameter_property powerUpDelay TYPE                 FLOAT
set_parameter_property powerUpDelay DESCRIPTION "Delay after powerup before initialization"
set_parameter_property powerUpDelay UNITS                Microseconds
set_parameter_property powerUpDelay ALLOWED_RANGES       0.0:999.0
set_parameter_property powerUpDelay HDL_PARAMETER        false

add_parameter refreshPeriod FLOAT
set_parameter_property refreshPeriod DEFAULT_VALUE       15.625
set_parameter_property refreshPeriod DISPLAY_NAME        "Issue one refresh command every"
set_parameter_property refreshPeriod UNITS               Microseconds
set_parameter_property refreshPeriod DESCRIPTION "Issue one refresh command for every cycle"
set_parameter_property refreshPeriod ALLOWED_RANGES      0.0:156.25
set_parameter_property refreshPeriod HDL_PARAMETER       false

add_parameter SDRAM_ROW_WIDTH INTEGER
set_parameter_property SDRAM_ROW_WIDTH DEFAULT_VALUE        12
set_parameter_property SDRAM_ROW_WIDTH DISPLAY_NAME         "Row"
set_parameter_property SDRAM_ROW_WIDTH TYPE                 INTEGER
set_parameter_property SDRAM_ROW_WIDTH DESCRIPTION "Row width"
set_parameter_property SDRAM_ROW_WIDTH UNITS                None
set_parameter_property SDRAM_ROW_WIDTH ALLOWED_RANGES       11:14
set_parameter_property SDRAM_ROW_WIDTH HDL_PARAMETER        true

# system info parameters
add_parameter clockRate LONG
set_parameter_property clockRate DEFAULT_VALUE {50000000}
set_parameter_property clockRate DISPLAY_NAME {clockRate}
set_parameter_property clockRate AFFECTS_GENERATION {1}
set_parameter_property clockRate HDL_PARAMETER {0}
set_parameter_property clockRate SYSTEM_INFO {clock_rate clock_sink}
set_parameter_property clockRate SYSTEM_INFO_TYPE {CLOCK_RATE}
set_parameter_property clockRate SYSTEM_INFO_ARG {clock_sink}
set_parameter_property clockRate VISIBLE {false}

add_parameter componentName STRING
set_parameter_property componentName DISPLAY_NAME {componentName}
set_parameter_property componentName VISIBLE {0}
set_parameter_property componentName AFFECTS_GENERATION {1}
set_parameter_property componentName HDL_PARAMETER {0}
set_parameter_property componentName SYSTEM_INFO {unique_id}
set_parameter_property componentName SYSTEM_INFO_TYPE {UNIQUE_ID}


#-------------------------------------------------------------------------------
# derived parameters
#-------------------------------------------------------------------------------

add_parameter T_RCD INTEGER
set_parameter_property T_RCD DEFAULT_VALUE         2
set_parameter_property T_RCD DISPLAY_NAME          "t_rcd / clock_period "
set_parameter_property T_RCD TYPE                  INTEGER
set_parameter_property T_RCD UNITS                 None
set_parameter_property T_RCD DERIVED               true
set_parameter_property T_RCD ALLOWED_RANGES        0:20
set_parameter_property T_RCD HDL_PARAMETER         true
set_parameter_property T_RCD VISIBLE               false

add_parameter T_RFC INTEGER
set_parameter_property T_RFC DEFAULT_VALUE         7
set_parameter_property T_RFC DISPLAY_NAME          "t_rfc / clock_period "
set_parameter_property T_RFC TYPE                  INTEGER
set_parameter_property T_RFC UNITS                 None
set_parameter_property T_RFC DERIVED               true
set_parameter_property T_RFC ALLOWED_RANGES        0:70
set_parameter_property T_RFC HDL_PARAMETER         true
set_parameter_property T_RFC VISIBLE               false

add_parameter T_RP INTEGER
set_parameter_property T_RP DEFAULT_VALUE          2
set_parameter_property T_RP DISPLAY_NAME           "t_rp / clock_period "
set_parameter_property T_RP TYPE                   INTEGER
set_parameter_property T_RP UNITS                  None
set_parameter_property T_RP DERIVED                true
set_parameter_property T_RP ALLOWED_RANGES         0:20
set_parameter_property T_RP HDL_PARAMETER          true
set_parameter_property T_RP VISIBLE                false

add_parameter T_WR INTEGER
set_parameter_property T_WR DEFAULT_VALUE          2
set_parameter_property T_WR DISPLAY_NAME           "t_wr / clock_period"
set_parameter_property T_WR TYPE                   INTEGER
set_parameter_property T_WR UNITS                  None
set_parameter_property T_WR DERIVED                true
set_parameter_property T_WR ALLOWED_RANGES         0:14
set_parameter_property T_WR HDL_PARAMETER          true
set_parameter_property T_WR VISIBLE                false

add_parameter SDRAM_BANK_WIDTH INTEGER
set_parameter_property SDRAM_BANK_WIDTH DEFAULT_VALUE    2
set_parameter_property SDRAM_BANK_WIDTH DISPLAY_NAME     "Width of SDRAM bank address bit"
set_parameter_property SDRAM_BANK_WIDTH TYPE             INTEGER
set_parameter_property SDRAM_BANK_WIDTH UNITS            None
set_parameter_property SDRAM_BANK_WIDTH DERIVED          true
set_parameter_property SDRAM_BANK_WIDTH ALLOWED_RANGES   {1 2}
set_parameter_property SDRAM_BANK_WIDTH HDL_PARAMETER    true
set_parameter_property SDRAM_BANK_WIDTH VISIBLE          false

add_parameter POWERUP_DELAY INTEGER
set_parameter_property POWERUP_DELAY DEFAULT_VALUE       10000
set_parameter_property POWERUP_DELAY DISPLAY_NAME        "Delay after powerup / clock_period"
set_parameter_property POWERUP_DELAY TYPE                INTEGER
set_parameter_property POWERUP_DELAY UNITS               None
set_parameter_property POWERUP_DELAY DERIVED             true
set_parameter_property POWERUP_DELAY ALLOWED_RANGES      0:100000
set_parameter_property POWERUP_DELAY HDL_PARAMETER       true
set_parameter_property POWERUP_DELAY VISIBLE             false

add_parameter REFRESH_PERIOD INTEGER
set_parameter_property REFRESH_PERIOD DEFAULT_VALUE      1563
set_parameter_property REFRESH_PERIOD DISPLAY_NAME       "Refresh period / clock_period"
set_parameter_property REFRESH_PERIOD TYPE               INTEGER
set_parameter_property REFRESH_PERIOD UNITS              None
set_parameter_property REFRESH_PERIOD DERIVED            true
set_parameter_property REFRESH_PERIOD ALLOWED_RANGES     0:15630
set_parameter_property REFRESH_PERIOD HDL_PARAMETER      true
set_parameter_property REFRESH_PERIOD VISIBLE            false

add_parameter size LONG
set_parameter_property size DEFAULT_VALUE                0
set_parameter_property size DISPLAY_NAME                 "size"
set_parameter_property size DERIVED                      true
set_parameter_property size HDL_PARAMETER                false
set_parameter_property size VISIBLE                      false

add_parameter CNTRL_ADDR_WIDTH INTEGER 
set_parameter_property CNTRL_ADDR_WIDTH DEFAULT_VALUE    22
set_parameter_property CNTRL_ADDR_WIDTH DISPLAY_NAME     "Controller Address Width"
set_parameter_property CNTRL_ADDR_WIDTH TYPE             INTEGER
set_parameter_property CNTRL_ADDR_WIDTH UNITS            None
set_parameter_property CNTRL_ADDR_WIDTH DERIVED          true
set_parameter_property CNTRL_ADDR_WIDTH ALLOWED_RANGES   0:32
set_parameter_property CNTRL_ADDR_WIDTH HDL_PARAMETER    true
set_parameter_property CNTRL_ADDR_WIDTH VISIBLE          false

add_parameter MAX_REC_TIME INTEGER
set_parameter_property MAX_REC_TIME DEFAULT_VALUE        1
set_parameter_property MAX_REC_TIME DISPLAY_NAME         "Maximum Recovery Time"
set_parameter_property MAX_REC_TIME TYPE                 INTEGER
set_parameter_property MAX_REC_TIME UNITS                None
set_parameter_property MAX_REC_TIME DERIVED              true
set_parameter_property MAX_REC_TIME ALLOWED_RANGES       -2147483648:2147483647
set_parameter_property MAX_REC_TIME HDL_PARAMETER        true
set_parameter_property MAX_REC_TIME VISIBLE              false


#-------------------------------------------------------------------------------
# module GUI
#-------------------------------------------------------------------------------

# display group
add_display_item {} {Memory Profile} GROUP tab

# group parameter
add_display_item {Memory Profile} {Data Width} GROUP
add_display_item {Data Width} SDRAM_DATA_WIDTH PARAMETER

add_display_item {Memory Profile} {Architecture} GROUP
add_display_item {Architecture} NUM_CHIPSELECTS PARAMETER
add_display_item {Architecture} numberOfBanks PARAMETER

add_display_item {Memory Profile} {Address Width} GROUP
add_display_item {Address Width} SDRAM_ROW_WIDTH PARAMETER
add_display_item {Address Width} SDRAM_COL_WIDTH PARAMETER

add_display_item {Memory Profile} {Generic Memory model (simulation only)} GROUP
add_display_item {Generic Memory model (simulation only)} generateSimulationModel PARAMETER

add_display_item {Memory Profile} sdramSizeDisplay TEXT ""

add_display_item {} {Timing} GROUP tab

add_display_item {Timing} CAS_LATENCY PARAMETER
set_display_item_property CAS_LATENCY DISPLAY_HINT radio
add_display_item {Timing} INIT_REFRESH PARAMETER
add_display_item {Timing} refreshPeriod PARAMETER
add_display_item {Timing} powerUpDelay PARAMETER
add_display_item {Timing} TRFC PARAMETER
add_display_item {Timing} TRP PARAMETER
add_display_item {Timing} TRCD PARAMETER
add_display_item {Timing} TAC PARAMETER
add_display_item {Timing} TWR PARAMETER


#-------------------------------------------------------------------------------
# validation
#-------------------------------------------------------------------------------

proc proc_calculateNanoSecondPerCAS { casLatency } {
    set clockRate [ get_parameter_value clockRate ]
    if { $clockRate > 0 } {
        set clockperiod [ expr { pow(10,9)/$clockRate } ]
        return [ expr { $clockperiod * $casLatency } ]
    } else {
        send_message error "Unknown input clock frequency."
        return 0
    }
}

proc proc_max { x y z } { 
   set int_result [ expr { $x > $y ? $x : $y } ]
   if { $int_result > $z } {
      return $int_result
   } else {
      return $z
   }
}

proc validation {} {

   # module parameters
   set TRCD             [ get_parameter_value TRCD             ]
   set TRFC             [ get_parameter_value TRFC             ]
   set TRP              [ get_parameter_value TRP              ]
   set TWR              [ get_parameter_value TWR              ]
   set numberOfBanks    [ get_parameter_value numberOfBanks    ]
   set powerUpDelay     [ get_parameter_value powerUpDelay     ]
   set refreshPeriod    [ get_parameter_value refreshPeriod    ]
   set SDRAM_DATA_WIDTH [ get_parameter_value SDRAM_DATA_WIDTH ]
   set clockRate        [ get_parameter_value clockRate        ]
   set SDRAM_ROW_WIDTH  [ get_parameter_value SDRAM_ROW_WIDTH  ]
   set SDRAM_COL_WIDTH  [ get_parameter_value SDRAM_COL_WIDTH  ]
   set NUM_CHIPSELECTS	[ get_parameter_value NUM_CHIPSELECTS  ]
   set INIT_REFRESH     [ get_parameter_value INIT_REFRESH     ]
   set CAS_LATENCY      [ get_parameter_value CAS_LATENCY      ]
   set TAC              [ get_parameter_value TAC              ]

   # calculate clock period in nanosecond
   set clockperiod      [ expr { pow(10,9)/$clockRate }              ]
   
   # calculate derived parameters
   set T_RCD            [ expr { $TRCD/$clockperiod }                ]
   set T_RFC            [ expr { $TRFC/$clockperiod }                ]
   set T_RP             [ expr { $TRP/$clockperiod  }                ]
   set T_WR             [ expr { $TWR/$clockperiod  }                ]
   set POWERUP_DELAY    [ expr { $powerUpDelay*1000/$clockperiod }   ]
   set REFRESH_PERIOD   [ expr { $refreshPeriod*1000/$clockperiod }  ]
   
   # Added by SH
   set D_NUMBANKBITS     [ log2ceil $numberOfBanks                    ]
   set D_NUM_CHIPSELECTS [ log2ceil $NUM_CHIPSELECTS                  ]
   set D_ADDR_WIDTH		 [ expr {$SDRAM_ROW_WIDTH + $SDRAM_COL_WIDTH + $D_NUM_CHIPSELECTS + $D_NUMBANKBITS} ]  
   
	# calculate RAM size
	set memSizeInBits    [ expr {[expr 1<<$D_ADDR_WIDTH] * $SDRAM_DATA_WIDTH} ] 
	set MemSizeInBytes   [ expr {$memSizeInBits/8} ]
	set size             $MemSizeInBytes

	# Update SDRAM memory size on GUI display according to user setting
	set sizeInBytes $size
	set sizeInBits [ expr {$sizeInBytes * 8} ]
	
	#send_message info "memSizeInBits = $memSizeInBits, sizeInBytes = $sizeInBytes, D_ADDR_WIDTH = $D_ADDR_WIDTH"
	
	set SDRAM_TABLE "<html><table border=\"0\" width=\"100%\">
	            <tr><td valign=\"top\"><font size=3><b>Memory Size =</b></td>
	            <td valign=\"top\"><font size=3><b>[expr {$sizeInBytes/1048576}] MBytes</font></b><br><b>[expr {$sizeInBits/$SDRAM_DATA_WIDTH}] x $SDRAM_DATA_WIDTH<br>[expr {$sizeInBits/1048576}] MBits</b></td>
	            </tr></table></html>"
	set_display_item_property sdramSizeDisplay TEXT $SDRAM_TABLE

   # validate Bad Row
   if { $SDRAM_ROW_WIDTH < 11 || $SDRAM_ROW_WIDTH > 14 } {
      send_message error "Invalid row width. Row width should be between 11 and 14."
   }
   # validate Bad Col
   if { $SDRAM_COL_WIDTH < 8 || $SDRAM_COL_WIDTH >= $SDRAM_ROW_WIDTH } {
      send_message error "Invalid column width. Column width should be more than 8 and less than row width."
   }
   # validate init refresh
   if { $INIT_REFRESH < 1 || $INIT_REFRESH > 8 } {
      send_message error "Only integral numbers of refreshes between 1 and 8 are supported."
   }
   # validate refresh period
   if { $refreshPeriod >= 156.25 } {
      send_message error "Invalid refresh period (must be < 156.26)."
   }
   # validate power up delay
   if { $powerUpDelay >= 1000 } {
      send_message error "Invalid powerup delay (must be < 1000)."
   }
   # validate TRFC delay
   if { $TRFC >= 700 } {
      send_message error "Invalid refresh command duration t_rfc (must be < 700)."
   }
   # validate TRP delay
   if { $TRP >= 200 } {
      send_message error "Invalid precharge command period t_rp (must be < 200)."
   }
   # validate TRCD delay
   if { $TRCD >= 200 } {
      send_message error "Invalid active to read or write delay t_rcd (must be < 200)."
   }
   # validate TAC
   set nanoSecondsPerCAS [ proc_calculateNanoSecondPerCAS $CAS_LATENCY ]
   if { $nanoSecondsPerCAS == 0 } {
      send_message error "Calculated CAS latency is 0 ns."
   }
   if { $TAC >= $nanoSecondsPerCAS } {
      send_message error "Invalid access time t_ac (must be < $nanoSecondsPerCAS ns)."
   }
   # validate TWR
   if { $TWR >= 140 } {
      send_message error "Invalid non-auto precharge time (must be < 140)."
   }   
   
   send_message info "Altera SDRAM Tri-State Controller will only be supported in Quartus Prime Standard Edition in the future release."

   # update the derived parameters
   set_parameter_value T_RCD              $T_RCD
   set_parameter_value T_RFC              $T_RFC
   set_parameter_value T_RP               $T_RP
   set_parameter_value T_WR               $T_WR
   set_parameter_value SDRAM_BANK_WIDTH   $D_NUMBANKBITS
   set_parameter_value POWERUP_DELAY      $POWERUP_DELAY
   set_parameter_value REFRESH_PERIOD     $REFRESH_PERIOD
   set_parameter_value size 			  $size
   set_parameter_value CNTRL_ADDR_WIDTH   $D_ADDR_WIDTH
   set_parameter_value MAX_REC_TIME       [ proc_max [ expr { $T_WR - 1 } ] [ expr { $CAS_LATENCY - 2 } ] 0 ]

}

proc elaboration {} {

   set T_RCD            [ get_parameter_value T_RCD            ]
   set T_RFC            [ get_parameter_value T_RFC            ]
   set T_RP             [ get_parameter_value T_RP             ]
   set CNTRL_ADDR_WIDTH [ get_parameter_value CNTRL_ADDR_WIDTH ]
   set SDRAM_DATA_WIDTH [ get_parameter_value SDRAM_DATA_WIDTH ]
   set SDRAM_ROW_WIDTH  [ get_parameter_value SDRAM_ROW_WIDTH  ]
   set SDRAM_BANK_WIDTH [ get_parameter_value SDRAM_BANK_WIDTH ]
   set NUM_CHIPSELECTS  [ get_parameter_value NUM_CHIPSELECTS  ]
   set TRISTATE_EN      [ proc_get_boolean_parameter TRISTATE_EN ]

   # 
   # connection point clock_sink
   # 
   add_interface clock_sink clock end
   set_interface_property clock_sink clockRate 0
   set_interface_property clock_sink ENABLED true
   set_interface_property clock_sink EXPORT_OF ""
   set_interface_property clock_sink PORT_NAME_MAP ""
   set_interface_property clock_sink CMSIS_SVD_VARIABLES ""
   set_interface_property clock_sink SVD_ADDRESS_GROUP ""

   add_interface_port clock_sink clk clk Input 1

   # 
   # connection point reset_sink
   # 
   add_interface reset_sink reset end
   set_interface_property reset_sink associatedClock clock_sink
   set_interface_property reset_sink synchronousEdges DEASSERT
   set_interface_property reset_sink ENABLED true
   set_interface_property reset_sink EXPORT_OF ""
   set_interface_property reset_sink PORT_NAME_MAP ""
   set_interface_property reset_sink CMSIS_SVD_VARIABLES ""
   set_interface_property reset_sink SVD_ADDRESS_GROUP ""

   add_interface_port reset_sink rst_n reset_n Input 1

   # 
   # connection point s1
   # 
	add_interface s1 avalon slave
	set_interface_property s1 addressAlignment               {DYNAMIC}
	set_interface_property s1 addressGroup                   {0}
	set_interface_property s1 addressSpan                    {16777216}
	set_interface_property s1 addressUnits                   WORDS
	set_interface_property s1 alwaysBurstMaxBurst            {0}
	set_interface_property s1 associatedClock                clock_sink
	set_interface_property s1 associatedReset                reset_sink
	set_interface_property s1 bitsPerSymbol                  8
	set_interface_property s1 burstOnBurstBoundariesOnly     false
	set_interface_property s1 burstcountUnits                WORDS
	set_interface_property s1 constantBurstBehavior          0
	set_interface_property s1 explicitAddressSpan            0
	set_interface_property s1 holdTime                       0
	set_interface_property s1 interleaveBursts               {0}
	set_interface_property s1 isBigEndian                    {0}
	set_interface_property s1 linewrapBursts                 false
	set_interface_property s1 maximumPendingReadTransactions 7
	set_interface_property s1 minimumUninterruptedRunLength  {1}
	set_interface_property s1 readLatency                    0
	set_interface_property s1 readWaitStates                 {1}
	set_interface_property s1 readWaitTime                   1
	set_interface_property s1 registerIncomingSignals        {0}
	set_interface_property s1 registerOutgoingSignals        {0}
	set_interface_property s1 setupTime                      0
	set_interface_property s1 timingUnits                    Cycles
	set_interface_property s1 transparentBridge              {0}
	set_interface_property s1 wellBehavedWaitrequest         {0}
	set_interface_property s1 writeLatency                   {0}
	set_interface_property s1 writeWaitStates                {0}
	set_interface_property s1 writeWaitTime                  0

   set_interface_property s1 ENABLED true
   set_interface_property s1 EXPORT_OF ""
   set_interface_property s1 PORT_NAME_MAP ""
   set_interface_property s1 CMSIS_SVD_VARIABLES ""
   set_interface_property s1 SVD_ADDRESS_GROUP ""

	set byteenable_width [ expr { $SDRAM_DATA_WIDTH/8 } ] 
	add_interface_port s1 avs_address         address        Input    "$CNTRL_ADDR_WIDTH"
	add_interface_port s1 avs_byteenable      byteenable     Input    "$byteenable_width"
	add_interface_port s1 avs_writedata       writedata      Input    "$SDRAM_DATA_WIDTH"
	add_interface_port s1 avs_read            read           Input    1
	add_interface_port s1 avs_write           write          Input    1
	add_interface_port s1 avs_readdata        readdata       Output   "$SDRAM_DATA_WIDTH"
	add_interface_port s1 avs_readdatavalid   readdatavalid  Output   1
	add_interface_port s1 avs_waitrequest     waitrequest    Output   1
   
   set_interface_assignment s1 embeddedsw.configuration.isFlash 0
   set_interface_assignment s1 embeddedsw.configuration.isMemoryDevice 1
   set_interface_assignment s1 embeddedsw.configuration.isNonVolatileStorage 0
   set_interface_assignment s1 embeddedsw.configuration.isPrintableDevice 0

   set dqm_width [ expr { $SDRAM_DATA_WIDTH/8 } ]

   if { $TRISTATE_EN } {

      # 
      # connection point tcm (tristate conduit master)
      # 
      add_interface tcm tristate_conduit master

      set_interface_property tcm associatedClock clock_sink
      set_interface_property tcm associatedReset reset_sink
      set_interface_property tcm ENABLED true
      set_interface_property tcm EXPORT_OF ""
      set_interface_property tcm PORT_NAME_MAP ""
      set_interface_property tcm CMSIS_SVD_VARIABLES ""
      set_interface_property tcm SVD_ADDRESS_GROUP ""

      add_interface_port tcm tcm_grant    grant       Input    1
      add_interface_port tcm tcm_request  request     Output   1

      add_interface_port tcm sdram_dq_out dq_out      Output   "$SDRAM_DATA_WIDTH"
      add_interface_port tcm sdram_dq_in  dq_in       Input    "$SDRAM_DATA_WIDTH"
      add_interface_port tcm sdram_dq_oe  dq_outen    Output   1

      add_interface_port tcm sdram_addr   addr_out    Output   "$SDRAM_ROW_WIDTH"
      add_interface_port tcm sdram_ba     ba_out      Output   "$SDRAM_BANK_WIDTH"
      add_interface_port tcm sdram_cas_n  cas_out     Output   1
      add_interface_port tcm sdram_cke    cke_out     Output   1
      add_interface_port tcm sdram_cs_n   cs_out      Output   "$NUM_CHIPSELECTS"
      add_interface_port tcm sdram_dqm    dqm_out     Output   "$dqm_width"
      add_interface_port tcm sdram_ras_n  ras_out     Output   1
      add_interface_port tcm sdram_we_n   we_out      Output   1

      add_interface_port tcm sdram_dq     unused      Bidir    "$SDRAM_DATA_WIDTH"
      set_port_property sdram_dq          termination true
      set_port_property sdram_dq          termination_value    0

   } else {
   
      # 
      # connection point wire
      # 
      add_interface wire conduit end
      set_interface_property wire associatedClock ""
      set_interface_property wire associatedReset ""
      set_interface_property wire ENABLED true
      set_interface_property wire EXPORT_OF ""
      set_interface_property wire PORT_NAME_MAP ""
      set_interface_property wire CMSIS_SVD_VARIABLES ""
      set_interface_property wire SVD_ADDRESS_GROUP ""

      add_interface_port wire sdram_addr     export      Output   "$SDRAM_ROW_WIDTH"
      add_interface_port wire sdram_ba       export      Output   "$SDRAM_BANK_WIDTH"
      add_interface_port wire sdram_cas_n    export      Output   1
      add_interface_port wire sdram_cke      export      Output   1
      add_interface_port wire sdram_cs_n     export      Output   "$NUM_CHIPSELECTS"
      add_interface_port wire sdram_dq       export      Bidir    "$SDRAM_DATA_WIDTH"
      add_interface_port wire sdram_dqm      export      Output   "$dqm_width"
      add_interface_port wire sdram_ras_n    export      Output   1
      add_interface_port wire sdram_we_n     export      Output   1

      # unused ports
      add_interface sdram_dq_tristate conduit end
      set_interface_property  sdram_dq_tristate  ENABLED true
      set_interface_property  sdram_dq_tristate  EXPORT_OF ""
      set_interface_property  sdram_dq_tristate  PORT_NAME_MAP ""
      set_interface_property  sdram_dq_tristate  SVD_ADDRESS_GROUP ""
      
      add_interface_port sdram_dq_tristate sdram_dq_out  sdram_dq_out   Output   "$SDRAM_DATA_WIDTH"
      add_interface_port sdram_dq_tristate sdram_dq_in   sdram_dq_in    Input    "$SDRAM_DATA_WIDTH"
      add_interface_port sdram_dq_tristate sdram_dq_oe   sdram_dq_oe    Output   1

      set_port_property sdram_dq_out   termination true
      set_port_property sdram_dq_in    termination true
      set_port_property sdram_dq_in    termination_value    0
      set_port_property sdram_dq_oe    termination true
	  
      add_interface tcm tristate_conduit master
      
      set_interface_property tcm associatedClock clock_sink
      set_interface_property tcm associatedReset reset_sink
      set_interface_property tcm ENABLED true
      set_interface_property tcm EXPORT_OF ""
      set_interface_property tcm PORT_NAME_MAP ""
      set_interface_property tcm CMSIS_SVD_VARIABLES ""
      set_interface_property tcm SVD_ADDRESS_GROUP ""
	  
      add_interface_port tcm tcm_grant       unused      Input    1
      add_interface_port tcm tcm_request     unused      Output   1
      set_port_property  tcm_grant           termination true
      set_port_property  tcm_grant           termination_value    0
      set_port_property  tcm_request         termination true

   }

}


## Add documentation links for user guide and/or release notes
add_documentation_link "User Guide" https://documentation.altera.com/#/link/sfo1400787952932/iga1404138195527
add_documentation_link "Release Notes" https://documentation.altera.com/#/link/hco1421698042087/hco1421698013408
