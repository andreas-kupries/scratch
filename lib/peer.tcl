## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Package fx::peer 0
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
package require cmdr::color
package require debug
package require debug::caller
package require fileutil
package require interp
package require linenoise
package require textutil::adjust
package require try

package require fx::fossil
package require fx::mailer
package require fx::mgr::config
package require fx::mgr::map
package require fx::table
package require fx::util

# # ## ### ##### ######## ############# ######################

namespace eval ::fx {
    namespace export peer
    namespace ensemble create
}
namespace eval ::fx::peer {
    namespace export \
	list add remove add-git remove-git exchange \
	state-dir state-reset state-clear \
	export import init
    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::fx::fossil
    namespace import ::fx::mailer
    namespace import ::fx::mgr::config
    namespace import ::fx::mgr::map
    namespace import ::fx::util

    namespace import ::fx::table::do
    rename do table
}

# # ## ### ##### ######## ############# ######################

debug level  fx/peer
debug prefix fx/peer {[debug caller] | }

# # ## ### ##### ######## ############# ######################

proc ::fx::peer::list {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    set map [Get $config]
    # dict: "fossil" + url + area -> direction
    #       "git" + url           -> last-uuid

    # Restructure the map to be indexed by url, and canonicalize the
    # associated data for the table.
    set tmap {}
    dict for {type spec} $map {
	switch -exact -- $type {
	    fossil {
		dict for {url espec} $spec {
		    set etype $type
		    dict for {area dir} [util dictsort $espec] {
			dict lappend tmap $url [::list $etype $dir $area {}]
			# Drop type information in multiple rows of the same url
			set etype {}
		    }
		}
	    }
	    git {
		dict for {url last} $spec {
		    dict lappend tmap $url [::list $type push content $last]
		}
	    }
	    default {
		error "Bad peer type \"$type\", expected one of fossil, or git"
	    }
	}
    }

    # Show the table
    [table t {Url Type Flow Area Last} {
	foreach {u speclist} [util dictsort $tmap] {
	    foreach spec [lsort -dict $speclist] {
		$t add $u {*}$spec
		# Drop the url in multiple rows of the same url.
		set u {}
	    }
	}
    }] show
    return
}

# # ## ### ##### ######## ############# ######################

proc ::fx::peer::add {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    set url  [$config @peer]
    set dir  [$config @direction]
    set area [$config @area]

    puts -nonewline "  Adding fossil \"$url $dir $area\" ... "
    flush stdout

    AddFossil $url $dir $area
    return
}

proc ::fx::peer::remove {config} {
    debug.fx/peer {}
    fossil show-repository-location

    set url  [$config @peer]
    set dir  [$config @direction]
    set area [$config @area]

    puts -nonewline "  Removing fossil \"$url $dir $area\" ... "
    flush stdout

    set peers [map get fx@peer@fossil]

    if {![dict exists $peers $url]} {
	puts [color note {No change, ignored}]
	return
    }

    # Drop areas ...
    set spec [dict get $peers $url]

    if {![dict exists $spec $area]} {
	puts [color note {No change, ignored}]
	return
    }

    # Merge directions ...
    variable dremove
    set old [dict get $spec $area]
    set new [dict get $dremove $old $dir]

    debug.fx/peer { Have $area => $old}
    debug.fx/peer { Drop          $dir}
    debug.fx/peer { Keeping       $new}

    if {$new eq $old} {
	puts [color note {No change, ignored}]
	return
    }

    if {$new eq {}} {
	# No directions left for the area, drop entire area.
	debug.fx/peer {drop entire $area}
	dict unset spec $area
    } else {
	# Change to reduced directions of the area.
	dict set spec $area $new
    }

    debug.fx/peer {new spec = ($spec)}

    if {![dict size $spec]} {
	# Drop entirely...
	debug.fx/peer {drop entire $url}
	map remove1 fx@peer@fossil $url
	puts [color good OK]
	return
    }

    # Change stored spec.
    debug.fx/peer {save changed}
    fossil repository transaction {
	map remove1 fx@peer@fossil $url
	map add1    fx@peer@fossil $url $spec
    }

    puts [color good OK]
    return
}

# # ## ### ##### ######## ############# ######################

proc ::fx::peer::add-git {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    set url [$config @peer]

    puts -nonewline "  Adding git \"$url push content\" ... "
    flush stdout

    AddGit $url {}
    return
}

