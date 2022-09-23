# ===================================================================
# TITLE : PERIDOT Ethernet I/O Extender / SDC
#
#     DESIGN : s.osafune@j7system.jp (J-7SYSTEM WORKS LIMITED)
#     DATE   : 2022/09/23
#
# ===================================================================
#
# The MIT License (MIT)
# Copyright (c) 2022 J-7SYSTEM WORKS LIMITED.
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

set_false_path -to [get_registers {*|peridot_ethio_cdb_areset:*|in_areset_reg[0]}]
set_false_path -to [get_registers {*|peridot_ethio_cdb_signal:*|in_sig_reg[0]}]

set_false_path \
	-to [get_registers {*|peridot_ethio_cdb_vector:u_cdb_status|in_data_reg[*]}]
set_false_path \
	-to [get_registers {*|peridot_ethio_cdb_vector:u_cdb_param|in_data_reg[*]}]
set_false_path \
	-from [get_registers {*|peridot_ethio_cdb_stream:*|in_data_reg[*]}] \
	-to [get_registers {*|peridot_ethio_cdb_stream:*|peridot_ethio_cdb_vector:u_cdb3|in_data_reg[*]}]
set_false_path \
	-from [get_registers {*|peridot_ethio_cdb_get:*|in_data_reg[*]}] \
	-to [get_registers {*|peridot_ethio_cdb_get:*|peridot_ethio_cdb_vector:u_cdb3|in_data_reg[*]}]


