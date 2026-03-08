# SPDX-License-Identifier: Apache-2.0
# File: top.xdc
# Purpose: Constraints placeholder for FPGA builds
# TODO:
# - Replace placeholders with board-specific constraints

## Clock inputs (comment templates)
# create_clock -name refclk100 -period 10.000 [get_ports refclk]         ;# 100 MHz
# create_clock -name refclk156 -period 6.400  [get_ports refclk_156m25]  ;# 156.25 MHz
# create_clock -name refclk250 -period 4.000  [get_ports refclk_250m]    ;# 250 MHz

## Reset (active-low)
# set_property PULLUP true [get_ports rst_btn_n]

## IO pin assignments (example)
# set_property PACKAGE_PIN W5 [get_ports refclk]
# set_property IOSTANDARD LVCMOS18 [get_ports refclk]