proc ::fx::peer::remove-git {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    set url [$config @peer]

    puts -nonewline "  Removing git \"$url push content\" ... "
    flush stdout

    set peers [map get fx@peer@git]

    if {![dict exists $peers $url]} {
	puts [color note {No change, ignored}]
	return
    }

    # TODO: Document the git data structures.

    map remove1 fx@peer@git $url
    puts [color good OK]
    return
}

# # ## ### ##### ######## ############# ######################

proc ::fx::peer::state-dir {config} {
    debug.fx/peer {}
    fossil show-repository-location

    if {[$config @dir set?]} {
	# Specified, set value.
	config set-local fx-aku-peer-git-state [$config @dir]
    }

    # Show current value, possibly set above.
    puts [Statedir]
    return
}

proc ::fx::peer::state-reset {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    set state [Statedir]
    if {[IsState $state]} {
	if {[MyState $state _ _]} {
	    puts "  Drop tracked uuid from state [color note $state]"
	    GitDropLast $state
	} else {
	    puts "  [color error {Not touching}] non-owned state [color note $state]"
	}
    } else {
	puts "  Ignoring non-state [color note $state]"
    }

    fossil repository transaction {
	set peers [map get fx@peer@git]
	dict for {url last} $peers {
	    puts "  Cleared tracked uuid for git peer [color note $url]"
	    map remove1 fx@peer@git $url
	    map add1    fx@peer@git $url {}
	}
    }

    puts [color good OK]
    return
}

proc ::fx::peer::state-clear {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    set state [Statedir]
    if {[IsState $state]} {
	if {[MyState $state _ _]} {
	    puts "  Discard state [color note $state]"
	    file delete -force $state
	} else {
	    puts "  [color error {Not touching}] non-owned state [color note $state]"
	}
    } else {
	puts "  Ignoring non-state [color note $state]"
    }

    fossil repository transaction {
	set peers [map get fx@peer@git]
	dict for {url last} $peers {
	    puts "  Cleared tracked uuid for git peer [color note $url]"
	    map remove1 fx@peer@git $url
	    map add1    fx@peer@git $url {}
	}
    }

    puts [color good OK]
    return
}

# # ## ### ##### ######## ############# ######################

proc ::fx::peer::exchange {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    # See also note.tcl, ProjectInfo.
    set location [mailer get location]
    set	project  [mailer get project-name]

    set map [Get $config]
    # dict: "fossil" + url + area -> direction
    #       "git" + url           -> last-uuid

    # Note: The dictsort means that fossil peers are handled before
    # git peers. That is good because it means that any new content
    # pulled from one or more of the fossil peers will be pushed
    # immediately to the git peers, instead of getting delayed by one
    # exchange cycle.

    dict for {type spec} [util dictsort $map] {
	switch -exact -- $type {
	    fossil {
		dict for {url espec} [util dictsort $spec] {
		    dict for {area dir} [util dictsort $espec] {
			# Exchange data for area, per chosen direction.
			# Invokes regular fossil to perform the action.
			puts "Exchange [string repeat _ 40]"
			puts "Fossil [color note $url]"
			puts "[string totitle $dir] $area ..."

			fossil exchange $url $area $dir
			puts [color good OK]
		    }
		}
	    }
	    git {
		set state [Statedir]
		GitSetup $state $project $location

		set current [GitImport $state $project $location]

		dict for {url last} [util dictsort $spec] {
		    puts "Exchange [string repeat _ 40]"
		    puts "Git [color note $url]"
		    puts "Push content ..."
		    puts "  State  @ $current"
		    puts "  Remote @ $last"

		    # Skip destinations which are uptodate.
		    if {$last eq $current} {
			puts [color note "  No new commits"]
			puts [color good OK]
			continue
		    }

		    # TODO: Consider catching errors here, and going
		    #       to the next remote, in case of multiple remotes.

		    GitPush $state $url $current
		    puts [color good OK]
		}
	    }
	    default {
		error "Bad peer type \"$type\", expected one of fossil, or git"
	    }
	}
    }
    return
}

# # ## ### ##### ######## ############# ######################

