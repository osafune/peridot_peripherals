# ===================================================================
# TITLE : PERIDOT-NGS / "PERIDOT WSG Sound Generator"
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2016/10/25 -> 2017/05/08
#
# ===================================================================
# *******************************************************************
#  (C)2009,2016,2017 J-7SYSTEM WORKS LIMITED.  All rights Reserved.
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
# module peridot_wsg
# 
set_module_property NAME peridot_wsg
set_module_property DISPLAY_NAME "PERIDOT WSG Sound Generator (beta test version)"
set_module_property DESCRIPTION "PERIDOT WSG Sound Generator"
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
set_fileset_property QUARTUS_SYNTH TOP_LEVEL wsg_component
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
set_fileset_property QUARTUS_SYNTH ENABLE_FILE_OVERWRITE_MODE false
add_fileset_file wsg_component.vhd		VHDL PATH hdl/wsg_component.vhd TOP_LEVEL_FILE
add_fileset_file wsg_businterface.vhd	VHDL PATH hdl/wsg_businterface.vhd
add_fileset_file wsg_slotengine.vhd		VHDL PATH hdl/wsg_slotengine.vhd
add_fileset_file wsg_extmodule.vhd		VHDL PATH hdl/wsg_extmodule.vhd
add_fileset_file wsg_pcm8.vhd			VHDL PATH hdl/wsg_pcm8.vhd
add_fileset_file wsg_audout.vhd			VHDL PATH hdl/wsg_audout.vhd
add_fileset_file wsg_dsdac8.vhd			VHDL PATH hdl/wsg_dsdac8.vhd
#add_fileset_file wsg_wavetable.mif		MIF PATH hdl/wsg_wavetable.mif
#add_fileset_file wsg_component.sdc		SDC PATH hdl/wsg_component.sdc


# 
# parameters
# 
add_parameter AUDIOCLOCKFREQ INTEGER 24576000
set_parameter_property AUDIOCLOCKFREQ DEFAULT_VALUE 24576000
set_parameter_property AUDIOCLOCKFREQ DISPLAY_NAME "External Audio clock input "
set_parameter_property AUDIOCLOCKFREQ TYPE INTEGER
set_parameter_property AUDIOCLOCKFREQ UNITS Hertz
set_parameter_property AUDIOCLOCKFREQ ALLOWED_RANGES 1000000:256000000
set_parameter_property AUDIOCLOCKFREQ HDL_PARAMETER true
add_parameter SAMPLINGFREQ INTEGER 32000
set_parameter_property SAMPLINGFREQ DEFAULT_VALUE 32000
set_parameter_property SAMPLINGFREQ DISPLAY_NAME "WSG and PCM sound playback frequency "
set_parameter_property SAMPLINGFREQ TYPE INTEGER
set_parameter_property SAMPLINGFREQ UNITS Hertz
set_parameter_property SAMPLINGFREQ ALLOWED_RANGES 1000:96000
set_parameter_property SAMPLINGFREQ HDL_PARAMETER true
add_parameter MAXSLOTNUM INTEGER 64
set_parameter_property MAXSLOTNUM DEFAULT_VALUE 64
set_parameter_property MAXSLOTNUM DISPLAY_NAME "WSG slot generate number "
set_parameter_property MAXSLOTNUM ALLOWED_RANGES {32 40 48 56 64}
set_parameter_property MAXSLOTNUM UNITS None
set_parameter_property MAXSLOTNUM HDL_PARAMETER true
add_parameter PCM_CHANNEL_GENNUM INTEGER 2
set_parameter_property PCM_CHANNEL_GENNUM DEFAULT_VALUE 2
set_parameter_property PCM_CHANNEL_GENNUM DISPLAY_NAME "PCM channel generate number "
set_parameter_property PCM_CHANNEL_GENNUM ALLOWED_RANGES 0:8
set_parameter_property PCM_CHANNEL_GENNUM UNITS None
set_parameter_property PCM_CHANNEL_GENNUM HDL_PARAMETER true


# 
# display items
# 



