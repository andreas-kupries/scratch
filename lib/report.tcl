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
package require sha1 2
package require cmdr::color
package require debug
package require debug::caller
package require dictutil
#package require interp
#package require linenoise
#package require textutil::adjust
#package require try
package require json::write

package require fx::fossil
package require fx::mgr::config
#package require fx::mgr::report
package require fx::table
package require fx::util
#package require fx::validate::report

# # ## ### ##### ######## ############# ######################

namespace eval ::fx::report {
    namespace export \
	add delete rename copy show listing export import \
	run edit set-sql set-colors set-owner \
	template-set template-show template-reset
    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::fx::fossil
    namespace import ::fx::util
    namespace import ::fx::mgr::config

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

    Add $title $owner $spec {}

    puts [color good OK]
    return
}

proc ::fx::report::delete {config} {
    # @id (rn)
    fossil show-repository-location

    set rn [$config @id]

    puts -nonewline "Delete report [color name $rn] ... "

    # drop by report id (we also have by title, see import)
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
	lassign [Get $rn] _o _t _m colors sqlcode

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

    puts -nonewline "Redefine report [color name $rn] definition ... "

    # TODO : Validate new spec, see 'Add'.

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

    lassign [Get $rn] owner title mtime colors sqlcode

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
    fossil show-repository-location

    set parts [$config @only]

    if {[$config @id set?]} {
	set reports [$config @id]
    } else {
	set reports [fossil fx-reports]
    }

    if {[$config @exploded]} {
	# @output is a directory.
	# TODO: wpath validation ...
	# cmdr --> conditional VT, boolean

	foreach rn $reports {
	    puts -nonewline "Exporting report [color name $rn] ... "

	    lassign [Get $rn] owner title _m colors sqlcode

	    regsub -all {[^[:alnum:]]} $title {} fname
	    append fname .[sha1::sha1 -hex $title]

	    # TODO: Use report title for report directory name, strip
	    # non-alphanumeric parts, and add serial numbers where the
	    # result is not unique.
	    set dst [$config @output]/$fname

	    file mkdir $dst

	    fileutil::writeFile $dst/title $title\n
	    fileutil::writeFile $dst/owner $owner\n

	    if {$parts in {all color}} {
		fileutil::writeFile $dst/colors $colors\n
	    }
	    if {$parts in {all sql}} {
		fileutil::writeFile $dst/sql $sqlcode\n
	    }

	    puts [color good OK]
	}
	return
    }

    set chan [util open [$config @output]]
    foreach rn $reports {
	puts -nonewline "Exporting report [color name $rn] ... "

	lassign [Get $rn] owner title _m colors sqlcode
	Write $chan $parts $owner $title $colors $sqlcode

	puts [color good OK]
    }

    close $chan
    return
}

proc ::fx::report::import {config} {
    # Parameters
    # @input - channel to read from
    # @import-mode
    # - replace all         = replace
    # - replace on conflict = overwrite
    # - ignore on conflict  = extend

    fossil show-repository-location
    Import [$config @input] [$config @import-mode]
    return
}

proc ::fx::report::edit {config} {
    # Parameters
    # @id   - optional => use color/sql templates
    # @only - which parts to edit.
    #
    # Workflow: Export to temp file, call, editor, import result back (replace on conflict).
    # ... Ignore title on import ?
    # ... Block import of multiple reports ?

    set parts [$config @only]

    if {[$config @id set?]} {
	# Get report
	set rn [$config @id]
	lassign [Get $rn] owner title _m colors sqlcode
    } else {
	# No report, use the templates instead.
	set owner   $tcl_platform(user)
	set title   Untitled
	set colors  [GetColorTemplate]
	set sqlcode [GetSqlTemplate]
    }

    # Export it
    set tmp [fileutil::tempfile fx_redit_]
    set chan [open $tmp w]
    Write $chan $parts
    close $chan

    # Choose editor application
    if {[info exists env(VISUAL)]} {
	set cmd $env(VISUAL)
    } elseif {[info exists env(EDITOR)]} {
	set cmd $env(EDITOR)
    } else {
	set cmd vi
    }

    # Run editor
    exec 2>@ stderr >@ stdout <@ stdin {*}$cmd $tmp

    # And import the results
    Import [open $tmp r] overwrite

    file delete $tmp
    return
}

