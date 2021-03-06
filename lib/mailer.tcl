## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Package fx::mailer 0
# Meta author      {Andreas Kupries}
# Meta category    ?
# Meta description ?
# Meta location    http:/core.tcl.tk/akupries/fx
# Meta platform    tcl
# Meta require     sqlite3
# Meta subject     fossil
# Meta summary     ?
# @@ Meta End

package require Tcl 8.5
package require cmdr::color
package require tls
package require smtp
package require mime
package require fx::fossil
package require fx::mailgen
package require fx::table
package require fx::mgr::config
package require fx::validate::mail-config

debug level  fx/mailer
debug prefix fx/mailer {[debug caller] | }

# # ## ### ##### ######## ############# ######################

namespace eval ::fx {
    namespace export mailer
    namespace ensemble create
}
namespace eval ::fx::mailer {
    namespace export get-config get get-global has has-global \
	has-local send good-address dedup-addresses test-address \
	drop-address
    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::fx::fossil
    namespace import ::fx::mailgen
    namespace import ::fx::mgr::config
    namespace import ::fx::validate::mail-config

    namespace import ::fx::table::do
    rename do table
}

# # ## ### ##### ######## ############# ######################

proc ::fx::mailer::test-address {config} {
    debug.fx/mailer {}
    set address [$config @address]

    puts "Decoding ($address) :="
    [table t {Part Value Notes} {
	set address [string map {{;} {,}} $address]
	set first 1
	foreach parts [mime::parseaddress $address] {
	    if {!$first} { $t add ==== ===== ===== }
	    set first 0

	    # set parts [lindex 0]
	    set hasdomain 0
	    set haslocal  0

	    foreach k [lsort -dict [dict keys $parts]] {
		set v [dict get $parts $k]
		set notes {}
		switch -exact $k {
		    domain -
		    local {
			incr has$k
			if {$v eq {}} {
			    lappend notes [color note {** Empty **}]
			}
		    }
		    error {
			if {$v ne {}} {
			    set k [color bad $k]
			    set v [color bad $v]
			}
		    }
		    default {
			# Report on the missing pieces. Depends on the
			# parts sorted lexicographically (see lsort above)
			# to place the fakes at the correct locations.

			if {([string compare $k domain] > 0) && !$hasdomain} {
			    $t add [color bad $k] {} [color bad {** Missing **}]
			    incr hasdomain
			}
			if {([string compare $k local] > 0) && !$haslocal} {
			    $t add [color bad $k] {} [color bad {** Missing **}]
			    incr haslocal
			}
		    }
		}
		$t add $k $v [join $notes \n]
	    }
	}

    }] show
    return
}

# # ## ### ##### ######## ############# ######################

proc ::fx::mailer::dedup-addresses {addrlist} {
    debug.fx/mailer {}
    # We assume that all addresses are good.
    # We keep the longest input of each with the same 'address'.

    #puts IN|[join $addrlist "|\n  |"]|

    # Note that we do basic lexical uniqueness first, getting rid of
    # the trivial duplicates.

    set map {}
    foreach a [lsort -unique $addrlist] {
	set route [dict get [lindex [mime::parseaddress $a] 0] address]
	dict lappend map $route $a
    }

    #array set mm $map ; parray mm ; unset mm

    set r {}
    dict for {route alist} $map {
	lappend r [lindex [lsort -command [lambda {a b} {
	    expr {[string length $b] - [string length $a]}
	}] $alist] 0]
    }

    return $r
}

proc ::fx::mailer::drop-address {addr addrlist} {
    debug.fx/mailer {}
    # We assume that all addresses are good.
    # We do not care about duplicates.
    # - If the input has them, the output will too.

    set addr [dict get [lindex [mime::parseaddress $addr] 0] address]

    debug.fx/mailer {subtract = $addr}

    set result {}
    foreach a $addrlist {
	set route [dict get [lindex [mime::parseaddress $a] 0] address]
	debug.fx/mailer {route = $route}
	if {$route eq $addr} continue
	debug.fx/mailer {  kept}
	lappend result $a
    }

    debug.fx/mailer {==> ($result)}
    return $result
}

