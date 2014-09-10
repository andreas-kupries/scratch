## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Package fx::validate::not-report-id 0
# Meta author      {Andreas Kupries}
# Meta category    ?
# Meta description ?
# Meta location    http:/core.tcl.tk/akupries/fx
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
    namespace export not-report-id
    namespace ensemble create
}

# # ## ### ##### ######## ############# ######################
## Custom validation types: not-report-id (report names|titles)

namespace eval ::fx::validate::not-report-id {
    namespace export release validate default complete
    namespace ensemble create

    namespace import ::fx::fossil
    namespace import ::cmdr::validate::common::fail-known-thing
}

proc ::fx::validate::not-report-id::default  {p}   { return {} }
proc ::fx::validate::not-report-id::complete {p}   { return {} }
proc ::fx::validate::not-report-id::release  {p x} { return }
proc ::fx::validate::not-report-id::validate {p x} {
    set matches [fossil repository onecolumn {
	SELECT count(*)
	FROM   reportfmt
	WHERE  title = :x
    }]

    if {!$matches} {
	return $x
    }
    fail-known-thing $p NOT-REPORT-ID "report name" $x
}

# # ## ### ##### ######## ############# ######################
package provide fx::validate::not-report-id 0
return