proc ::fx::report::run {config} {
    # Parameters
    # @id - optional. undefined => Take stdin.
    # @raw, @json

}

# # ## ### ##### ######## ############# ######################

proc ::fx::report::template-set {config} {
    fossil show-repository-location

    switch -exact -- [$config @part] {
	sql {
	    set key  ticket-report-template
	    set head "Setting report template ... "
	}
	color {
	    set key  ticket-key-template
	    set head "Setting color key template ... "
	}
    }

    puts -nonewline $head
    config set-local $key [$config @text]
    puts [color good OK]
    return
}

proc ::fx::report::template-reset {config} {
    fossil show-repository-location

    switch -exact -- [$config @part] {
	sql {
	    set key  ticket-report-template
	    set head "Resetting report template ... "
	}
	color {
	    set key  ticket-key-template
	    set head "Resetting color key template ... "
	}
    }

    puts -nonewline $head
    config unset-local $key
    puts [color good OK]
    return
}

proc ::fx::report::template-show {config} {
    switch -exact -- [$config @part] {
	sql {
	    set text [GetSqlTemplate]
	    set head "Show report template ... "
	}
	color {
	    set text [GetColorTemplate]
	    set head "Show color key template ... "
	}
    }

    if {[$config @json]} {
	puts [json::write string $text]

    } elseif {[$config @raw]} {
	puts $text

    } else {
	fossil show-repository-location
	puts $head
	[table t Value {
	    $t add $text
	}] show
    }

    return
}

# # ## ### ##### ######## ############# ######################

proc ::fx::report::Write {chan parts owner title colors sql} {
    puts $chan [list @@ -------------------------]
    puts $chan [list @title $title]
    puts $chan [list @owner $owner]

    if {($parts in {all color}) && ($colors ne {})} {
	puts $chan @colors
	puts $chan $colors
	puts $chan @/colors
	puts $chan {}
    }
    if {($parts in {all sql}) && ($sqlcode ne {})} {
	puts $chan @sql
	puts $chan $sqlcode
	puts $chan @/sql
	puts $chan {}
    }
    return
}

proc ::fx::report::Read {chan} {
    set state cmd
    set definitions {}
    array set current {}

    while {[gets $chan line] >= 0} {
	switch -exact -- $state {
	    cmd {
		switch -glob -- [string trim $line] {
		    {@@*} continue
		    {@title *} {
			SaveCurrent
			set current(title) [string trim [string range $line 7 end]]
		    }
		    {@owner *} {
			set current(owner) [string trim [string range $line 7 end]]
		    }
		    {@colors} {
			set state colors
		    }
		    {@sql} {
			set state sql
		    }
		    * {
			# TODO ERROR
		    }
		}
	    }
	    colors {
		# Wait for any @ command, and record everything else as the color key lines.
		# @title also triggers starting of the next report

		switch -glob -- [string trim $line] {
		    {@@*} -
		    {@/sqlcode} {
			# TODO ERROR
		    }
		    {@/colors} {
			set state cmd
		    }
		    {@title *} {
			SaveCurrent
			set current(title) [string trim [string range $line 7 end]]
		    }
		    {@owner *} {
			set current(owner) [string trim [string range $line 7 end]]
			set state cmd
		    }
		    {@colors*} {
			# Reset definition
			unset current(colors)
		    }
		    {@sql*} {
			set state sql
		    }
		    * {
			append current(colors) $line\n
		    }
		}
	    }
	    sql {
		# Wait for any @ command, and record everything else as the report lines.
		# @title also triggers starting of the next report

		switch -glob -- [string trim $line] {
		    {@@*} -
		    {@/colors} {
			# TODO ERROR
		    }
		    {@/sql} {
			set state cmd
		    }
		    {@title *} {
			SaveCurrent
			set current(title) [string trim [string range $line 7 end]]
		    }
		    {@owner *} {
			set current(owner) [string trim [string range $line 7 end]]
			set state cmd
		    }
		    {@colors} {
			set state colors
		    }
		    {@sql} {
			# Reset definition
			unset current(sql)
		    }
		    * {
			append current(sql) $line\n
		    }
		}
	    }
	}
    }

    SaveCurrent
    return $definitions
}

