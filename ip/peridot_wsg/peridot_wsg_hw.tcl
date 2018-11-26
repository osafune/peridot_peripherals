# ===================================================================
# TITLE : PERIDOT-NGS / "PERIDOT WSG Sound Generator"
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2016/10/25 -> 2017/05/08
#   MODIFY : 2018/11/26 17.1 beta
#
# ===================================================================
#
# The MIT License (MIT)
# Copyright (c) 2016,2018 J-7SYSTEM WORKS LIMITED.
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
# module peridot_wsg
# 
set_module_property NAME peridot_wsg
set_module_property DISPLAY_NAME "PERIDOT WSG Sound Generator (beta test version)"
set_module_property DESCRIPTION "PERIDOT WSG Sound Generator"
set_module_property GROUP "PERIDOT Peripherals"
set_module_property AUTHOR "J-7SYSTEM WORKS LIMITED"
set_module_property VERSION 17.1
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
set_fileset_property QUARTUS_SYNTH TOP_LEVEL peridot_wsg
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
set_fileset_property QUARTUS_SYNTH ENABLE_FILE_OVERWRITE_MODE false
add_fileset_file peridot_wsg.vhd				VHDL PATH hdl/peridot_wsg.vhd TOP_LEVEL_FILE
add_fileset_file peridot_wsg_businterface.vhd	VHDL PATH hdl/peridot_wsg_businterface.vhd
add_fileset_file peridot_wsg_slotengine.vhd		VHDL PATH hdl/peridot_wsg_slotengine.vhd
add_fileset_file peridot_wsg_extmodule.vhd		VHDL PATH hdl/peridot_wsg_extmodule.vhd
add_fileset_file peridot_wsg_pcm8.vhd			VHDL PATH hdl/peridot_wsg_pcm8.vhd
add_fileset_file peridot_wsg_audout.vhd			VHDL PATH hdl/peridot_wsg_audout.vhd
add_fileset_file peridot_wsg_dsdac8.vhd			VHDL PATH hdl/peridot_wsg_dsdac8.vhd
add_fileset_file peridot_wsg.sdc				SDC PATH hdl/peridot_wsg.sdc
#add_fileset_file peridot_wsg_wavetable.mif		MIF PATH hdl/peridot_wsg_wavetable.mif


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

add_interface_port clock avs_s1_clk clk Input 1


# 
# connection point reset
# 
add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT

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
set_interface_property irq associatedAddressablePoint s1
set_interface_property irq associatedClock clock
set_interface_property irq associatedReset reset

add_interface_port irq avs_s1_irq irq Output 1


# 
# connection point export
# 
add_interface export conduit end
set_interface_property export associatedClock ""
set_interface_property export associatedReset ""

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


