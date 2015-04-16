## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Package fx::contacts 0
# Meta author      {Andreas Kupries}
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
package require interp

package require fx::fossil
package require fx::mailer
package require fx::manifest
package require fx::seen
package require fx::validate::event-type

# # ## ### ##### ######## ############# ######################

namespace eval ::fx::contacts {
    namespace export get

    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::fx::fossil
    namespace import ::fx::mailer
    namespace import ::fx::manifest
    namespace import ::fx::seen
    namespace import ::fx::validate::event-type
}

# # ## ### ##### ######## ############# ######################

debug level  fx/contacts
debug prefix fx/contacts {[debug caller] | }

# # ## ### ##### ######## ############# ######################

proc ::fx::contacts::get {config} {
    debug.fx/contacts {}

    #array set xx $map ; parray xx ; unset xx

    # Test all events (pending or not).

    fossil show-repository-location

    set max [seen num]
    set n 0
    set fmt %[string length $max]d

    set recv {}

    seen forall type _ uuid __ {
	incr n
	puts -nonewline stderr "\r\033\[K\r[format $fmt $n]/$max: $uuid ([llength $recv])"
	flush stderr

	lappend recv {*}[Contacts $uuid $type]
	set recv [mailer dedup-addresses $recv]
    }

    puts \n[join [lsort -dict $recv] \n]
    return
}

proc ::fx::contacts::Contacts {uuid type} {
    debug.fx/contacts {}
    # Timeline event types, and associated artifact types.
    #
    # extype  type
    # ------  ----
    # checkin ci -- manifest (checkin)
    # control g  -- control        (comment change, tag change on a checkin)
    # event   e  -- event,         attachment
    # ticket  t  -- ticket change, attachment
    # wiki    w  -- wiki page,     attachment
    # ------  ----
    #
    # Note how attachments are not their own type of timeline
    # event, but are categorized underneath the associated changed
    # artifact, i.e. ticket or wiki.
    #
    # As events can have attachments as well I suspect that these
    # are handled under 'e' too, assuming consistency.

    set extype [event-type external $type]

    #puts type\t$extype

    # Get the event's manifest and use it to deduce the dynamic
    # routes, i.e. contacts implied by this manifest.
    set m [manifest parse \
	       [fossil get-manifest $uuid] \
	       ecomment {} \
	       etype    $extype  \
	       self     $uuid]

    #array set mm $m ; parray mm

    return [Receivers $m]
}

proc ::fx::contacts::Receivers {manifest} {
    debug.fx/contacts {}

    set recv {}

    if {![dict exists $manifest field]} {
	# No fields, no ticket, skip
	return {}
    }

    set field [dict get $manifest field]

    #array set ff $field ; parray ff

    set mtime [dict get $manifest epoch]
    if {[dict exists $manifest ticket]} {
	set tuuid [dict get $manifest ticket]
    } elseif {[dict exists $manifest target]} {
	set tuuid [dict get $manifest target]
    } else {
	set tuuid {}
    }

    #puts mtime/ticket=$mtime/$tuuid

    # We assess all fields of the ticket for addresses.
    foreach dest [dict keys $field] {
	+RX [dict get $field $dest]
    }


    # The fields may have introduced duplicate destinations.  Also,
    # same destinations may have different friendly names in them, and
    # still must be collated into one route.

    set recv [mailer dedup-addresses $recv]

    debug.fx/contacts {/done}
    return $recv
}

proc ::fx::contacts::+RX {addr} {
    debug.fx/contacts {}
    upvar 1 recv recv
    # Each level of transformation may introduce an address.
    debug.fx/contacts {concealed = $addr}
    +R $addr

    set addr [fossil reveal $addr]
    debug.fx/contacts {revealed  = $addr}
    +R $addr

    set addr [fossil user-info $addr]
    debug.fx/contacts {contact   = $addr}
    +R $addr
    return
}

proc ::fx::contacts::+R {addrs} {
    debug.fx/contacts {}
    upvar 1 recv recv
    if {$addrs eq {}} return
    foreach addr [split $addrs {,;}] {
	set addr [string trim $addr]
	if {![mailer good-address $addr]} {
	    debug.fx/contacts {rejected $addr}
	    return
	}
	debug.fx/contacts {added    $addr}
	lappend recv $addr
    }
    return
}

# # ## ### ##### ######## ############# ######################
package provide fx::contacts 0
return
