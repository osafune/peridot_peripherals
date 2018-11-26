# ===================================================================
# TITLE : PERIDOT-NGS / "PERIDOT Graphic LCD Controller"
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2017/03/12 -> 2017/03/12
#   MODIFY : 2018/11/26 17.1 beta
#
# ===================================================================
#
# The MIT License (MIT)
# Copyright (c) 2018 J-7SYSTEM WORKS LIMITED.
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
# module peridot_glcd_controller
# 
set_module_property NAME peridot_glcd_controller
set_module_property DISPLAY_NAME "PERIDOT GLCD controller"
set_module_property DESCRIPTION "PERIDOT GLCD controller"
set_module_property GROUP "PERIDOT Peripherals"
set_module_property AUTHOR "J-7SYSTEM WORKS LIMITED"
set_module_property VERSION 17.1
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property HIDE_FROM_SOPC true
set_module_property HIDE_FROM_QUARTUS true
set_module_property EDITABLE false
set_module_property ELABORATION_CALLBACK elaboration_callback


# 
# file sets
# 
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL peridot_glcd
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
set_fileset_property QUARTUS_SYNTH ENABLE_FILE_OVERWRITE_MODE false
add_fileset_file peridot_glcd.vhd			VHDL PATH hdl/peridot_glcd.vhd TOP_LEVEL_FILE
add_fileset_file peridot_glcd_dma.vhd		VHDL PATH hdl/peridot_glcd_dma.vhd
add_fileset_file peridot_glcd_regs.vhd		VHDL PATH hdl/peridot_glcd_regs.vhd
add_fileset_file peridot_glcd_wrstate.vhd	VHDL PATH hdl/peridot_glcd_wrstate.vhd


# 
# parameters
# 
set debugview false

add_parameter CLOCKFREQ integer
set_parameter_property CLOCKFREQ UNITS hertz
set_parameter_property CLOCKFREQ SYSTEM_INFO {CLOCK_RATE clock}
set_parameter_property CLOCKFREQ ENABLED false
set_parameter_property CLOCKFREQ VISIBLE $debugview

add_parameter VRAM_LINEBYTES integer
set_parameter_property VRAM_LINEBYTES HDL_PARAMETER true
set_parameter_property VRAM_LINEBYTES DERIVED true
set_parameter_property VRAM_LINEBYTES VISIBLE $debugview

add_parameter VRAM_VIEWWIDTH integer
set_parameter_property VRAM_VIEWWIDTH HDL_PARAMETER true
set_parameter_property VRAM_VIEWWIDTH DERIVED true
set_parameter_property VRAM_VIEWWIDTH VISIBLE $debugview

add_parameter VRAM_VIEWHEIGHT integer
set_parameter_property VRAM_VIEWHEIGHT HDL_PARAMETER true
set_parameter_property VRAM_VIEWHEIGHT DERIVED true
set_parameter_property VRAM_VIEWHEIGHT VISIBLE $debugview

add_parameter LCDC_WRSETUP_COUNT integer
set_parameter_property LCDC_WRSETUP_COUNT HDL_PARAMETER true
set_parameter_property LCDC_WRSETUP_COUNT DERIVED true
set_parameter_property LCDC_WRSETUP_COUNT VISIBLE $debugview

add_parameter LCDC_WRWIDTH_COUNT integer
set_parameter_property LCDC_WRWIDTH_COUNT HDL_PARAMETER true
set_parameter_property LCDC_WRWIDTH_COUNT DERIVED true
set_parameter_property LCDC_WRWIDTH_COUNT VISIBLE $debugview

add_parameter LCDC_WRHOLD_COUNT integer
set_parameter_property LCDC_WRHOLD_COUNT HDL_PARAMETER true
set_parameter_property LCDC_WRHOLD_COUNT DERIVED true
set_parameter_property LCDC_WRHOLD_COUNT VISIBLE $debugview

add_parameter LCDC_WAITCOUNT_MAX integer
set_parameter_property LCDC_WAITCOUNT_MAX HDL_PARAMETER true
set_parameter_property LCDC_WAITCOUNT_MAX DERIVED true
set_parameter_property LCDC_WAITCOUNT_MAX VISIBLE $debugview


