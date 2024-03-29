# ===================================================================
# TITLE : PERIDOT-NGS / OmniVision DVP I/F SDC
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2017/04/04 -> 2017/04/06
#          : 2023/01/04
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

set_false_path -to [get_keepers {*|peridot_cam:*|peridot_cam_avs:u_csr|fsync_in_reg[0]}]
set_false_path -to [get_keepers {*|peridot_cam:*|peridot_cam_avs:u_csr|done_in_reg[0]}]
set_false_path -from [get_keepers {*|peridot_cam:*|peridot_cam_avs:u_csr|fiforeset_reg}]

set_false_path -from [get_keepers {*|peridot_cam:*|camvsync_reg}] -to [get_keepers {*|peridot_cam:*|fsync_in_reg[0]}]
set_false_path -from [get_keepers {*|peridot_cam:*|peridot_cam_avs:u_csr|execution_reg}] -to [get_keepers {*|peridot_cam:*|exec_in_reg[0]}]
set_false_path -from [get_keepers {*|peridot_cam:*|peridot_cam_avs:u_csr|capaddress_reg[*]}] -to  [get_keepers {*|peridot_cam:*|peridot_cam_avm:u_avm|address_reg[*]}]
set_false_path -from [get_keepers {*|peridot_cam:*|peridot_cam_avs:u_csr|capcyclenum_reg[*]}] -to  [get_keepers {*|peridot_cam:*|peridot_cam_avm:u_avm|chunkcount_reg[*]}]