proc ::fx::peer::export {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    lappend data "\# fx peer export @ [clock format [clock seconds]]"
    dict for {url dlist} [map get fx@peer@fossil] {
	foreach {area dir} $dlist {
	    lappend data [::list fossil $area $dir $url]
	}
    }
    dict for {url last} [map get fx@peer@git] {
	lappend data [::list git $url $last]
    }

    set    chan [util open [$config @output]]
    puts  $chan [join $data \n]
    close $chan
    return
}

proc ::fx::peer::import {config} {
    debug.fx/peer {}
    fossil show-repository-location

    set extend [$config @extend]

    set input [$config @input]
    set data [read $input]
    $config @input forget

    # Run the import script in a safe interpreter with just the import
    # commands. This generates internal data structures from which we
    # then create the peering links again.

    set i [interp::createEmpty]
    $i alias fossil ::fx::peer::IFossil
    $i alias git    ::fx::peer::IGit
    $i eval $data
    interp delete $i

    variable imported 

    if {![llength $imported]} {
	puts [color note {No peers}]
	return
    }

    if {!$extend} {
	puts [color warning "Import replaces all existing peers ..."]
	# Inlined delete of all peers
	map delete fx@peer@fossil
	map delete fx@peer@git
    } else {
	puts [color note "Import keeps the existing peers ..."]
    }

    puts "New peers ..."
    init
    foreach {type url details} $imported {
	puts -nonewline "  Importing $type $url ($details) ... "
	flush stdout

	switch -exact -- $type {
	    fossil { AddFossil $url {*}$details }
	    git    { AddGit    $url $details }
	    default {
		error "Bad peer type \"$type\", expected one of fossil, or git"
	    }
	}
    }
    return
}

proc ::fx::peer::IFossil {area dir url} {
    debug.fx/peer {}
    variable imported
    lappend  imported fossil $url [::list $dir $area]
    return
}

proc ::fx::peer::IGit {url last} {
    debug.fx/peer {}
    variable imported
    lappend  imported git $url $last
    return
}

# # ## ### ##### ######## ############# ######################

proc ::fx::peer::AddFossil {url dir area} {
    debug.fx/peer {}

    set peers [map get fx@peer@fossil]

    if {![dict exists $peers $url]} {
	# New peer
	map add1 fx@peer@fossil $url [::list $area $dir]
	puts [color good OK]
	return
    }

    # Merge areas ...
    set spec [dict get $peers $url]

    if {![dict exists $spec $area]} {
	# New area in known peer
	dict set spec $area $dir
	fossil repository transaction {
	    map remove1 fx@peer@fossil $url
	    map add1    fx@peer@fossil $url $spec
	}
	puts [color good OK]
	return
    }

    # Merge directions for known area in known peer ...
    variable dadd
    set old [dict get $spec $area]
    set new [dict get $dadd $old $dir]

    if {$new eq $old} {
	puts [color note {No change, ignored}]
	return
    }

    puts -nonewline [color note "upgraded to $new "]
    flush stdout

    dict set spec $area $new
    fossil repository transaction {
	map remove1 fx@peer@fossil $url
	map add1    fx@peer@fossil $url $spec
    }

    puts [color good OK]
    return
}

proc ::fx::peer::AddGit {url last} {
    debug.fx/peer {}

    set peers [map get fx@peer@git]

    if {[dict exists $peers $url]} {
	puts [color note {No change, ignored}]
	return
    }

    map add1 fx@peer@git $url {}
    puts [color good OK]
    return
}

# # ## ### ##### ######## ############# ######################
## Internal import support commands.

proc ::fx::peer::Statedir {} {
    debug.fx/peer {}
    return [config get-with-default \
		fx-aku-peer-git-state \
		[fossil repository-location].peer-state]
}

proc ::fx::peer::IsState {statedir} {
    debug.fx/peer {}
    return [expr {[file exists      $statedir] &&
		  [file isdirectory $statedir] &&
		  [file exists      $statedir/git/git-daemon-export-ok] &&
		  [file isfile      $statedir/git/git-daemon-export-ok]
	      }]
}

proc ::fx::peer::MyState {statedir pv ov} {
    upvar 1 $pv pcode $ov owner
    debug.fx/peer {}
    set pcode [config get-local project-code]
    set owner [string trim [fileutil::cat $statedir/owner]]
    return [expr {$pcode eq $owner}]
}