add_parameter EGL_SETTINGS_GLCDRESO integer 1
set_parameter_property EGL_SETTINGS_GLCDRESO DISPLAY_NAME "GLCD display resolution"
set_parameter_property EGL_SETTINGS_GLCDRESO ALLOWED_RANGES {"0:128 x 160 pixels" "1:240 x 320 pixels" "2:240 x 400 pixels" "3:320 x 480 pixels" "99:custom"}

add_parameter EGL_SETTINGS_LANDSCAPE boolean false
set_parameter_property EGL_SETTINGS_LANDSCAPE DISPLAY_NAME "Used by a landscape mode"
set_parameter_property EGL_SETTINGS_LANDSCAPE DISPLAY_HINT boolean

add_parameter EGL_SETTINGS_DISPX integer 240
set_parameter_property EGL_SETTINGS_DISPX DISPLAY_NAME "Horizontal resolution (pixel)"
set_parameter_property EGL_SETTINGS_DISPX ENABLED false
set_parameter_property EGL_SETTINGS_DISPX ALLOWED_RANGES 8:1024

add_parameter EGL_SETTINGS_DISPY integer 320
set_parameter_property EGL_SETTINGS_DISPY DISPLAY_NAME "Vertical resolution (pixel)"
set_parameter_property EGL_SETTINGS_DISPY ENABLED false
set_parameter_property EGL_SETTINGS_DISPY ALLOWED_RANGES 8:1024

add_parameter EGL_SETTINGS_VRAMSIZE integer 2
set_parameter_property EGL_SETTINGS_VRAMSIZE DISPLAY_NAME "VRAM area size"
set_parameter_property EGL_SETTINGS_VRAMSIZE ALLOWED_RANGES {"0:512 x 256 pixels" "1:512 x 512 pixels" "2:1024 x 512 pixels" "3:1024 x 1024 pixels" "4:2048 x 1024 pixels"}

add_parameter LCDC_WRSETUP_TIME integer 40
set_parameter_property LCDC_WRSETUP_TIME UNITS nanoseconds
set_parameter_property LCDC_WRSETUP_TIME DISPLAY_NAME "RS and D signal setup time"
set_parameter_property LCDC_WRSETUP_TIME ALLOWED_RANGES 1:500

add_parameter LCDC_WRWIDTH_TIME integer 120
set_parameter_property LCDC_WRWIDTH_TIME UNITS nanoseconds
set_parameter_property LCDC_WRWIDTH_TIME DISPLAY_NAME "nWR signal assert time"
set_parameter_property LCDC_WRWIDTH_TIME ALLOWED_RANGES 1:500

add_parameter LCDC_WRHOLD_TIME integer 40
set_parameter_property LCDC_WRHOLD_TIME UNITS nanoseconds
set_parameter_property LCDC_WRHOLD_TIME DISPLAY_NAME "RS and D signal hold time"
set_parameter_property LCDC_WRHOLD_TIME ALLOWED_RANGES 1:500



# 
# display items
# 

add_display_item "Graphics Settings" EGL_SETTINGS_GLCDRESO parameter
add_display_item "Graphics Settings" EGL_SETTINGS_LANDSCAPE parameter
add_display_item "Graphics Settings" EGL_SETTINGS_DISPX parameter
add_display_item "Graphics Settings" EGL_SETTINGS_DISPY parameter
add_display_item "Graphics Settings" EGL_SETTINGS_VRAMSIZE parameter

add_display_item "Timing Settings" LCDC_WRSETUP_TIME parameter
add_display_item "Timing Settings" LCDC_WRWIDTH_TIME parameter
add_display_item "Timing Settings" LCDC_WRHOLD_TIME parameter



#-----------------------------------
# Avalon-MM master interface
#-----------------------------------
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

add_interface_port reset csi_reset reset Input 1


