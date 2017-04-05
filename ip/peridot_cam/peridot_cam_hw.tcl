# ===================================================================
# TITLE : PERIDOT-NGS / "PERIDOT CAM"
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2017/04/05 -> 2017/04/06
#
# ===================================================================
# *******************************************************************
#        (C)2017 J-7SYSTEM WORKS LIMITED.  All rights Reserved.
#
# * This module is a free sourcecode and there is NO WARRANTY.
# * No restriction on use. You can use, modify and redistribute it
#   for personal, non-profit or commercial products UNDER YOUR
#   RESPONSIBILITY.
# * Redistributions of source code must retain the above copyright
#   notice.
# *******************************************************************

# 
# request TCL package from ACDS 16.1
# 
package require -exact qsys 16.1


# 
# module peridot_hostbridge
# 
set_module_property NAME peridot_cam
set_module_property DISPLAY_NAME "PERIDOT CAM interface (Alpha test version)"
set_module_property DESCRIPTION "PERIDOT Camera input interface"
set_module_property GROUP "PERIDOT Peripherals"
set_module_property AUTHOR "J-7SYSTEM WORKS LIMITED"
set_module_property VERSION 16.1
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property HIDE_FROM_SOPC true
set_module_property HIDE_FROM_QUARTUS true
set_module_property EDITABLE false


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
set_interface_property s1_clock ENABLED true
set_interface_property s1_clock EXPORT_OF ""
set_interface_property s1_clock PORT_NAME_MAP ""
set_interface_property s1_clock CMSIS_SVD_VARIABLES ""
set_interface_property s1_clock SVD_ADDRESS_GROUP ""

add_interface_port s1_clock csi_global_clk clk Input 1

# 
# connection point s1_reset
# 
add_interface s1_reset reset end
set_interface_property s1_reset associatedClock s1_clock
set_interface_property s1_reset synchronousEdges DEASSERT
set_interface_property s1_reset ENABLED true
set_interface_property s1_reset EXPORT_OF ""
set_interface_property s1_reset PORT_NAME_MAP ""
set_interface_property s1_reset CMSIS_SVD_VARIABLES ""
set_interface_property s1_reset SVD_ADDRESS_GROUP ""

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
set_interface_property s1 ENABLED true
set_interface_property s1 EXPORT_OF ""
set_interface_property s1 PORT_NAME_MAP ""
set_interface_property s1 CMSIS_SVD_VARIABLES ""
set_interface_property s1 SVD_ADDRESS_GROUP ""

add_interface_port s1 avs_s1_address address Input 2
add_interface_port s1 avs_s1_write write Input 1
add_interface_port s1 avs_s1_writedata writedata Input 32
add_interface_port s1 avs_s1_read read Input 1
add_interface_port s1 avs_s1_readdata readdata Output 32
set_interface_assignment s1 embeddedsw.configuration.isFlash 0
set_interface_assignment s1 embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment s1 embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment s1 embeddedsw.configuration.isPrintableDevice 0

# 
# connection point irq_s1
# 
add_interface irq_s1 interrupt end
set_interface_property irq_s1 associatedAddressablePoint ""
set_interface_property irq_s1 associatedClock s1_clock
set_interface_property irq_s1 bridgedReceiverOffset ""
set_interface_property irq_s1 bridgesToReceiver ""
set_interface_property irq_s1 ENABLED true
set_interface_property irq_s1 EXPORT_OF ""
set_interface_property irq_s1 PORT_NAME_MAP ""
set_interface_property irq_s1 CMSIS_SVD_VARIABLES ""
set_interface_property irq_s1 SVD_ADDRESS_GROUP ""

add_interface_port irq_s1 avs_s1_irq irq Output 1


# 
# connection point m1_clock
# 
add_interface m1_clock clock end
set_interface_property m1_clock clockRate 0
set_interface_property m1_clock ENABLED true
set_interface_property m1_clock EXPORT_OF ""
set_interface_property m1_clock PORT_NAME_MAP ""
set_interface_property m1_clock CMSIS_SVD_VARIABLES ""
set_interface_property m1_clock SVD_ADDRESS_GROUP ""

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
set_interface_property m1 ENABLED true
set_interface_property m1 EXPORT_OF ""
set_interface_property m1 PORT_NAME_MAP ""
set_interface_property m1 CMSIS_SVD_VARIABLES ""
set_interface_property m1 SVD_ADDRESS_GROUP ""

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
set_interface_property extcam ENABLED true
set_interface_property extcam EXPORT_OF ""
set_interface_property extcam PORT_NAME_MAP ""
set_interface_property extcam CMSIS_SVD_VARIABLES ""
set_interface_property extcam SVD_ADDRESS_GROUP ""

add_interface_port extcam cam_clk pclk Input 1
add_interface_port extcam cam_data data Input 8
add_interface_port extcam cam_href href Input 1
add_interface_port extcam cam_vsync vsync Input 1
