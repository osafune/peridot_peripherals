# ===================================================================
# TITLE : PERIDOT-NGS / "PERIDOT SPI master"
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2017/02/20 -> 2017/03/01
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
# module peridot_spi_master
# 
set_module_property NAME peridot_spi_master
set_module_property DISPLAY_NAME "PERIDOT SPI master"
set_module_property DESCRIPTION "PERIDOT SPI master"
set_module_property GROUP "PERIDOT Peripherals"
set_module_property AUTHOR "J-7SYSTEM WORKS LIMITED"
set_module_property VERSION 17.1
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property HIDE_FROM_SOPC true
set_module_property HIDE_FROM_QUARTUS true
set_module_property EDITABLE false
set_module_property VALIDATION_CALLBACK validate


# 
# file sets
# 
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL peridot_csr_spi
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
set_fileset_property QUARTUS_SYNTH ENABLE_FILE_OVERWRITE_MODE false
add_fileset_file peridot_csr_spi.v VERILOG PATH ../peridot_hostbridge/hdl/peridot_csr_spi.v TOP_LEVEL_FILE


# 
# parameters
# 
add_parameter CLOCKFREQ INTEGER 0
set_parameter_property CLOCKFREQ TYPE INTEGER
set_parameter_property CLOCKFREQ SYSTEM_INFO {CLOCK_RATE clock}
set_parameter_property CLOCKFREQ DISPLAY_NAME "Drive clock rate"
set_parameter_property CLOCKFREQ UNITS Hertz
set_parameter_property CLOCKFREQ HDL_PARAMETER false

add_parameter DEVSELECT_NUMBER INTEGER 1
set_parameter_property DEVSELECT_NUMBER TYPE INTEGER
set_parameter_property DEVSELECT_NUMBER DISPLAY_NAME "Number of devices(ss_n)"
set_parameter_property DEVSELECT_NUMBER UNITS None
set_parameter_property DEVSELECT_NUMBER ALLOWED_RANGES 1:32
set_parameter_property DEVSELECT_NUMBER HDL_PARAMETER true

add_parameter DEFAULT_REG_BITRVS INTEGER 0
set_parameter_property DEFAULT_REG_BITRVS TYPE INTEGER
set_parameter_property DEFAULT_REG_BITRVS DISPLAY_NAME "Default value of bit reverse register(BITRVS)"
set_parameter_property DEFAULT_REG_BITRVS UNITS None
set_parameter_property DEFAULT_REG_BITRVS ALLOWED_RANGES {0 1}
set_parameter_property DEFAULT_REG_BITRVS HDL_PARAMETER true

add_parameter DEFAULT_REG_MODE INTEGER 0
set_parameter_property DEFAULT_REG_MODE TYPE INTEGER
set_parameter_property DEFAULT_REG_MODE DISPLAY_NAME "Default value of mode register(MODE)"
set_parameter_property DEFAULT_REG_MODE UNITS None
set_parameter_property DEFAULT_REG_MODE ALLOWED_RANGES {0 1 2 3}
set_parameter_property DEFAULT_REG_MODE HDL_PARAMETER true

add_parameter DEFAULT_REG_CLKDIV INTEGER 255
set_parameter_property DEFAULT_REG_CLKDIV TYPE INTEGER
set_parameter_property DEFAULT_REG_CLKDIV DISPLAY_NAME "Default value of clock divider(CLKDIV)"
set_parameter_property DEFAULT_REG_CLKDIV UNITS None
set_parameter_property DEFAULT_REG_CLKDIV ALLOWED_RANGES 0:255
set_parameter_property DEFAULT_REG_CLKDIV HDL_PARAMETER true


# 
# display items
# 


# 
# connection point clock
# 
add_interface clock clock end
set_interface_property clock clockRate 0

add_interface_port clock csi_clk clk Input 1


# 
# connection point reset
# 
add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT

add_interface_port reset rsi_reset reset Input 1


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
set_interface_property s1 readWaitTime 1
set_interface_property s1 setupTime 0
set_interface_property s1 timingUnits Cycles
set_interface_property s1 writeWaitTime 0

add_interface_port s1 avs_address address Input 1
add_interface_port s1 avs_read read Input 1
add_interface_port s1 avs_readdata readdata Output 32
add_interface_port s1 avs_write write Input 1
add_interface_port s1 avs_writedata writedata Input 32
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

add_interface_port irq ins_irq irq Output 1


# 
# connection point export
# 
add_interface export conduit end
set_interface_property export associatedClock clock
set_interface_property export associatedReset reset

add_interface_port export spi_ss_n ss_n Output {DEVSELECT_NUMBER}
add_interface_port export spi_sclk sclk Output 1
add_interface_port export spi_mosi mosi Output 1
add_interface_port export spi_miso miso Input 1


#
# Validation callback
#
proc validate {} {

	#
	# Software assignments for system.h
	#
	set_module_assignment embeddedsw.CMacro.FREQ [get_parameter_value CLOCKFREQ]

}