# 
# connection point m1
# 
add_interface m1 avalon start
set_interface_property m1 addressUnits SYMBOLS
set_interface_property m1 associatedClock clock
set_interface_property m1 associatedReset reset
set_interface_property m1 bitsPerSymbol 8
set_interface_property m1 burstOnBurstBoundariesOnly false
set_interface_property m1 burstcountUnits WORDS
set_interface_property m1 doStreamReads false
set_interface_property m1 doStreamWrites false
set_interface_property m1 holdTime 0
set_interface_property m1 linewrapBursts false
set_interface_property m1 maximumPendingReadTransactions 0
set_interface_property m1 readLatency 0
set_interface_property m1 readWaitTime 1
set_interface_property m1 setupTime 0
set_interface_property m1 timingUnits Cycles
set_interface_property m1 writeWaitTime 0

add_interface_port m1 avm_m1_address address Output 31
add_interface_port m1 avm_m1_waitrequest waitrequest Input 1
add_interface_port m1 avm_m1_burstcount burstcount Output 4
add_interface_port m1 avm_m1_read read Output 1
add_interface_port m1 avm_m1_readdata readdata Input 16
add_interface_port m1 avm_m1_readdatavalid readdatavalid Input 1


#-----------------------------------
# Avalon-MM slave interface
#-----------------------------------
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
set_interface_property s1 readLatency 0
set_interface_property s1 readWaitTime 1
set_interface_property s1 setupTime 0
set_interface_property s1 timingUnits Cycles
set_interface_property s1 writeWaitTime 0

add_interface_port s1 avs_s1_address address Input 2
add_interface_port s1 avs_s1_read read Input 1
add_interface_port s1 avs_s1_readdata readdata Output 32
add_interface_port s1 avs_s1_write write Input 1
add_interface_port s1 avs_s1_writedata writedata Input 32
set_interface_assignment s1 embeddedsw.configuration.isFlash 0
set_interface_assignment s1 embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment s1 embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment s1 embeddedsw.configuration.isPrintableDevice 0


# 
# connection point s1_irq
# 
add_interface s1_irq interrupt end
set_interface_property s1_irq associatedAddressablePoint s1
set_interface_property s1_irq associatedClock clock
set_interface_property s1_irq associatedReset reset

add_interface_port s1_irq ins_s1_irq irq Output 1



#-----------------------------------
# Other condit interface
#-----------------------------------
# 
# connection point glcd
# 
add_interface glcd conduit end
set_interface_property glcd associatedClock clock
set_interface_property glcd associatedReset reset

add_interface_port glcd coe_lcd_rst_n rst_n Output 1
add_interface_port glcd coe_lcd_cs_n cs_n Output 1
add_interface_port glcd coe_lcd_rs rs Output 1
add_interface_port glcd coe_lcd_wr_n wr_n Output 1
add_interface_port glcd coe_lcd_d d Bidir 8



# *******************************************************************
#
#  Elaboration callback
#
# *******************************************************************

