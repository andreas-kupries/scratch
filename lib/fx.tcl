#!/usr/bin/env tclsh
## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Package fx ?
# Meta author      {Andreas Kupries}
# Meta category    ?
# Meta description ?
# Meta location    http:/core.tcl.tk/akupries/fx
# Meta platform    tcl
# Meta require     sqlite3
# Meta require     cmdr
# Meta require     {Tcl 8.5-}
# Meta require     lambda
# Meta require     fx::fossil
# Meta require     fx::config
# Meta require     fx::enum
# Meta require     fx::report
# Meta subject     ?
# Meta summary     ?
# @@ Meta End

package require Tcl 8.5
package require cmdr::color ; # color activation
package require cmdr::history
package require cmdr::help::tcl
package require cmdr::actor 1.3 ;# Need -extend support for common/use blocks.
package require cmdr
package require debug
package require debug::caller
package require lambda

package require fx::seen  ; # set-progress

# # ## ### ##### ######## ############# ######################

debug level  fx
debug prefix fx {[debug caller] | }

# # ## ### ##### ######## ############# ######################

namespace eval fx {
    namespace export main
    namespace ensemble create
}

# # ## ### ##### ######## ############# ######################

proc ::fx::main {argv} {
    debug.fx {}
    try {
	fx do {*}$argv
    } trap {CMDR CONFIG WRONG-ARGS} {e o} - \
      trap {CMDR CONFIG BAD OPTION} {e o} - \
      trap {CMDR VALIDATE} {e o} - \
      trap {CMDR ACTION UNKNOWN} {e o} - \
      trap {CMDR ACTION BAD} {e o} - \
      trap {CMDR VALIDATE} {e o} - \
      trap {CMDR PARAMETER LOCKED} {e o} - \
      trap {CMDR DO UNKNOWN} {e o} {
	debug.fx {trap - cmdline user error}
	puts stderr "$::argv0 cmdr: [cmdr color error $e]"
	return 1

    } trap {FX} {e o} {
	debug.fx {trap - other user error}
	puts stderr "$::argv0 general: [cmdr color error $e]"
	return 1
	
    } on error {e o} {
	debug.fx {trap - general, internal error}
	debug.fx {[debug pdict $o]}
	# TODO: nicer formatting of internal errors.
	puts stderr [cmdr color error $::errorInfo]
	mail-error $::errorInfo
	return 1
    }

    debug.fx {done, ok}
    return 0
}

proc ::fx::mail-error {e} {
    global env

    # Mailing the stacktrace can be disabled form the environment.
    # Current user of this behaviour: Testsuite.
    if {[info exists env(FX_MAIL_STACKTRACE)] && !$env(FX_MAIL_STACKTRACE)} {
	return
    }

    package require fx::fossil
    package require fx::mailer
    package require fx::mailgen
    set config [::fx mailer get-config]
    set admin  [lindex [dict get $config -header] end]

    ::fx mailgen context-push "R:  [::fx::fossil repository-location]"
    try {
	::fx mailer send $config $admin \
	    [::fx mailgen for-error $e] on
    } finally {
	::fx mailgen context-pop
    }
    return
}

# # ## ### ##### ######## ############# ######################
## Support commands constructing glue for various callbacks.

proc ::fx::no-search {} {
    lambda {p x} {
	$p config @repository-active set off
    }
}

# NOTE: call, vt, sequence, exclude - Possible convenience cmds for Cmdr.
proc ::fx::call {p args} {
    lambda {p args} {
	package require fx::$p
	fx::$p {*}$args
    } $p {*}$args
}

proc ::fx::vt {p args} {
    lambda {p args} {
	package require fx::validate::$p
	fx::validate::$p {*}$args
    } $p {*}$args
}

proc ::fx::sequence {args} {
    lambda {cmds p x} {
	foreach c $cmds {
	    {*}$c $p $x
	}
    } $args
}

proc ::fx::exclude {locked} {
    # Jump into the context of the parameter instance currently
    # getting configured. At the time the spec is executed things
    # regarding naming are in good enough shape to extract naming
    # information. While aliases for options are missing these are of
    # no relevance to our purpose here either, we need only the
    # primary name, and that is initialized by now.

    set by [uplevel 2 {my the-name}]
    lambda {locked by p args} {
	#debug.cmdr {}
	$p config @$locked lock $by
    } $locked $by
}

proc ::fx::overlay {path args} {
    set cmd {}
    if {[llength $args]} {
	set cmd " '[join $args { }]'"
    }
    [::fx::fx find $path] learn [subst {
	private delegate {
	    section Convenience
	    description {
		Delegate the command$cmd to the local fossil executable.
	    }
	    input args {
		Command and arguments to deliver to core fossil
	    } { list ; validate str }
	} {fx::delegate {$args}}
	# All commands not known to fx at this level are delegated to
	# the core fossil application.
	default
    }]
}

proc ::fx::delegate {prefix config} {
    # Any issues of the command delegated to are its problems, and not ours.
    # It will have them reported already anyway as well.
    catch {
	exec >@ stdout 2>@ stderr <@ stdin \
	    {*}[auto_execok fossil] {*}$prefix {*}[$config @args]
    }
}

