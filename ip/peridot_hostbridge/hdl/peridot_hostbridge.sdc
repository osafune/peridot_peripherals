# ===================================================================
# TITLE : PERIDOT-NG / Host bridge sdc
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2017/01/23 -> 2017/01/30
#
# ===================================================================
# *******************************************************************
#    (C)2016-2017, J-7SYSTEM WORKS LIMITED.  All rights Reserved.
#
# * This module is a free sourcecode and there is NO WARRANTY.
# * No restriction on use. You can use, modify and redistribute it
#   for personal, non-profit or commercial products UNDER YOUR
#   RESPONSIBILITY.
# * Redistributions of source code must retain the above copyright
#   notice.
# *******************************************************************

set_false_path -from [get_registers \{*\|altchip_id:*\|regout_wire\}] -to [get_registers \{*\|altchip_id:*\|lpm_shiftreg:shift_reg\|dffs\[63\]\}]