proc elaboration_callback {} {

	#-----------------------------------
	# lcd resolution settings
	#-----------------------------------

	set lcd_resolution [get_parameter_value EGL_SETTINGS_GLCDRESO]

	switch $lcd_resolution {
	"0" {
		set disp_x_size 128
		set disp_y_size 160
	}
	"1" {
		set disp_x_size 240
		set disp_y_size 320
	}
	"2" {
		set disp_x_size 240
		set disp_y_size 400
	}
	"3" {
		set disp_x_size 320
		set disp_y_size 480
	}
	"99" {
		set disp_x_size [get_parameter_value EGL_SETTINGS_DISPX]
		set disp_y_size [get_parameter_value EGL_SETTINGS_DISPY]

		if {[expr $disp_x_size % 8] != 0} {
			send_message error "Horizontal resolution has to set a multiple of 8."
		}
	}

	default {
		send_message error "Don't defined resolution."
	}}


	if {$lcd_resolution == 99} {
		set lcd_custom_setting true

	} else {
		set lcd_custom_setting false

		if {[get_parameter_value EGL_SETTINGS_LANDSCAPE]} {
			set temp $disp_x_size
			set disp_x_size $disp_y_size
			set disp_y_size $temp
		}
	}

	set_parameter_property EGL_SETTINGS_DISPX ENABLED $lcd_custom_setting
	set_parameter_property EGL_SETTINGS_DISPY ENABLED $lcd_custom_setting

	set_parameter_value	VRAM_VIEWWIDTH $disp_x_size
	set_parameter_value	VRAM_VIEWHEIGHT $disp_y_size


	#-----------------------------------
	# vram area settings
	#-----------------------------------

	set vram_settings_size [get_parameter_value EGL_SETTINGS_VRAMSIZE]

	switch $vram_settings_size {
	"0" {
		set vram_y_size 256
		set vram_lineshift 10
	}
	"1" {
		set vram_y_size 512
		set vram_lineshift 10
	}
	"2" {
		set vram_y_size 512
		set vram_lineshift 11
	}
	"3" {
		set vram_y_size 1024
		set vram_lineshift 11
	}
	"4" {
		set vram_y_size 1024
		set vram_lineshift 12
	}

	default {
		send_message error "Don't defined vram area."
	}}

	set vram_x_size [expr (1<<$vram_lineshift) / 2]
	set vram_areasize [expr $vram_x_size * $vram_y_size * 2]
	set_parameter_value VRAM_LINEBYTES [expr $vram_x_size * 2]

	if {$vram_x_size < $disp_x_size || $vram_y_size < $disp_y_size} {
		send_message warning "A display area exceeds VRAM territory."
	}


	#-----------------------------------
	# setup timing parameter
	#-----------------------------------

	set clock_frequency [get_parameter_value CLOCKFREQ]

	if {$clock_frequency == 0} {
		send_message warning "A connection of a clock is necessary for setting of timing."
	}

	set wr_setup_time [get_parameter_value LCDC_WRSETUP_TIME]
	set wr_setup_cycle [expr (ceil($wr_setup_time*(pow(10,-9)) * $clock_frequency))]
	set_parameter_value LCDC_WRSETUP_COUNT $wr_setup_cycle

	set wr_width_time [get_parameter_value LCDC_WRWIDTH_TIME]
	set wr_width_cycle [expr (ceil($wr_width_time*(pow(10,-9)) * $clock_frequency))]
	set_parameter_value LCDC_WRWIDTH_COUNT $wr_width_cycle

	set wr_hold_time [get_parameter_value LCDC_WRHOLD_TIME]
	set wr_hold_cycle [expr (ceil($wr_hold_time*(pow(10,-9)) * $clock_frequency))]
	set_parameter_value LCDC_WRHOLD_COUNT $wr_hold_cycle

	set wr_maximum_cycle 0
	if {$wr_setup_cycle > $wr_maximum_cycle} {set wr_maximum_cycle $wr_setup_cycle}
	if {$wr_width_cycle > $wr_maximum_cycle} {set wr_maximum_cycle $wr_width_cycle}
	if {$wr_hold_cycle  > $wr_maximum_cycle} {set wr_maximum_cycle $wr_hold_cycle}

	set_parameter_value LCDC_WAITCOUNT_MAX $wr_maximum_cycle


	#-----------------------------------
	# Software assignments
	#-----------------------------------

	set_module_assignment embeddedsw.CMacro.VRAM_PIXELCOLOR	"RGB555"
	set_module_assignment embeddedsw.CMacro.VRAM_MEMSIZE	[format %u $vram_areasize]
	set_module_assignment embeddedsw.CMacro.VRAM_LINESHIFT	[format %u $vram_lineshift]
	set_module_assignment embeddedsw.CMacro.VRAM_LINEBYTES	[format %u [get_parameter_value VRAM_LINEBYTES]]
	set_module_assignment embeddedsw.CMacro.VRAM_X_SIZE		[format %u $vram_x_size]
	set_module_assignment embeddedsw.CMacro.VRAM_Y_SIZE		[format %u $vram_y_size]
	set_module_assignment embeddedsw.CMacro.VRAM_VIEWWIDTH	[format %u [get_parameter_value VRAM_VIEWWIDTH]]
	set_module_assignment embeddedsw.CMacro.VRAM_VIEWHEIGHT	[format %u [get_parameter_value VRAM_VIEWHEIGHT]]
	set_module_assignment embeddedsw.CMacro.USE_LANDSCAPE	[expr ([get_parameter_value EGL_SETTINGS_LANDSCAPE]? 1 : 0)]

}