# taken from old setup-import script.
proc ::fx::peer::GitSetup {statedir project location} {
    debug.fx/peer {}

    puts "Exchange [string repeat _ 40]"
    puts "Git State Directory"

    if {[IsState $statedir]} {
	debug.fx/peer {/initialized}
	puts "  Ready at [color note $statedir]."

	# A ready directory may still belong to a different
	# project. Check this.

	if {![MyState $statedir pcode owner]} {
	    puts [color error "  Error: Claimed by project \"$owner\""]
	    puts [color error "  Error: Which is not us    \"$pcode\""]
	    # Abort self, and caller (exchange).
	    return -code return
	}

	puts [color good OK]
	return
    } else {
	set pcode [config get-local project-code]
    }

    puts "  Initialize at [color note $statedir]."

    # State directory is not initialized. Do it now.
    # Drop anything else which may existed in its place.
    debug.fx/peer {initialize now}

    # The git state is a sub-directory of the main state directory
    # This allows us to put other (more transient) state as a sibling
    # of the git directory while not requiring additional path
    # configuration keys.
    set git [file join $statedir git]

    file delete -force $statedir
    file mkdir $git

    set ::env(TZ) UTC

    Run git --bare --git-dir=$git init \
	|& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}

    file rename -force \
	$git/hooks/post-update.sample \
	$git/hooks/post-update

    fileutil::touch     $git/git-daemon-export-ok
    fileutil::writeFile $git/description \
	"Mirror of the $project fossil repository at $location\n"

    # At last, claim the initialized state directory for the project
    fileutil::writeFile $statedir/owner $pcode

    puts [color good OK]
    debug.fx/peer {/done initialization}
    return
}

proc ::fx::peer::GitImport {statedir project location} {
    debug.fx/peer {}

    puts "Exchange [string repeat _ 40]"
    puts "Git Import $statedir"

    set git $statedir/git
    set tmp $statedir/tmp

    GitMakeReadme $git $project $location

    set current [fossil last-uuid]
    set last    [GitLastImported $git]

    puts "  Fossil @ $current"
    puts "  Git    @ $last"

    if {$last eq $current} {
	puts [color note "  No new commits"]
	puts [color good OK]
	return $current
    }

    file mkdir $tmp
    try {
	set first   [expr {$last eq {}}]
	set elapsed [GitPull $tmp $git $first]
	puts [color note "  Imported new commits to git mirror in $elapsed min"]

	# Remember how far we imported.
	GitUpdateImported $git $current
    } finally {
	file delete -force $tmp
    }

    puts [color good OK]
    return $current
}

proc ::fx::peer::GitMakeReadme {git project location} {
    debug.fx/peer {}
    set date [Now]

    lappend map @PROJECT $project
    lappend map @URL     $location
    lappend map @DATE    $date
    
    fileutil::writeFile $git/README.html [string map $map {
	<p>This repository is a mirror of the
	<a href="@URL">@PROJECT fossil repository</a>.
	Last updated on @DATE.</p>
    }]
    return
}

proc ::fx::peer::Now {} {
    clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}
}

proc ::fx::peer::GitLastImported {git} {
    set idfile $git/fossil-import-id
    if {![file exists $idfile]} {
	return {}
    }
    return [string trim [fileutil::cat $idfile]]
}

proc ::fx::peer::GitUpdateImported {git current} {
    set idfile $git/fossil-import-id
    fileutil::writeFile $idfile $current
    return
}

proc ::fx::peer::GitDropLast {statedir} {
    set idfile $statedir/git/fossil-import-id
    file delete -force $idfile
    return
}