# # ## ### ##### ######## ############# ######################

fx seen set-progress [lambda {text} {
    set eeol \033\[K
    puts -nonewline \r$eeol\r$text
    flush stdout
}]

# # ## ### ##### ######## ############# ######################

cmdr history initial-limit 20
cmdr history save-to       ~/.fx_history

cmdr create fx::fx [file tail $::argv0] {
    ##
    # # ## ### ##### ######## ############# #####################

    description {
	The fx command line client
    }

    shandler ::cmdr::history::attach

    # # ## ### ##### ######## ############# #####################
    ## Bespoke category ordering for help
    ## Values are priorities. Final order is by decreasing priority.
    ## I.e. Highest priority is printed first, at the top, beginning.

    common *category-order* {
	Convenience -8900
	Advanced    -9000
    }

    # # ## ### ##### ######## ############# ######################
    ## Common pieces across the various commands.

    common .repository {
	state repository-active {
	    This hidden field can be used by other fields to disable
	    the search for a local fossil repository. This is for use
	    by all commands which have global and local operation modes.
	} {
	    immediate
	    validate boolean
	    default on
	}
	option repository {
	    The repository to work with. Defaults to the repository of
	    the checkout we are in, or, outside of a checkout, the
	    explicitly configured "default" repository.
	} {
	    alias R
	    validate rwfile
	    generate [fx::call fossil repository-find]
	}
	state repository-db {
	    The repository database we are working with.
	} {
	    immediate
	    # Ensures that this is run before the action code, making
	    # the database command globally accessible.
	    generate [fx::call fossil repository-open]
	}
    }

    common *all* {
	option debug {
	    Placeholder. Processed before reaching cmdr.
	} {
	    undocumented
	    validate str
	}
	option color {
	    Force the (non-)use of colors in the output. The default
	    depends on the environment, active when talking to a tty,
	    and otherwise not.
	} {
	    when-set [lambda {p x} {
		cmdr color activate $x
	    }]
	}
    }

    common .extend {
	# Used by officer 'note config'.
	option extend {
	    Extend the current tables.
	} { presence }
    }

    common .uuid {
	input uuid {
	    Full fossil uuid of the artifact to work with.
	} { validate [fx::vt uuid] }
    }

    common .uuid-lex-list {
	input uuid {
	    Full fossil uuids of the artifacts to work with.
	} {
	    list
	    validate [fx::vt uuid-lexical]
	}
    }

    common .all {
	option all {
	    Do this for all repositories watched by fx.
	} { alias A; presence }
	# See also the note in option repository above.
    }

    common .verbose {
	option verbose {
	    Activate more chatter.
	} { alias v; presence }
    }

    common .uuid-or-all {
	input uuid {
	    Full fossil uuid of the artifact to work with.
	} {
	    optional
	    validate [fx::vt uuid]
	    when-set [fx::exclude overall]
	}
	option overall {
	    Do this for all repositories watched by fx.
	} {
	    label all
	    alias A
	    presence
	    when-set [fx::exclude uuid]
	}
	state uuid-all-check {
	    Check that either uuid or --all were used.
	    The exclusion have already made sure that not both are set.
	} {
	    immediate
	    when-complete [lambda {p x} {
		if {[$p config @uuid    set?] ||
		    [$p config @overall set?]} return
		return -code error -errorcode {CMDR VALIDATE} \
		    "Must use either uuid or --all" 
	    }]
	}
    }

    common .export {
	input output {
	    The path of the file to save the exported data into.
	} {
	    # Avoid wchan. Externally visible side-effect is bad, can
	    # happen when cmdr simply wants to test the ok-ness of the
	    # input without any conversion.
	    validate wfile
	}
    }

    common .import {
	input input {
	    The path of the file to read the data from.
	    Defaults to stdin.
	} {
	    optional
	    validate rchan
	}
    }

    # # ## ### ##### ######## ############# ######################

    common .event-hidden-validation {
	state event {
	    Hidden parameter to be used by the internal validation of
	    event-types.
	} {
	    label imported-event
	    validate [fx::vt event-type]
	}
    }
    common .field-hidden-validation {
	state field {
	    Hidden parameter to be used by the internal validation of
	    ticket fields.
	} {
	    label imported-ticket-field
	    validate [fx::vt ticket-field]
	}
    }
    common .mailconfig-hidden-validation {
	state mailconfig {
	    Hidden parameter to be used by the internal validation of
	    mail configuration keys
	} {
	    label imported-mail-config-key
	    validate [fx::vt mail-config]
	}
    }
    common .mailaddr-hidden-validation {
	state mailaddr {
	    Hidden parameter to be used by the internal validation of
	    email addresses.
	} {
	    label imported-mail-address
	    validate [fx::vt mail-address]
	}
    }
    common .configarea-hidden-validation {
	state configarea {
	    Hidden parameter to be used by the internal validation of
	    config area names.
	} {
	    label imported-configarea
	    validate [fx::vt config-area]
	}
    }
    common .syncdir-hidden-validation {
	state syncdir {
	    Hidden parameter to be used by the internal validation of
	    sync directions.
	} {
	    label imported-syncdir
	    validate [fx::vt sync-dir]
	}
    }
    common .routemap {
	# All validation fields used by the RouteMap code.
	use .field-hidden-validation
	use .event-hidden-validation
	use .mailaddr-hidden-validation
    }
    common .peermap {
	# All validation fields used by the peering code.
	use .configarea-hidden-validation
	use .syncdir-hidden-validation
    }

    common .global {
	option global {
	    Operate on the global configuration.
	} {
	    alias G ; presence
	    when-set [::fx::no-search]
	}
    }

    # # ## ### ##### ######## ############# ######################

    private version {
	section Introspection
	description {
	    Print version and revision of the application.
	}
    } [lambda config {
	puts "[file tail $::argv0] [package present fx]"
    }]

    private contacts {
	description {
	    Print all email addresses found in the repository (Tickets).
	}
	use .repository
    } [fx::call contacts get]

    private save {
	description {
	    Save all fx-managed state of the repository.
	}
	use .repository
	use .export
    } [fx::call state save]

    private restore {
	description {
	    Load all fx-managed state of a repository.
	}
	use .repository
	use .import
    } [fx::call state restore]

    officer repository {
	description {
	    Manage the repository to work with.
	}

	private show {
	    section Introspection
	    section {Repository Management}
	    description {
		Print the name of the repository we are working on, if any.
	    }
	    use .repository
	} [fx::call fossil c_show_repository]
	default

	private default {
	    section Introspection
	    section {Repository Management}
	    description {
		Print the name of the default repository, if any.
	    }
	} [fx::call fossil c_default_repository]

	private reset {
	    section {Repository Management}
	    description {
		Unset the current default repository.
	    }
	} [fx::call fossil c_reset_repository]

	private set {
	    section {Repository Management}
	    description {
		Set the path to the current default repository.
	    }
	    input target {
		The path to the current repository to use when all else fails.
	    } {
		validate rwpath
	    }
	} [fx::call fossil c_set_repository]
    }

    # # ## ### ##### ######## ############# ######################
    ## Overlay to the standard "fossil user" command

    officer user {
	description {
	    Management of users in the local repository
	}

	private push {
	    section {User Management}
	    description {
		Push local changes to the users to the
		configured remote
	    }
	    use .repository
	} [fx::call user push]

	private pull {
	    section {User Management}
	    description {
		Push user information from the
		configured remote to here.
	    }
	    use .repository
	} [fx::call user pull]

	private sync {
	    section {User Management}
	    description {
		Sync the user information at the configured
		remote and here.
	    }
	    use .repository
	} [fx::call user sync]

	private list {
	    section {User Management}
	    description {
		Show all known users, their information and capabilities
	    }
	    use .repository
	} [fx::call user list]
	default

	private broadcast {
	    section {User Management}
	    description {
		Send a mail to all accounts of the repository.
	    }
	    input text {
		The file containing the contents of the mail.
		Defaults to stdin
	    } {
		optional
		validate rchan
	    }
	    use .repository
	} [fx::call user broadcast]

	private contact {
	    section {User Management}
	    description {
		Change the contact information for the named user
	    }
	    input user {
		The name of the user to update.
	    } {
		validate [fx::vt user]
		# need extended interaction ops => part of cmdr ?
		#generate [fx::call user select-for {contact change}]
	    }
	    input contact {
		The new contact information of the user.
		Will be asked for interactively if not specified.
	    } {
		optional
		validate str
		interact
	    }
	    use .repository
	} [fx::call user update-contact]
    }
    alias users = user list

    # # ## ### ##### ######## ############# ######################
    ## Extended configuration management.

    officer config {
	description {
	    Management of a fossil repositories' configuration, in detail.
	    I.e. this has access to all the individual pieces.
	}
	common .setting {
	    input setting {
		The name of the configuration setting to work with.
	    } {
		validate [fx::vt setting]
	    }
	}
	common .setting-list {
	    input setting {
		The names of the configuration settings to work with.
	    } {
		list
		validate [fx::vt setting]
	    }
	}

	private available {
	    section Configuration
	    description {
		List all available configuration settings.
	    }
	} [fx::call config available]

	private list {
	    section Configuration
	    description {
		List all changed configuration settings of the
		repository, and their values.
	    }
	    use .repository
	} [fx::call config list]
	default

	private get {
	    section Configuration
	    description {
		Print the value of the named configuration setting.
	    }
	    use .setting
	    use .repository
	} [fx::call config get]

	private set {
	    section Configuration
	    description {
		Change the value of the named
		configuration setting to the
		given text.
	    }
	    use .setting
	    use .global
	    input value {
		The new value of the configuration setting.
	    } {}
	    use .repository
	} [fx::call config set]

	private unset {
	    section Configuration
	    description {
		Remove the specified local configuration setting.
		This sets it back to the system default.
	    }
	    use .repository
	    use .global
	    use .setting-list
	} [fx::call config unset]

	# Standard fossil cli configuration commands, implement maybe.
	# push
	# pull
	# sync
	# merge
	# export
	# import
	# reset
    }

    # # ## ### ##### ######## ############# ######################
    ## Report management. Using an external report format which is
    ## easier to write by a human being. Also nicer table output, and
    ## structured output.

    # Components:
    # - name (aka title)
    # - sql (select statement)              -- should have a template to use
    # - color key (map: #rrggbb => string)  -- should have a template
    # Note ! The color key is an optional part of a report's definition.
    #
    # Templates
    # - color key
    # - sql
    #
    # Operations
    # - template-spec   - Set sql template
    # - template-colors - Set color key template
    # - list            - List (table, raw, json)
    # - add             - Create name ?sql?
    # - rename          - Change name
    # - set             - Change sql
    # - set-colors      - Change colors
    # - delete          - Delete name|id...
    # - export          - Export ?name|id...? - Restricted export, sql or color
    # - import          - Import file
    # - run             - Run name
    # - run             - Run <sql>|<sqlfile>  (create + run + delete, tmp-name)
    # - edit            - Edit name   => auto-calls editor, (export + edit + import, tmp-file)
    # -                 -  restricted => sql, or colors

    officer report {
	description {
	    Management of a fossil repositories' set of ticket reports.
	}

	common *all* -extend {
	    use .repository
	}

	common .spec {
	    input spec {
		Report specification.
		Defaults to reading it from stdin.
	    } {
		optional
		validate str
		generate [lambda p { read stdin }]
	    }
	}

	common .colorkey {
	    input colors {
		Color key
		Defaults to reading it from stdin.
	    } {
		optional
		validate str
		generate [lambda p { read stdin }]
	    }
	}

	common .only {
	    option only {
		Restrict the operation to a part of the report, i.e.
		either specification (sql) or color key (color).
	    } { validate [fx::vt report-part] }
	}

	# execute a report ... proper matrix output, json output, nested tcl
	# execute a temp report => enter a report, execute it, delete it.
	# see if we can get reports parameterized. at least from fx.

	private list {
	    section Reporting
	    description {
		List all reports found in the repository.
	    }
	    option json {
		Print the data formatted as JSON array.
		Cannot be used together with --raw
	    } { presence ; when-set [fx::exclude raw] }
	    option raw {
		Print the raw names.
		Cannot be used together with --json
	    } { presence ; when-set [fx::exclude json] }

	    # options: --json, --raw
	} [fx::call report list]
	default

	private add {
	    section Reporting
	    description {
		Add a report definition to the repository.
	    }
	    # ... ?owner?, title, (cols, sql)
	    option owner {
		Specify the owner of the report.
		Defaults to the unix user running the command.
	    } {
		validate str
		default [lambda p { set ::tcl_platform(user) }]
	    }
	    input title {
		The report's name.
	    } {
		validate str
	    }
	    use .spec
	} [fx::call report add]

	private rename {
	    section Reporting
	    description {
		Rename the specified report.
	    }
	    input id {
		Id or name of the report to rename.
	    } {
		validate [fx::vt report-id]
	    }
	    input newname {
		New name of the report.
	    } {
		validate [fx::vt not-report-id]
	    }
	} [fx::call report rename]

	private set {
	    section Reporting
	    description {
		Change the definition of the specified report.
	    }
	    input id {
		Id or name of the report to change.
	    } {
		validate [fx::vt report-id]
	    }
	    use .spec
	} [fx::call report redefine]
	alias redefine

	private set-colors {
	    section Reporting
	    description {
		Change the color key of the specified report.
	    }
	    input id {
		Id or name of the report to change.
	    } {
		validate [fx::vt report-id]
	    }
	    use .colorkey
	} [fx::call report set-colors]

	private export {
	    section Reporting
	    description {
		Export one or more reports into a file. Defaults to all.
	    }
	    use .export
	    use .only
	    input id {
		Id or name of the report(s) to export.
	    } {
		optional ; list
		validate [fx::vt report-id]
	    }
	} [fx::call report export]

	private import {
	    section Reporting
	    description {
		Import report definitions from a file.
	    }
	    use .import
	} [fx::call report import]

	private edit {
	    section Reporting
	    description {
		Interactively edit the specified report using the
		application specified by the environment variable
		EDITOR.
	    }
	    use .only
	    input id {
		Id or name of the report to edit.
		If not specified start from the current templates.
	    } {
		optional
		validate [fx::vt report-id]
	    }
	} [fx::call report edit]

	private delete {
	    section Reporting
	    description {
		Delete the specified report definition.
	    }
	    input id {
		Id or name of the report(s) to delete.
	    } {
		list
		validate [fx::vt report-id]
	    }
	} [fx::call report delete]

	private run {
	    section Reporting
	    description {
		Execute the specified report definition and print the results to stdout.
		Without a specification read the definition from stdin for a temporary report.
	    }
	    input id {
		Id or name of the report to run.
	    } {
		optional
		validate [fx::vt report-id]
	    }
	} [fx::call report run]

	private template-colors {
	    section Reporting
	    description {
		Set the global color key template.
	    }
	    use .colorkey
	} [fx::call report template-set-colors]

	private template-spec {
	    section Reporting
	    description {
		Set the global sql template
	    }
	    use .spec
	} [fx::call report template-set-sql]
    }
    alias reports = report list

    # # ## ### ##### ######## ############# ######################
    ## Management of mappings (used both internally and by the
    ## ticket system, for example. Type, severity, priority, category,
    ## ...)

    officer map {
	description {
	    Management of mappings for the ticketing system and other
	    things.
	}

	common *all* -extend {
	    use .repository
	}

	common .map {
	    input map {
		Name of the mapping to operate on.
	    } {
		validate [fx::vt map]
	    }
	}

	private list {
	    section Mappings
	    section Introspection
	    description {
		List all mappings stored in the repository.
	    }
	} [fx::call map list]
	default

	private create {
	    section Mappings Control
	    description {
		Create a new named mapping.
	    }
	    input newmap {
		Name of the mapping to create.
	    } {
		validate [fx::vt not-map]
	    }
	} [fx::call map create]

	private delete {
	    section Mappings Control
	    description {
		Delete the named mapping.
	    }
	    use .map
	} [fx::call map delete]

	private rename {
	    section Mappings Control
	    description {
		Rename the named mapping.
	    }
	    use .map
	    input newmap {
		New name for the mapping
	    } {
		validate [fx::vt not-map]
	    }
	} [fx::call map rename]

	private export {
	    section Mappings Save/Restore
	    description {
		Save the specified mapping(s).
		Defaults to all.
	    }
	    use .export
	    input maps {
		Names of the mappings to export.
	    } {
		optional
		list
		validate [fx::vt map]
	    }
	} [fx::call map export]

	private import {
	    section Mappings Save/Restore
	    description {
		Import one or more mappings from a save file.
	    }
	    use .extend
	    use .import
	} [fx::call map import]

	private add {
	    section Mappings Control
	    description {
		Extend the specified mapping with the given key and value.
	    }
	    use .map
	    input key {
		Additional key of the mapping.
	    } {
		validate [fx::vt not-map-key]
	    }
	    input value {
		Value associated with the key
	    } {
		validate str
	    }
	} [fx::call map add]

	private remove {
	    section Mappings Control
	    description {
		Remove the named keys(s) from the specified mapping.
	    }
	    use .map
	    input items {
		Keys of the mapping to remove.
	    } {
		list
		validate [fx::vt map-key]
	    }
	} [fx::call map remove]

	private show {
	    section Mappings
	    section Introspection
	    description {
		Show the key/value pairs of the specified mapping.
	    }
	    use .map
	} [fx::call map show]
    }

    alias maps = map list

    # # ## ### ##### ######## ############# ######################
    ## Management of enumerations (used both internally and by the
    ## ticket system, for example. Type, severity, priority, category,
    ## ...)

    officer enum {
	description {
	    Management of enumerations for the ticketing system.
	}

	common *all* -extend {
	    use .repository
	}

	common .enum {
	    input enum {
		Name of the enumeration to operate on.
	    } {
		validate [fx::vt enum]
	    }
	}

	private list {
	    section Enumerations
	    section Introspection
	    description {
		List all enumerations stored in the repository.
	    }
	} [fx::call enum list]
	default

	private create {
	    section Enumerations Control
	    description {
		Create a new named enumeration.
	    }
	    input newenum {
		Name of the enumeration to create.
	    } {
		validate [fx::vt not-enum]
	    }
	    input items {
		Initial items of the new enumeration.
	    } {
		optional
		list
		validate str
	    }
	} [fx::call enum create]

	private delete {
	    section Enumerations Control
	    description {
		Delete the named enumeration. Careful, you may break your
		ticketing system. Check first that the enumeration is not
		used anymore.
	    }
	    use .enum
	} [fx::call enum delete]

	private rename {
	    section Enumerations Control
	    description {
		Rename the named enumeration.
	    }
	    use .enum
	    input newenum {
		New name for the enumeration.
	    } {
		validate [fx::vt not-enum]
	    }
	} [fx::call enum rename]

	private export {
	    section Enumerations Save/Restore
	    description {
		Save the specified enumeration(s).
		Defaults to all.
	    }
	    use .export
	    input enums {
		Names of the enumerations to export.
	    } {
		optional
		list
		validate [fx::vt enum]
		#generate [fx::vt enum default]
	    }
	} [fx::call enum export]

	private import {
	    section Enumerations Save/Restore
	    description {
		Import one or more enumerations from a save file.
	    }
	    use .extend
	    use .import
	} [fx::call enum import]

	private add {
	    section Enumerations Control
	    description {
		Extend the specified enumeration with the given items.
	    }
	    use .enum
	    input items {
		Additional items of the enumeration.
	    } {
		list
		validate [fx::vt not-enum-item]
	    }
	} [fx::call enum add]

	private remove {
	    section Enumerations Control
	    description {
		Remove the named item(s) from the specified enumeration.
		Careful, you may break your ticketing system. Check
		first that the item is not used anymore.
	    }
	    use .enum
	    input items {
		Items of the enumeration to remove.
	    } {
		list
		validate [fx::vt enum-item]
	    }
	} [fx::call enum remove]

	private change {
	    section Enumerations Control
	    description {
		Rename the item in the specified enumeration.
		Careful, you may break your ticketing system. Check
		first that all users have made the same substitution.
	    }
	    use .enum
	    input item {
		Item of the enumeration to change.
	    } {
		validate [fx::vt enum-item]
	    }
	    input newitem {
		New name of the item in the enumeration.
	    } {
		validate [fx::vt not-enum-item]
	    }
	} [fx::call enum change]

	private items {
	    section Enumerations
	    section Introspection
	    description {
		Show the items in the specified enumeration.
	    }
	    use .enum
	} [fx::call enum items]
    }

    alias enums = enum list

    # # ## ### ##### ######## ############# ######################
    ## Change notifications, management and generation.

    officer note {
	description {
	    Management of notification emails for ticket
	    changes, new revisions, etc.
	}

	# Required commands:
	# - TODO-SPEC Exclude/Include users from email delivery
	# - TODO-SPEC Suspend/activate notification for a project, event type.
	# - MAYBE watch remote repo (ping /stat) => create a local clone,
	#                                             watch implies sync.
	#
	# All commands check for and remind the user about a missing
	# mail configuration, especially the mandatory fields.

	officer config {
	    description {
		Manage the mail setup for notification emails.
	    }

	    common .global-local {
		option global {
		    Operate on the global configuration.
		} {
		    alias G ; presence
		    when-set [::fx::sequence \
				  [::fx::exclude local] \
				  [::fx::no-search]]
		}
		option local {
		    Operate strictly on the local configuration.
		} {
		    alias L ; presence
		    when-set [::fx::exclude global]
		}
	    }

	    common .key {
		input key {
		    The part of the mail setup to (re)configure.
		} { validate [fx::vt mail-config] }
	    }

	    common .key-list {
		input key {
		    The parts of the mail setup to unset.
		} { list ; validate [fx::vt mail-config] }
	    }

	    private show {
		section Notifications {Mail setup}
		section Introspection
		description {
		    Show the current mail setup for notifications.
		}
		use .global-local
		use .repository
	    } [fx::call note mail-config-show]
	    default

	    private set {
		section Notifications {Mail setup}
		description {
		    Set the specified part of the mail setup for notifications.
		}
		use .global
		use .repository
		use .key
		input value {
		    The new value of the configuration.
		}
	    } [fx::call note mail-config-set]

	    private unset {
		section Notifications {Mail setup}
		description {
		    Reset the specified part of the mail setup for notifications
		    to its default.
		}
		use .global
		use .repository
		use .key-list
	    } [fx::call note mail-config-unset]

	    private reset {
		section Notifications {Mail setup}
		description {
		    Reset all parts of the mail setup for notifications
		    to their defaults.
		}
		use .global
		use .repository
	    } [fx::call note mail-config-reset]

	    private export {
		section Notifications Save/Restore
		description {
		    Save the notification configuration into a file.
		}
		use .global-local
		use .repository
		use .export
	    } [fx::call note mail-config-export]

	    private import {
		section Notifications Save/Restore
		description {
		    Import the notification configuration from a save file.
		}
		use .global
		use .repository
		use .import
		use .mailconfig-hidden-validation
	    } [fx::call note mail-config-import]
	}

	private update-history {
	    section Notifications Control
	    description {
		Update the cached ticket history used to calculate
		dynamic routes.
	    }
	    option clear {
		Clear the ticket history before updating. I.e. force
		full update from scratch, instead of doing an
		incremental one.

	    } { presence }
	    use .repository
	} [fx::call seen regenerate-series]

	private watched {
	    section Notifications Control
	    description {
		Show the list of repositories currently watched
		(<=> those which have active routes). These fall
		under the purview of 'note deliver --all'.
	    }
	} [fx::call note watched]

	# TODO: Global routes?
	officer route {
	    common *all* -extend {
		use .repository
	    }

	    private list {
		section Notifications Destinations
		section Introspection
		description {
		    Show all configured mail destinations (per event type).
		}
		use .routemap
	    } [fx::call note route-list]
	    default

	    private export {
		section Notifications Save/Restore
		description {
		    Save the configured mail destinations into a file.
		}
		use .export
		use .routemap
	    } [fx::call note route-export]

	    private import {
		section Notifications Save/Restore
		description {
		    Import mail destinations from a save file.
		}
		use .extend
		use .import
		use .routemap
	    } [fx::call note route-import]

	    common .etype {
		input event {
		    Event to work with.
		} { validate [fx::vt event-xtype] }
	    }

	    private add {
		section Notifications Destinations
		description {
		    Add fixed mail destination for the named event type.
		}
		use .etype
		input to {
		    Email addresses of the added routes.
		} {
		    list
		    validate [fx::vt mail-address]
		}
	    } [fx::call note route-add]

	    private drop {
		section Notifications Destinations
		description {
		    Remove the specified mail destinations
		    (glob pattern) for the event type.
		}
		use .etype
		input to {
		    Glob patterns of the emails to remove
		    from the routes.
		} {
		    optional
		    list
		    default *
		    validate str
		}
	    } [fx::call note route-drop]

	    private events {
		section Notifications Destinations
		section Introspection
		description {
		    Show all events we can generate notifications for.
		}
	    } [fx::call note event-list]

	    officer field {
		private list {
		    section Notifications Destinations
		    section Introspection
		    description {
			Show all available ticket fields (for dynamic routes).
		    }
		} [fx::call note field-list]
		default

		private add {
		    section Notifications Destinations
		    description {
			Add field as source of mail destinations for ticket events.
		    }
		    input field {
			Name of the field to use as source of mail destinations.
		    } {
			list
			validate [fx::vt ticket-field]
		    }
		} [fx::call note route-field-add]

		private drop {
		    section Notifications Destinations
		    description {
			Remove the specified field as source
			of mail destinations for ticket events.
		    }
		    input field {
			Name of the field to stop using as source of mail destinations.
		    } {
			list
			validate [fx::vt ticket-field]
		    }
		} [fx::call note route-field-drop]
	    }
	    alias fields = field list
	}

	alias routes = route list

	private deliver {
	    section Notifications
	    description {
		Send notification emails to all configured destinations,
		for all new events (since the last delivery).
	    }
	    use .all
	    use .repository
	    use .routemap
	    use .verbose
	} [fx::call note deliver]

	private mark-pending {
	    section Notifications Control
	    description {
		Mark the specified (or all) artifacts as having not
		been notified before. This forces the generation of a
		notification for them on the next invokation of
		"note deliver".
	    }
	    use .repository
	    use .uuid-or-all
	} [fx::call note mark-pending]

	private mark-notified {
	    section Notifications Control
	    description {
		Mark the specified (or all) artifacts as having been
		notified before, thus preventing generation of a
		notification for them on the next invokation of
		"note deliver".
	    }
	    use .repository
	    use .uuid-or-all
	} [fx::call note mark-notified]

	common .ex {
	    option extended {
		Show extended type information. Note that using this
		option will substantially slow the command down, as
		it has to parse all involved manifests. The larger
		the repository history, the larger the slow-down.
	    } { presence }
	}

	private show-pending {
	    section Notifications Control
	    description {
		Show all events in the timeline marked as pending.
	    }
	    use .ex
	    use .repository
	} [fx::call note show-pending]

	private show-notified {
	    section Notifications Control
	    description {
		Show all events in the timeline marked as notified.
	    }
	    use .ex
	    use .repository
	} [fx::call note show-notified]
    }

    # # ## ### ##### ######## ############# ######################
    ## Peering

    officer peer {
	description {
	    Management of multiple peers for repository synchronization.
	}

	common *all* -extend {
	    use .repository
	}

	private state {
	    section Peering Control
	    description {
		Set and query the directory used to store the
		local state for the git peers of the repository.
		The default is a directory sibling to the fossil
		repository file.
	    }
	    input dir {
		The directory to use for git state
	    } {
		optional
		default {}
		validate rwdirectory
	    }
	} [fx::call peer state-dir]

	private state-reset {
	    section Advanced {Armed & Dangerous} Peering
	    description {
		Resets the uuid information used to track new commits.
		This forces a re-import of the repository into the local
		git state, and further forces a push to the git peers on the
		next invokation of "peer exchange".
	    }
	} [fx::call peer state-reset]

	private state-clear {
	    section Advanced {Armed & Dangerous} Peering
	    description {
		Like "state-reset" but additionally discards the entire
		local git state, forcing a complete rebuild on the next
		invokation of "peer exchange".
	    }
	} [fx::call peer state-clear]

	private list {
	    section Peering
	    section Introspection
	    description {
		List all peers stored in the repository, and associated
		definitions (what to synchronize, direction, type of peer).
	    }
	    use .peermap
	} [fx::call peer list]
	default

	private export {
	    section Peering Save/Restore
	    description {
		Save the peering information.
	    }
	    use .export
	} [fx::call peer export]

	private import {
	    section Peering Save/Restore
	    description {
		Import the peering information from a save file.
	    }
	    use .extend
	    use .import
	} [fx::call peer import]

	common .direction {
	    input direction {
		The direction of synchronization
	    } { validate [fx::vt sync-dir] }
	}
	common .area {
	    input area {
		The configuration area to synchronize
	    } { validate [fx::vt config-area] }
	}
	common .peer-fossil {
	    input peer {
		The fossil peer to talk to.
	    } { validate [fx::vt peer-fossil] }
	}
	common .peer-git {
	    input peer {
		The git peer to talk to.
	    } { validate [fx::vt peer-git] }
	}
	common .not-peer-fossil {
	    input peer {
		The fossil peer to talk to.
	    } { validate [fx::vt not-peer-fossil] }
	}
	common .not-peer-git {
	    input peer {
		The git peer to talk to.
	    } { validate [fx::vt not-peer-git] }
	}

	private add {
	    section Peering Control
	    description {
		Add direction and area of exchange for a fossil peer.
	    }
	    use .direction
	    use .area
	    use .not-peer-fossil
	} [fx::call peer add]

	private remove {
	    section Peering Control
	    description {
		Add direction and area of exchange for a fossil peer.
	    }
	    use .direction
	    use .area
	    use .peer-fossil
	} [fx::call peer remove]

	private add-git {
	    section Peering Control
	    description {
		Add export to a git peer.
	    }
	    use .not-peer-git
	} [fx::call peer add-git]

	private remove-git {
	    section Peering Control
	    description {
		Remove export to a git peer.
	    }
	    use .peer-git
	} [fx::call peer remove-git]

	private exchange {
	    section Peering
	    description {
		Run a data exchange with all configured peers
	    }
	    use .peermap
	} [fx::call peer exchange]
    }
    alias peers = peer list

    # # ## ### ##### ######## ############# ######################
    ## Shun management

    officer shun {
	description {
	    Dangerous and advanced commands to manipulate the list
	    of shunned artifacts in bulk.
	}
	# TODO: testsuite.

	common *all* -extend {
	    section Advanced {Armed & Dangerous} Shunning
	    use .repository
	}

	private list {
	    description {
		Show the list of all shunned artifacts.
	    }
	} [fx::call shun list]

	private add {
	    description {
		Shun artifacts.
	    }
	    use .uuid-lex-list
	} [fx::call shun add]

	private remove {
	    description {
		Reaccept artifacts which have been shunned.
	    }
	    use .uuid-lex-list
	} [fx::call shun remove]
    }
    alias shunned = shun list

    # # ## ### ##### ######## ############# ######################
    ## Developer support, feature test and repository inspection.

    officer test {
	description {
	    Various commands to test the system and its configuration.
	}
	common *all* -extend {
	    section Advanced Testing
	    # We do not have use .repository here because the
	    # 'mail-address' command does not use it contrary
	    # to all others.
	}

	private mail-address {
	    description {
		Parse the specified address into parts, and determine
		if it is lexically ok for us, or not, and why not in
		case of the latter.
	    }
	    input address {
		The address to parse and test.
	    } { }
	} [fx::call mailer test-address]

	private mail-setup {
	    description {
		Generate a test mail and send it using the current
		mail configuration.
	    }
	    use .repository
	    input destination {
		The destination address to send the test mail to.
	    } { }
	} [fx::call note test-mail-config]

	private mail-for {
	    description {
		Generate the notification mail for the specified artifact,
		and print it to stdout.
	    }
	    use .repository
	    use .uuid-or-all
	} [fx::call note test-mail-gen]

	private mail-receivers {
	    description {
		Analyse the specified artifact and determine the set
		of mail addresses to send a notification to, fixed
		and field-based.
	    }
	    use .repository
	    use .uuid-or-all
	    use .routemap
	} [fx::call note test-mail-receivers]

	private manifest-parse {
	    description {
		Parse the specified artifact as manifest and print the
		resulting array/dictionary to stdout.
	    }
	    use .repository
	    use .uuid-or-all
	} [fx::call note test-parse]

	private tags {
	    description {
		Determine the names, types, and values of all tags
		associated with a checkin.
	    }
	    use .repository
	    use .uuid
	} [fx::call fossil test-tags]

	private branch {
	    description {
		Determine the branch of a checkin.
	    }
	    use .repository
	    use .uuid
	} [fx::call fossil test-branch]

	private last-uuid {
	    description {
		Determine the uuid of the last commit (on any branch).
		In other words, the uuid of the repository tip.
	    }
	    use .repository
	} [fx::call fossil test-last-uuid]
	alias tip = last-uuid

	private schema {
	    description {
		Determine the aux-schema of the repository.
	    }
	    use .repository
	} [fx::call fossil test-schema]

	private mlink {
	    description {
		Determine the state of the mlink table in the repository.
	    }
	    use .repository
	} [fx::call fossil test-mlink]
    }

    # # ## ### ##### ######## ############# ######################
    ## Developer support, debugging.

    officer debug {
	description {
	    Various commands to help debugging the system itself
	    and its configuration.
	}
	common *all* -extend {
	    section Advanced Debugging
	}

	private levels {
	    description {
		List all the debug levels known to the system,
		which we can enable to gain a (partial) narrative
		of the application-internal actions.
	    }
	} [fx::call debug levels]
    }

    # Shortcut
    alias ticket-fields = note route field list
    # aka                 note route fields
}

# # ## ### ##### ######## ############# ######################
## Add delegations.

fx::overlay {}
fx::overlay user user

# # ## ### ##### ######## ############# ######################
package provide fx 0
return