proc ::fx::report::SaveCurrent {} {
    upvar 1 current current definitions definitions
    if {![array size current]} return

    if {![info exists current(title)]} {
	# Ignore unnamed definition
	puts [color bad "Ignoring unnamed definition"
	return
    }
    if {![info exists current(colors)] &&
	 [info exists current(sql)]} {
	# Ignore empty definition
	puts [color warning "Ignoring empty definition $current(title)"]
	return
    }

    lappend definitions [array get current]
    array unset current *
    return
}

proc ::fx::report::Import {chan mode} {
    set defs [Read $chan]
    close $chan

    # Process definitions as per mode.
    # Be verbose too.

    if {$mode eq "replace"} {
	puts -nonewline [color warning "Import replaces all existing reports ..."]
	# Inlined delete of all reports
	fossil repository eval {
	    DELETE FROM reportfmt
	}
	puts [color good Done]
    }

    foreach def $defs {
	# def = dict (title, owner, colors, sql)
	# title       will be set.
	# owner       may be set.
	# colors, sql too, except one will be set.

	set title  [dict get  $def title]
	set owner  [dict get' $def owner  $tcl_platform(user)]
	set sql    [dict get' $def sql    {}]
	set colors [dict get' $def colors {}]

	puts -nonewline "  Importing [color name $title] ... "
	flush stdout

	set known [Has $title]
	if {($mode in {overwrite replace}) || !$known} {
	    try {
		fossil repository transaction {
		    if {$known} { DropByTitle $title }
		    Add $title $owner $sql $colors
		}
	    } on error {e o} {
		puts [color error $e]
	    } on ok {e o} {
		set ok OK
		if {$mode eq "overwrite"} { append ok ", replaced known" }
		puts [color good $ok]
	    }
	} else {
	    # extend, known --> ignore
	    puts [color warning "Ignored, already known"]
	}
    }
    return
}
# # ## ### ##### ######## ############# ######################

proc ::fx::report::Add {title owner sql colors} {

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
	VALUES (NULL,:owner,:title,:now,:colors,:spec)
    }

    # f r last_insert_rowid => print number.

    return
}

proc ::fx::report::Get {rn} {
    return [fossil repository eval {
	SELECT owner, title, datetime(mtime,'unixepoch'), cols, sqlcode
	FROM reportfmt
	WHERE rn = :rn
    }]
}

proc ::fx::report::Has {title} {
    return [fossil repository eval {
	SELECT COUNT(*)
	FROM reportfmt
	WHERE title = :title
    }]
}

proc ::fx::report::DropByTitle {title} {
    return [fossil repository eval {
	DELETE
	FROM reportfmt
	WHERE title = :title
    }]
}

# Default defaults copied out of the fossil repository web UI (admin tickets).
# Not available through sql operations.
# Can be out of sync with the actual fossil default templates.

proc ::fx::report::GetColorTemplate {} {
    return [GetTemplate ticket-key-template {
	#ffffff Key:
	#f2dcdc Active
	#e8e8e8 Review
	#cfe8bd Fixed
	#bde5d6 Tested
	#cacae5 Deferred
	#c8c8c8 Closed
    }]
}

proc ::fx::report::GetSqlTemplate {} {
    return [GetTemplate ticket-report-template {
	SELECT
	  CASE WHEN status IN ('Open','Verified') THEN '#f2dcdc'
	       WHEN status='Review' THEN '#e8e8e8'
	       WHEN status='Fixed' THEN '#cfe8bd'
	       WHEN status='Tested' THEN '#bde5d6'
	       WHEN status='Deferred' THEN '#cacae5'
	       ELSE '#c8c8c8' END AS 'bgcolor',
	  substr(tkt_uuid,1,10) AS '#',
	  datetime(tkt_mtime) AS 'mtime',
	  type,
	  status,
	  subsystem,
	  title,
	  comment AS '_comments'
	FROM ticket
    }]
}

proc ::fx::report::GetTemplate {key default} {
    set map [list \n\t \n "\n    " {}]
    return [string trimleft \
		[string map [list \r\n \n \r \n] \
		     [config get-with-default $key \
			  [string map $map $default]]]]
}

# # ## ### ##### ######## ############# ######################
package provide fx::report 0
return