proc ::fx::mailer::good-address {addr} {
    debug.fx/mailer {}
    set r [lindex [mime::parseaddress $addr] 0]

    # TODO: Check how it looks with multiple addresses, and bad syntax.

    # Drop empty results. Drop results which are not full addresses
    # i.e. have missing or empty local and domain parts.

    if {$r eq {}}                   { return 0 }
    if {![dict exists $r domain]}   { return 0 }
    if {[dict get $r domain] eq {}} { return 0 }
    if {![dict exists $r local]}    { return 0 }
    if {[dict get $r local] eq {}}  { return 0 }

    #puts ======================================================
    #array set aa $r ; parray aa ; unset aa

    # TODO: Filter out addresses with domains matching the local host.
    return 1
}

proc ::fx::mailer::get {setting} {
    return [Get 0 $setting]
}

proc ::fx::mailer::get-global {setting} {
    return [GetGlobal 0 $setting]
}

proc ::fx::mailer::get-config {} {
    debug.fx/mailer {}

    foreach {option listify setting} {
	-debug    0 debug
	-usetls   0 tls
	-username 0 user
	-password 0 password
	-servers  1 host
	-ports    0 port
    } {
	lappend config $option [Get $listify $setting]
    }

    lappend config -tlspolicy ::fx::mailer::TlsPolicy
    lappend config -header [list From [Get 0 sender] ]
    return $config
}

proc ::fx::mailer::Get {listify setting} {
    debug.fx/mailer {}

    if {$setting eq "project-name"} {
	# Pseudo mail config item
	set v [config get-with-default \
		   project-name \
		   [file rootname [file tail [fossil repository-location]]]]
    } else {
	set v [config get-with-default \
		   [mail-config internal   $setting] \
		   [mail-config default-of $setting]]
    }
    if {$listify} { set v [list $v] }
    return $v
}

proc ::fx::mailer::GetGlobal {listify setting} {
    debug.fx/mailer {}
    set v [config get-global [mail-config internal $setting]]
    if {$listify} { set v [list $v] }
    return $v
}

proc ::fx::mailer::has {setting} {
    debug.fx/mailer {}
    if {$setting eq "project-name"} {
	return 1
    }
    return [config has [mail-config internal $setting]]
}

proc ::fx::mailer::has-global {setting} {
    debug.fx/mailer {}
    if {$setting eq "project-name"} {
	return 0
    }
    return [config has-global [mail-config internal $setting]]
}

proc ::fx::mailer::has-local {setting} {
    debug.fx/mailer {}
    if {$setting eq "project-name"} {
	return 1
    }
    return [config has-local [mail-config internal $setting]]
}

# # ## ### ##### ######## ############# ######################

proc ::fx::mailer::send {config receivers corpus {verbose 0}} {
    debug.fx/mailer {}
    #if {[suspended]} return
    #if {![llength $receivers]} return

    if {$verbose} {
	puts "    ================================================"
	puts [textutil::adjust::indent $corpus {        }]
	puts "    ================================================"
    }
    #return

    set token [mime::initialize -string $corpus]

    foreach dst $receivers {
	puts "    To: $dst"
	mailgen context-push "To: $dst"
	try {
	    # Can the 'From' be configured via -header here ?
	    # I.e. config ? Alternate: -originator

	    set res [smtp::sendmessage $token \
			 -header [list To $dst] \
			 {*}$config]
	    foreach item $res {
		puts "    ERR $item"
	    }
	} finally {
	    mailgen context-pop
	}
    }

    mime::finalize $token
    puts "    Sent"

    variable mailcounter
    incr     mailcounter
    return
}

# # ## ### ##### ######## ############# ######################

proc ::fx::mailer::TlsPolicy {args} {
    debug.fx/mailer {}
    puts $args
    return secure
}

# # ## ### ##### ######## ############# ######################
package provide fx::mailer 0
return
