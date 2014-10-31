## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Package fx::validate::import-mode 0
# Meta author      {Andreas Kupries}
# Meta category    ?
# Meta description ?
# Meta location    http:/core.tcl.tk/akupries/fx
# Meta platform    tcl
# Meta require     ?
# Meta subject     ?
# Meta summary     ?
# @@ Meta End

package require Tcl 8.5
package require cmdr::validate::common

# # ## ### ##### ######## ############# ######################

namespace eval ::fx::validate {
    namespace export import-mode
    namespace ensemble create
}

# # ## ### ##### ######## ############# ######################
## Custom validation type, legal validateuration import-modes

namespace eval ::fx::validate::import-mode {
    namespace export release validate default complete legal
    namespace ensemble create

    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
}

proc ::fx::validate::import-mode::release  {p x} { return }
proc ::fx::validate::import-mode::validate {p x} {
    set cx [string tolower $x]
    if {$cx in [legal]} { return $cx }
    fail $p IMPORT-MODE "a configuration area" $x
}

proc ::fx::validate::import-mode::default  {p} { return replace }
proc ::fx::validate::import-mode::complete {p} {
    complete-enum [legal] 1 $x
}

# # ## ### ##### ######## ############# ######################

proc ::fx::validate::import-mode::legal {} {
    return {replace overwrite extend}
    # Note: content is not a regular configuration area.
    # However by adding it we can simplify the cli interface
    # for fossil peers, subsuming normal content as a special
    # type of configuration we can exchange.
}

# # ## ### ##### ######## ############# ######################
package provide fx::validate::import-mode 0
return
