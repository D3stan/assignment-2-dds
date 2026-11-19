# Only let GDB access memory that exists on the Didactic-SoC.
# Any access to an unmapped address (e.g. 0x0, which GDB's frame unwinder
# probes) never completes on the OBI bus: the core hangs, the debug module
# stays "busy" and OpenOCD/GDB report packet errors ("Invalid hex digit 116").
mem 0x01000000 0x01004000 rw
mem 0x01010000 0x01014000 rw
mem 0x01050000 0x01050014 rw
set mem inaccessible-by-default on
set backtrace past-main off

target extended-remote localhost:3333
load
