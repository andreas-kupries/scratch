## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Package fx::validate::enum 0
# Meta author      {Andreas Kupries}
# Meta category    ?
# Meta description ?
# Meta location    http:/core.tcl.tk/akupries/fossil2git
# Meta platform    tcl
# Meta require     ?
# Meta subject     ?
# Meta summary     ?
# @@ Meta End

# # ## ### ##### ######## ############# ######################

package require Tcl 8.5
package require fx::fossil
package require cmdr::validate::common

# # ## ### ##### ######## ############# ######################

namespace eval ::fx::validate {
    namespace export enum
    namespace ensemble create
}

# # ## ### ##### ######## ############# ######################
## Custom validation types: enumerations and items.

namespace eval ::fx::validate::enum {
    namespace export release validate default complete
    namespace ensemble create

    namespace import ::fx::fossil::fx-enums
    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
}

proc ::fx::validate::enum::release  {p x} { return }
proc ::fx::validate::enum::validate {p x} {
    set cx [string tolower $x]
    if {$cx in [Values $p]} {
	# Internal representation is the enum table.
	return fx_aku_enum_$cx
    }
    fail $p ENUM "an enumeration" $x
}

proc ::fx::validate::enum::default  {p} { return {} }
proc ::fx::validate::enum::complete {p} {
    complete-enum list [Values $p] $x
}

proc ::fx::validate::enum::Values {p} {
    return [fx-enums [$p config @repository-db]]
}

# # ## ### ##### ######## ############# ######################
package provide fx::validate::enum 0
return
