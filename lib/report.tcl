## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Package fx::report 0
# Meta author      ?
# Meta category    ?
# Meta description ?
# Meta location    http:/core.tcl.tk/akupries/fx
# Meta platform    tcl
# Meta require     ?
# Meta subject     ?
# Meta summary     ?
# @@ Meta End

package require Tcl 8.5
#package require cmdr::color
package require debug
package require debug::caller
#package require interp
#package require linenoise
#package require textutil::adjust
#package require try

#package require fx::fossil
#package require fx::mgr::report
#package require fx::table
#package require fx::util
#package require fx::validate::report

# # ## ### ##### ######## ############# ######################

namespace eval ::fx::report {
    namespace export \
	add delete rename redefine set-colors \
	list export import edit run \
	template-set-sql template-set-colors
    namespace ensemble create

#     namespace import ::cmdr::color
#     namespace import ::fx::fossil
#     namespace import ::fx::util

#     namespace import ::fx::table::do
#     rename do table
}

# # ## ### ##### ######## ############# ######################

debug level  fx/report
debug prefix fx/report {[debug caller] | }

# # ## ### ##### ######## ############# ######################

proc ::fx::report::add {config} {
}

proc ::fx::report::delete {config} {
}

proc ::fx::report::rename {config} {
}

proc ::fx::report::redefine {config} {
}

proc ::fx::report::set-colors {config} {
}

proc ::fx::report::list {config} {
}

proc ::fx::report::export {config} {
}

proc ::fx::report::import {config} {
}

proc ::fx::report::edit {config} {
}

proc ::fx::report::run {config} {
}

proc ::fx::report::template-set-sql {config} {
}

proc ::fx::report::template-set-colors {config} {
}

# # ## ### ##### ######## ############# ######################
package provide fx::report 0
return
