## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Package fx::validate::report-part 0
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
    namespace export report-part
    namespace ensemble create
}

# # ## ### ##### ######## ############# ######################
## Custom validation type, legal validateuration report-parts

namespace eval ::fx::validate::report-part {
    namespace export release validate default complete legal
    namespace ensemble create

    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
}

proc ::fx::validate::report-part::release  {p x} { return }
proc ::fx::validate::report-part::validate {p x} {
    set cx [string tolower $x]
    if {$cx in [legal]} { return $cx }
    fail $p REPORT-PART "a report-part" $x
}

proc ::fx::validate::report-part::default  {p} { return all }
proc ::fx::validate::report-part::complete {p} {
    complete-enum [legal] 1 $x
}

# # ## ### ##### ######## ############# ######################

proc ::fx::validate::report-part::legal {} {
    return {sql color}
}

# # ## ### ##### ######## ############# ######################
package provide fx::validate::report-part 0
return