proc ::fx::peer::GitPull {tmp git first} {
    puts "  Pull"

    set begin [clock seconds]
    set src   [fossil repository-location]

    file delete -force $tmp
    file mkdir         $tmp

    Run git --bare  --git-dir $tmp init \
	|& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}
    Run fossil export -R $src --git \
	| git --bare --git-dir $tmp fast-import \
	|& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}

    # Ensure that the new repository contains the HEAD of the old
    # repository.  If something goes wrong in the import then all the
    # commit ids get perturbed from the point of corruption on up and
    # this test will fail. If all is ok then this id will be present
    # in the new repo and we can push the new commits.

    if {!$first} {
	if {[catch {
	    set ref [Runx git --bare --git-dir $git rev-parse HEAD]
	    Run git --bare --git-dir $tmp cat-file -e $ref \
		|& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}
	} msg]} {
	    puts [color error "  Review $tmp for errors: $msg"]
	    return 0
	}
    }

    # Rename trunk to master to suit git terminology better.
    file rename $tmp/refs/heads/trunk $tmp/refs/heads/master

    # Push the new changes from tmp to local destination
    Run git --bare --git-dir $tmp remote add target $git \
	|& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}
    Run git --bare --git-dir $tmp push --force target --all \
	|& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}
    Run git --bare --git-dir $tmp push --force target --tags \
	|& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}

    file delete -force $tmp
    set elapsed [expr {([clock seconds] - $begin)/60}]

    # Also - after the very first import you need to repack the git
    # repository using 'git repack -adf --window=50' to avoid an
    # excessively large repo.  git fast-import is fast, not space
    # efficient - so always repack.

    if {$first} {
	Run git --bare  --git-dir $git repack -adf --window=50 \
	    |& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}
    }

    # Done pulling in changes
    return $elapsed
}

proc ::fx::peer::GitPush {statedir remote current} {
    # Perform garbage collect as required
    set git $statedir/git

    set count [Runx git --bare --git-dir $git count-objects | awk {{print $1}}]
    if {$count > 50} {
	Run git --bare --git-dir $git gc \
	    |& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}
    }

    Run git --bare --git-dir $git push --mirror $remote \
	|& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}

    # Update the local per-remote state, record the last uuid which is
    # now pushed to it.
    map remove1 fx@peer@git $remote
    map add1    fx@peer@git $remote $current
    return
}
#-----------------------------------------------------------------------------

proc  ::fx::peer::Silent {args} {
    debug.fx/peer {}
    exec 2> /dev/null > /dev/null {*}$args
}

proc  ::fx::peer::Runx {args} {
    debug.fx/peer {}
    exec 2>@ stderr {*}$args
}

proc ::fx::peer::Run {args} {
    debug.fx/peer {}
    exec 2>@ stderr >@ stdout {*}$args
}

proc ::fx::peer::Get {config} {
    debug.fx/peer {}
    # All peering information is loaded, and merged into a single
    # structure.
    #
    # dict: "fossil" + url + area -> direction
    #       "git" + url           -> last-uuid

    set map {}

    # I. Fossil peers
    dict for {url dlist} [map get fx@peer@fossil] {
	debug.fx/peer {$url ==> ($dlist)}

	foreach {area dir} $dlist {
	    debug.fx/peer {  $area ==> $dir}

	    $config @configarea set $area
	    $config @syncdir    set $dir

	    dict set map fossil $url \
		[$config @configarea] \
		[$config @syncdir]
	}
    }

    # II. Git peers.
    # Note how the configuration contains state information.
    # (Last uuid pushed to git mirror).
    dict for {url last} [map get fx@peer@git] {
	dict set map git $url $last
    }
    return $map
}

proc ::fx::peer::init {} {
    debug.fx/peer {}
    # Redefine to nothing for all future calls.
    proc ::fx::peer::init {} {}

    # Create mappings used to store peering information. Note how
    # their names use illegal characters. This makes them inaccessible
    # to the regular map commands, preventing users from messing
    # things up by direct editing. Of course, they still can do that
    # via direct database access and sql commands, so the commands
    # above will still validate the data they get from the repository

    # fx@peer@fossil: repo url -> dict (area dir ...)
    # fx@peer@git   : repo url -> last uuid sync'd so far.

    foreach map {
	fx@peer@fossil
	fx@peer@git
    } {
	if {[map has $map]} continue
	map create $map
    }
    return
}

# # ## ### ##### ######## ############# ######################
## Tables to manipulate the direction pseudo-bits.
## The explicit tables are easier to maintain and understand
## than coding the implied decision table.

namespace eval ::fx::peer {
    variable dadd {
	push {
	    push push
	    pull sync
	    sync sync
	}
	pull {
	    push sync
	    pull pull
	    sync sync
	}
	sync {
	    push sync
	    pull sync
	    sync sync
	}
    }

    variable dremove {
	push {
	    push {}
	    pull push
	    sync {}
	}
	pull {
	    push pull
	    pull {}
	    sync {}
	}
	sync {
	    push pull
	    pull push
	    sync {}
	}
    }
}

# # ## ### ##### ######## ############# ######################
package provide fx::peer 0
return
