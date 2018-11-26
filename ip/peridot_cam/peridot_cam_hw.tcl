# ===================================================================
# TITLE : PERIDOT-NGS / "PERIDOT CAM"
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2017/04/05 -> 2017/04/06
#   MODIFY : 2018/11/26 17.1 beta
#
# ===================================================================
#
# The MIT License (MIT)
# Copyright (c) 2017,2018 J-7SYSTEM WORKS LIMITED.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is furnished to do
# so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

# 
# request TCL package from ACDS 16.1
# 
package require -exact qsys 16.1


# 
# module peridot_cam
# 
set_module_property NAME peridot_cam
set_module_property DISPLAY_NAME "PERIDOT CAM interface (Beta test version)"
set_module_property DESCRIPTION "PERIDOT Camera input interface"
set_module_property GROUP "PERIDOT Peripherals"
set_module_property AUTHOR "J-7SYSTEM WORKS LIMITED"
set_module_property VERSION 17.1
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property HIDE_FROM_SOPC true
set_module_property HIDE_FROM_QUARTUS true
set_module_property EDITABLE true


# 
# file sets
# 
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL peridot_cam
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
set_fileset_property QUARTUS_SYNTH ENABLE_FILE_OVERWRITE_MODE false
add_fileset_file peridot_cam.v		VERILOG PATH hdl/peridot_cam.v TOP_LEVEL_FILE
add_fileset_file paridot_cam_avm.v	VERILOG PATH hdl/paridot_cam_avm.v
add_fileset_file peridot_cam_avs.v	VERILOG PATH hdl/peridot_cam_avs.v
add_fileset_file peridot_i2c.v		VERILOG PATH hdl/peridot_cam_sccb.v
add_fileset_file peridot_cam.sdc	SDC PATH hdl/peridot_cam.sdc


# 
# parameters
# 


# 
# display items
# 


# 
# connection point s1_clock
# 
add_interface s1_clock clock end
set_interface_property s1_clock clockRate 0

add_interface_port s1_clock csi_global_clk clk Input 1

# 
# connection point s1_reset
# 
add_interface s1_reset reset end
set_interface_property s1_reset associatedClock s1_clock
set_interface_property s1_reset synchronousEdges DEASSERT

add_interface_port s1_reset csi_global_reset reset Input 1

# 
# connection point s1
# 
add_interface s1 avalon end
set_interface_property s1 addressUnits WORDS
set_interface_property s1 associatedClock s1_clock
set_interface_property s1 associatedReset s1_reset
set_interface_property s1 bitsPerSymbol 8
set_interface_property s1 burstOnBurstBoundariesOnly false
set_interface_property s1 burstcountUnits WORDS
set_interface_property s1 explicitAddressSpan 0
set_interface_property s1 holdTime 0
set_interface_property s1 linewrapBursts false
set_interface_property s1 maximumPendingReadTransactions 0
set_interface_property s1 maximumPendingWriteTransactions 0
set_interface_property s1 readLatency 0
set_interface_property s1 readWaitTime 1
set_interface_property s1 setupTime 0
set_interface_property s1 timingUnits Cycles
set_interface_property s1 writeWaitTime 0

add_interface_port s1 avs_s1_address address Input 2
add_interface_port s1 avs_s1_write write Input 1
add_interface_port s1 avs_s1_writedata writedata Input 32
add_interface_port s1 avs_s1_read read Input 1
add_interface_port s1 avs_s1_readdata readdata Output 32
add_interface_port s1 avs_s1_waitrequest waitrequest Output 1
set_interface_assignment s1 embeddedsw.configuration.isFlash 0
set_interface_assignment s1 embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment s1 embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment s1 embeddedsw.configuration.isPrintableDevice 0

# 
# connection point irq_s1
# 
add_interface irq_s1 interrupt end
set_interface_property irq_s1 associatedAddressablePoint s1
set_interface_property irq_s1 associatedClock s1_clock
set_interface_property irq_s1 associatedReset s1_reset

add_interface_port irq_s1 avs_s1_irq irq Output 1


# 
# connection point m1_clock
# 
add_interface m1_clock clock end
set_interface_property m1_clock clockRate 0

add_interface_port m1_clock avm_m1_clk clk Input 1

# 
# connection point m1
# 
add_interface m1 avalon start
set_interface_property m1 addressUnits SYMBOLS
set_interface_property m1 associatedClock m1_clock
set_interface_property m1 associatedReset s1_reset
set_interface_property m1 bitsPerSymbol 8
set_interface_property m1 burstOnBurstBoundariesOnly false
set_interface_property m1 burstcountUnits WORDS
set_interface_property m1 doStreamReads false
set_interface_property m1 doStreamWrites false
set_interface_property m1 holdTime 0
set_interface_property m1 linewrapBursts false
set_interface_property m1 maximumPendingReadTransactions 0
set_interface_property m1 maximumPendingWriteTransactions 0
set_interface_property m1 readLatency 0
set_interface_property m1 readWaitTime 1
set_interface_property m1 setupTime 0
set_interface_property m1 timingUnits Cycles
set_interface_property m1 writeWaitTime 0

add_interface_port m1 avm_m1_address address Output 32
add_interface_port m1 avm_m1_write write Output 1
add_interface_port m1 avm_m1_writedata writedata Output 32
add_interface_port m1 avm_m1_byteenable byteenable Output 4
add_interface_port m1 avm_m1_burstcount burstcount Output 5
add_interface_port m1 avm_m1_waitrequest waitrequest Input 1


# 
# connection point extcam
# 
add_interface extcam conduit end
set_interface_property extcam associatedClock ""
set_interface_property extcam associatedReset ""

add_interface_port extcam cam_clk pclk Input 1
add_interface_port extcam cam_data data Input 8
add_interface_port extcam cam_href href Input 1
add_interface_port extcam cam_vsync vsync Input 1
add_interface_port extcam cam_reset_n reseto_n Output 1
add_interface_port extcam sccb_sck sccb_c Output 1
add_interface_port extcam sccb_data sccb_d Output 1
