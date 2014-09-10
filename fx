#!/usr/bin/env tclsh
## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Application fx   ?
# Meta author      {Andreas Kupries}
# Meta category    ?
# Meta description ?
# Meta location    http:/core.tcl.tk/akupries/fx
# Meta platform    tcl
# Meta require     fx
# Meta require     {Tcl 8.5-}
# Meta subject     ?
# Meta summary     ?
# @@ Meta End

package require Tcl 8.5
package require debug
package require debug::caller
package require cmdr::color

debug header {[::cmdr color {black bg-cyan} [clock format [clock seconds]]] }

package require fx
package require fx::atexit

# # ## ### ##### ######## ############# ######################

# (1) Process all --debug flags we can find. This is done before cmdr
#     gets hold of the command line to enable the debugging of the
#     innards of cmdr itself.
# 
# (2) Further activate debugging early when specified through the
#     environment
#
# TODO: Put both of these into Cmdr, as convenience commands.

set copy $argv
while {[llength $copy]} {
    set copy [lassign $copy first]
    if {$first ne "--debug"} continue
    set copy [lassign $copy tag]
    debug on $tag
}

if {[info exists env(FX_DEBUG)]} {
    foreach tag [split $env(FX_DEBUG) ,] {
	debug on [string trim $tag]
    }
}

# # ## ### ##### ######## ############# ######################
## Invoke the application code.
## Should possibly catch signals as well.

set status 1
try {
    set status [fx main $argv]
} finally {
    exit $status
}

# # ## ### ##### ######## ############# ######################
exit
