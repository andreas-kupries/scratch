## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Package fx::validate::report-id 0
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
    namespace export report-id
    namespace ensemble create
}

# # ## ### ##### ######## ############# ######################
## Custom validation types: report-id (blobs)

namespace eval ::fx::validate::report-id {
    namespace export release validate default complete ok
    namespace ensemble create

    namespace import ::fx::fossil
    namespace import ::cmdr::validate::common::fail-unknown-thing
    namespace import ::cmdr::validate::common::complete-enum
}

proc ::fx::validate::report-id::default  {p}   { return {} }
proc ::fx::validate::report-id::release  {p x} { return }
proc ::fx::validate::report-id::validate {p x} {
    set matches [fossil repository onecolumn {
	SELECT count(*)
	FROM reportfmt
	WHERE rn    = :x
	OR    title = :x
    }]

    if {$matches == 1} {
	return $x
    }
    fail-unknown-thing $p REPORT-ID "report name or id" $x
}

proc ::fx::validate::report-id::ok {x} {
    set matches [fossil repository onecolumn {
	SELECT count(*)
	FROM reportfmt
	WHERE rn    = :x
	OR    title = :x
    }]
    return [expr {$matches == 1}]
}

proc ::fx::validate::report-id::complete {p} {
    complete-enum [Values $p] 0 $x
}

proc ::fx::validate::report-id::Values {p} {
    # Force parameter, validation can happen
    # before the cmdr completion phase.
    $p config @repository-db
    return [fossil repository eval {
	SELECT rn    FROM reportfmt
	UNION
	SELECT title FROM reportfmt
    }]
}

# # ## ### ##### ######## ############# ######################
package provide fx::validate::report-id 0
return
