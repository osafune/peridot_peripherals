# ===================================================================
# TITLE : PERIDOT-NGS / Host bridge sdc
#
#   DEGISN : S.OSAFUNE (J-7SYSTEM WORKS LIMITED)
#   DATE   : 2017/01/23 -> 2017/01/30
#   MODIFY : 2017/04/07
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

set_false_path -from [get_registers {*|peridot_hostbridge:*|altchip_id:*|regout_wire}] -to [get_registers {*|peridot_hostbridge:*|altchip_id:*|dffs[63]}]
set_false_path -to [get_registers {*|peridot_hostbridge:*|peridot_board_i2c:*|scl_in_reg[0]}]
set_false_path -to [get_registers {*|peridot_hostbridge:*|peridot_board_i2c:*|sda_in_reg[0]}]
set_false_path -to [get_registers {*|peridot_hostbridge:*|peridot_config:*|streset_reg[0]}]
set_false_path -to [get_registers {*|peridot_hostbridge:*|peridot_config:*|perireset_reg[0]}]
set_false_path -to [get_registers {*|peridot_hostbridge:*|peridot_config_proc:*|scl_in_reg}]
set_false_path -to [get_registers {*|peridot_hostbridge:*|peridot_config_proc:*|sda_in_reg}]
set_false_path -to [get_registers {*|peridot_hostbridge:*|peridot_config_proc:*|bootsel_reg}]
set_false_path -to [get_registers {*|peridot_hostbridge:*|peridot_config_proc:*|nstatus_reg}]
set_false_path -to [get_registers {*|peridot_hostbridge:*|peridot_config_ru:*|nconfig_in_reg[0]}]
