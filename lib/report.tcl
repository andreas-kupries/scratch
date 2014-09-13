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
package require cmdr::color
package require debug
package require debug::caller
#package require interp
#package require linenoise
#package require textutil::adjust
#package require try
package require json::write

package require fx::fossil
#package require fx::mgr::report
package require fx::table
#package require fx::util
#package require fx::validate::report

# # ## ### ##### ######## ############# ######################

namespace eval ::fx::report {
    namespace export \
	add delete rename redefine set-colors \
	list export import edit run \
	template-set-sql template-set-colors
    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::fx::fossil
#     namespace import ::fx::util

    namespace import ::fx::table::do
    rename do table
}

# # ## ### ##### ######## ############# ######################

debug level  fx/report
debug prefix fx/report {[debug caller] | }

# # ## ### ##### ######## ############# ######################

proc ::fx::report::add {config} {
    # @owner, @title, @spec

    fossil show-repository-location

    set owner [$config @owner]
    set title [$config @title]
    set spec  [$config @spec]

    puts -nonewline "Add new report [color name $title] ... "

    # TODO: Normalization and validation of the sql-code
    # TODO: Use procedure, re-usable in import, redefine, edit, etc.
    #
    # Trial compilation:
    # - must be read-only (only SELECT allowed)
    # - must not access forbidden tables.
    # -> authorizer
    # - deny recursive
    # Strip/cleanup white-space.

    # -> f r authorizer cmd - set
    # -> f r authorizer {}  - unset
    # cmd (op .1 .2 db trigger) -> SQLITE_{OK,IGNORE,DENY}
    # op = SQLITE_{SELECT,FUNCTION,READ,RECURSIVE,...}
    #              ok     ok       table,deny,    deny
    # table => .1 = table name, allowed:
    #   fx_*, ticket ticketchng blob filename mlink plink
    #   event tag tagxref

    fossil repository eval {
	INSERT
	INTO reportfmt
	VALUES (NULL,:owner,:title,now(),'',:spec)
    }

    # f r last_insert_rowid => print number.

    puts [color good OK]
    return
}

proc ::fx::report::delete {config} {
    # @id (rn)
    fossil show-repository-location

    set rn [$config @id]

    puts -nonewline "Delete report [color name $rn] ... "
    fossil repository eval {
	DELETE
	FROM reportfmt
	WHERE rn = :rn
    }

    puts [color good OK]
    return
}

proc ::fx::report::rename {config} {
    # @id (rn), @newname
    fossil show-repository-location

    set rn  [$config @id]
    set new [$config @newname]

    puts -nonewline "Rename report [color name $rn] to [color name $new] ... "
    fossil repository eval {
	UPDATE reportfmt
	SET title = :new
	WHERE rn = :rn
    }

    puts [color good OK]
    return
}

proc ::fx::report::redefine {config} {
    fossil show-repository-location

    set rn   [$config @id]
    set spec [$config @spec]

    puts -nonewline "Redefine report [color name $rn] definition ... "
    fossil repository eval {
	UPDATE reportfmt
	SET sqlcode = :spec
	WHERE rn = :rn
    }

    puts [color good OK]
    return
}

proc ::fx::report::set-colors {config} {
    fossil show-repository-location

    set rn     [$config @id]
    set colors [$config @colors]

    puts -nonewline "Redefine report [color name $rn] colors ... "
    fossil repository eval {
	UPDATE reportfmt
	SET cols = :colors
	WHERE rn = :rn
    }

    puts [color good OK]
    return
}

proc ::fx::report::list {config} {
    # @json, @raw

    set defs [fossil repository eval {
	SELECT rn, owner, title, datetime(mtime,'unixepoch')
	FROM reportfmt
	--ORDER BY title, owner
	ORDER BY rn
    }]

    if {[$config @json]} {
	foreach {id owner title mtime} $defs {
	    lappend tmp \
		[json::write object \
		     id    $id \
		     owner [json::write string $owner] \
		     title [json::write string $title] \
		     mtime [json::write string $mtime]
	}
	puts [json::write array {*}$tmp]

    } elseif {[$config @raw]} {
	foreach {id owner title mtime} $defs {
	    puts $title
	}
    } else {
	fossil show-repository-location
	[table t {Id Title Owner Created} {
	    foreach {id owner title mtime} $defs {
		$t add \
		    $id \
		    [color name $title] \
		    $owner \
		    $mtime
	    }
	}] show
    }
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