# 
# connection point clock
# 
add_interface clock clock end
set_interface_property clock clockRate 0
set_interface_property clock ENABLED true
set_interface_property clock EXPORT_OF ""
set_interface_property clock PORT_NAME_MAP ""
set_interface_property clock CMSIS_SVD_VARIABLES ""
set_interface_property clock SVD_ADDRESS_GROUP ""

add_interface_port clock avs_s1_clk clk Input 1


# 
# connection point reset
# 
add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
set_interface_property reset ENABLED true
set_interface_property reset EXPORT_OF ""
set_interface_property reset PORT_NAME_MAP ""
set_interface_property reset CMSIS_SVD_VARIABLES ""
set_interface_property reset SVD_ADDRESS_GROUP ""

add_interface_port reset csi_global_reset reset Input 1


# 
# connection point s1
# 
add_interface s1 avalon end
set_interface_property s1 addressUnits WORDS
set_interface_property s1 associatedClock clock
set_interface_property s1 associatedReset reset
set_interface_property s1 bitsPerSymbol 8
set_interface_property s1 burstOnBurstBoundariesOnly false
set_interface_property s1 burstcountUnits WORDS
set_interface_property s1 explicitAddressSpan 0
set_interface_property s1 holdTime 0
set_interface_property s1 linewrapBursts false
set_interface_property s1 maximumPendingReadTransactions 0
set_interface_property s1 maximumPendingWriteTransactions 0
set_interface_property s1 readLatency 0
set_interface_property s1 readWaitStates 2
set_interface_property s1 readWaitTime 2
set_interface_property s1 setupTime 0
set_interface_property s1 timingUnits Cycles
set_interface_property s1 writeWaitTime 0
set_interface_property s1 ENABLED true
set_interface_property s1 EXPORT_OF ""
set_interface_property s1 PORT_NAME_MAP ""
set_interface_property s1 CMSIS_SVD_VARIABLES ""
set_interface_property s1 SVD_ADDRESS_GROUP ""

add_interface_port s1 avs_s1_address address Input 9
add_interface_port s1 avs_s1_read read Input 1
add_interface_port s1 avs_s1_readdata readdata Output 16
add_interface_port s1 avs_s1_write write Input 1
add_interface_port s1 avs_s1_writedata writedata Input 16
add_interface_port s1 avs_s1_byteenable byteenable Input 2
set_interface_assignment s1 embeddedsw.configuration.isFlash 0
set_interface_assignment s1 embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment s1 embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment s1 embeddedsw.configuration.isPrintableDevice 0


# 
# connection point irq
# 
add_interface irq interrupt end
set_interface_property irq associatedAddressablePoint ""
set_interface_property irq bridgedReceiverOffset ""
set_interface_property irq bridgesToReceiver ""
set_interface_property irq ENABLED true
set_interface_property irq EXPORT_OF ""
set_interface_property irq PORT_NAME_MAP ""
set_interface_property irq CMSIS_SVD_VARIABLES ""
set_interface_property irq SVD_ADDRESS_GROUP ""

add_interface_port irq avs_s1_irq irq Output 1



# 
# connection point export
# 
add_interface export conduit end
set_interface_property export associatedClock ""
set_interface_property export associatedReset ""
set_interface_property export ENABLED true
set_interface_property export EXPORT_OF ""
set_interface_property export PORT_NAME_MAP ""
set_interface_property export CMSIS_SVD_VARIABLES ""
set_interface_property export SVD_ADDRESS_GROUP ""

add_interface_port export audio_clk audio_clk Input 1
add_interface_port export dac_bclk bclk Output 1
add_interface_port export dac_lrck lrck Output 1
add_interface_port export dac_data sdat Output 1
add_interface_port export aud_l aud_l Output 1
add_interface_port export aud_r aud_r Output 1
add_interface_port export mute mute Output 1
add_interface_port export kb_scko kb_scko Output 1
add_interface_port export kb_load_n kb_load_n Output 1
add_interface_port export kb_sdin kb_sdin Input 1



