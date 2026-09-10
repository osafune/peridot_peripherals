# ===================================================================
# TITLE : PERIDOT ESN - Reservoir core / SDC
#
#     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
#     DATE   : 2026/03/18
#
# ===================================================================
#
# The MIT License (MIT)
# Copyright (c) 2026 J-7SYSTEM WORKS LIMITED.
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


# ---------------------------------------------
# Set false path
# ---------------------------------------------

set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|core_reset_n_reg}] \
	-to [get_registers {*|peridot_esn_csr:u_csr|reset_n_out_reg[*]}]
set_false_path \
	-to [get_registers {*|peridot_esn_csr:u_csr|start_out_reg[0]}]
set_false_path \
	-to [get_registers {*|peridot_esn_csr:u_csr|busy_in_reg[0]}]

set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|working_page_reg}] \
	-to [get_registers {*|peridot_esn_input:u_input|working_page_reg}]
set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|clear_reg}] \
	-to [get_registers {*|peridot_esn_input:u_input|state_clear_reg}]
set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|n_node_reg[*]}] \
	-to [get_registers {*|peridot_esn_input:u_input|row_count_reg[*]}]
set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|n_input_reg[*]}] \
	-to [get_registers {*|peridot_esn_input:u_input|n_input_reg[*]}]
set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|n_output_reg[*]}] \
	-to [get_registers {*|peridot_esn_input:u_input|n_output_reg[*]}]
set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|seed_reg[*]}] \
	-to [get_registers {*|peridot_esn_input:u_input|peridot_esn_xorshift32:u_rand|x_reg[*]}]
set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|scale_in_reg[*]}] \
	-to [get_registers {*|peridot_esn_input:u_input|scale_in_reg[*]}]
set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|scale_fb_reg[*]}] \
	-to [get_registers {*|peridot_esn_input:u_input|scale_fb_reg[*]}]

set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|clear_reg}] \
	-to [get_registers {*|peridot_esn_reservoir:u_reservoir|state_clear_reg}]
set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|n_node_reg[*]}] \
	-to [get_registers {*|peridot_esn_reservoir:u_reservoir|n_node_reg[*]}]
set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|seed_reg[*]}] \
	-to [get_registers {*|peridot_esn_reservoir:u_reservoir|peridot_esn_xorshift32:u_rand|x_reg[*]}]
set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|density_reg[*]}] \
	-to [get_registers {*|peridot_esn_reservoir:u_reservoir|density_reg[*]}]
set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|scale_wres_reg[*]}] \
	-to [get_registers {*|peridot_esn_reservoir:u_reservoir|scale_wres_reg[*]}]
set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|scale_lr_reg[*]}] \
	-to [get_registers {*|peridot_esn_reservoir:u_reservoir|scale_lr_reg[*]}]

set_false_path \
	-from [get_registers {*|peridot_esn_csr:u_csr|n_output_reg[*]}] \
	-to [get_registers {*|peridot_esn_readout:u_readout|n_output_reg[*]}]

set_false_path \
	-from [get_registers {*|peridot_esn_reservoir:u_reservoir|working_page_reg}] \
	-to [get_registers {*|peridot_esn_reservoir:u_reservoir|mem_page_reg}]
