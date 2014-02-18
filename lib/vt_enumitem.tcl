## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Package fx::validate::enum-item 0
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

namespace eval ::fx::validate::enum-item {
    namespace export release validate default complete
    namespace ensemble create

    namespace import ::fx::fossil::fx-enums
    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
}

proc ::fx::validate::enum-item::release  {p x} { return }
proc ::fx::validate::enum-item::validate {p x} {
    if {$x in [Values $p]} { return $x }
    fail $p ENUM-ITEM "an enumeration item" $x
}

proc ::fx::validate::enum-item::default  {p} { return {} }
proc ::fx::validate::enum-item::complete {p} {
    complete-enum list [Values $p] $x
}

proc ::fx::validate::enum-item::Values {p} {
    return [fx-enum-items \
		[$p config @repository-db] \
		[$p config @enum]]
}

# # ## ### ##### ######## ############# ######################
package provide fx::validate::enum-item 0
return