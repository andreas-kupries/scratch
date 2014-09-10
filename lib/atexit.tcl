## -*- tcl -*-
# # ## ### ##### ######## #############

# @@ Meta Begin
# Package fx::atexit 0
# Meta author      {Andreas Kupries}
# Meta category    ?
# Meta description ?
# Meta location    http:/core.tcl.tk/akupries/fx
# Meta platform    tcl
# Meta require     sqlite3
# Meta subject     fossil
# Meta summary     ?
# @@ Meta End

package require Tcl 8.5

debug level  fx/atexit
debug prefix fx/atexit {[debug caller] | }

# # ## ### ##### ######## #############

namespace eval ::fx {
    namespace export atexit
    namespace ensemble create
}
namespace eval ::fx::atexit {
    namespace export add
    namespace ensemble create
}

# # ## ### ##### ######## #############

proc ::fx::atexit::add {cmdprefix} {
    debug.fx/atexit {}
    variable handlers
    lappend  handlers $cmdprefix
    return
}

proc ::fx::atexit::Exit {args} {
    debug.fx/atexit {}
    variable ::fx::atexit::handlers
    foreach cmd $handlers {
	debug.fx/atexit {=> $cmd}
	catch {
	    uplevel #0 $cmd
	}
    }
    set handlers {}
    ::fx::atexit::Exit.orig {*}$args
}

# # ## ### ##### ######## #############
## Hook into process exit.

namespace eval ::fx::atexit {
    variable handlers {}
}

rename ::exit             ::fx::atexit::Exit.orig
rename ::fx::atexit::Exit ::exit

# # ## ### ##### ######## #############

package provide fx::atexit 0
