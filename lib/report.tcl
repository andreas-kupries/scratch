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
	add delete rename set-sql set-colors \
	set-owner copy show listing export import \
	edit run template-set-sql template-set-colors
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
    # TODO: Use procedure, re-usable in import, set-sql, edit, etc.
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

    set now [clock seconds]
    fossil repository eval {
	INSERT
	INTO reportfmt
	VALUES (NULL,:owner,:title,:now,'',:spec)
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

proc ::fx::report::copy {config} {
    # @id (rn), @newname
    fossil show-repository-location

    set rn    [$config @id]
    set owner [$config @owner]
    set title [$config @newname]
    set now   [clock seconds]

    puts -nonewline "Copy report [color name $rn] to [color name $title] ... "

    fossil repository transaction {
	lassign [fossil repository eval {
	    SELECT cols, sqlcode
	    FROM reportfmt
	    WHERE rn = :rn
	}] colors sqlcode

	fossil repository eval {
	    INSERT
	    INTO reportfmt
	    VALUES (NULL,:owner,:title,:now,:colors,:sqlcode)
	}
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

proc ::fx::report::set-sql {config} {
    fossil show-repository-location

    set rn   [$config @id]
    set spec [$config @spec]
    set now  [clock seconds]

    # TODO : Validate new spec, see 'add'.

    puts -nonewline "Redefine report [color name $rn] definition ... "
    fossil repository eval {
	UPDATE reportfmt
	SET sqlcode = :spec,
	    mtime   = :now
	WHERE rn = :rn
    }

    puts [color good OK]
    return
}

proc ::fx::report::set-colors {config} {
    fossil show-repository-location

    set rn     [$config @id]
    set colors [$config @colors]
    set now    [clock seconds]

    puts -nonewline "Redefine report [color name $rn] colors ... "
    fossil repository eval {
	UPDATE reportfmt
	SET cols  = :colors,
	    mtime = :now
	WHERE rn = :rn
    }

    puts [color good OK]
    return
}

proc ::fx::report::set-owner {config} {
    fossil show-repository-location

    set rn    [$config @id]
    set owner [$config @owner]
    set now   [clock seconds]

    puts -nonewline "Redefine report [color name $rn] owner ... "
    fossil repository eval {
	UPDATE reportfmt
	SET owner = :owner,
	    mtime = :now
	WHERE rn = :rn
    }

    puts [color good OK]
    return
}

proc ::fx::report::show {config} {
    set rn    [$config @id]
    set parts [$config @only]

    lassign [fossil repository eval {
	SELECT owner, title, datetime(mtime,'unixepoch'), cols, sqlcode
	FROM reportfmt
	WHERE rn = :rn
    }] owner title mtime colors sqlcode

    if {[$config @json]} {
	switch -- $parts {
	    sql {
		puts [json::write string $sqlcode]
	    }
	    color {
		puts [json::write string $colors]
	    }
	    all {
		puts [json::write object \
			  id     $rn \
			  owner  [json::write string $owner]  \
			  title  [json::write string $title]  \
			  mtime  [json::write string $mtime]  \
			  colors [json::write string $colors] \
			  sql    [json::write string $sqlcode]]
	    }
	}
    } elseif {[$config @raw]} {
	switch -- $parts {
	    sql {
		puts $sqlcode
	    }
	    color {
		puts $colors
	    }
	    all {
		puts $owner
		puts $title
		puts $mtime
		puts --
		puts $colors
		puts --
		puts $sqlcode
	    }
	}
    } else {
	fossil show-repository-location
	puts "Report [color name $rn] ... "
	[table t {Key Value} {
	    if {$parts eq "all"} {
		$t add Owner      $owner
		$t add Title      [color name $title]
		$t add Created    $mtime
		$t add ---------- -------------------
	    }
	    if {$parts in {all color}} {
		$t add Color-Key  $colors
	    }
	    if {$parts eq "all"} {
		$t add ---------- -------------------
	    }
	    if {$parts in {all sql}} {
		$t add Definition $sqlcode
	    }
	}] show
    }
    return
}

proc ::fx::report::listing {config} {
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
		     mtime [json::write string $mtime]]
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
