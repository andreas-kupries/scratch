## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Package fx::manifest 0
# Meta author      {Andreas Kupries}
# Meta category    ?
# Meta description ?
# Meta location    http:/core.tcl.tk/akupries/fossil2git
# Meta platform    tcl
# Meta require     ?
# Meta subject     ?
# Meta summary     ?
# @@ Meta End

package require Tcl 8.5
package require clock::iso8601

# # ## ### ##### ######## ############# ######################

namespace eval ::fx {
    namespace export manifest
    namespace ensemble create
}
namespace eval ::fx::manifest {
    namespace export parse
    namespace ensemble create
}

# # ## ### ##### ######## ############# ######################

proc ::fx::manifest::parse {manifest args} {
    # Manifest array/dictionary collecting all important pieces.

    # Initalize with general data coming from outside the manifest itself.
    # self -> uuid of the manifest artifact.
    array set m $args

    # Map from cards to dictionary elements, and manifest types.
    ##                             Type
    # A     name,target,attachment,operation             attachment
    # B n/a                        checkin
    # C     comment
    # D     when
    # E     when-event,eventid
    # F n/a                        checkin
    # J     field - sub dictionary
    # K     ticket                 ticket
    # L     title                  wiki
    # M n/a
    # N     mimetype
    # P n/a
    # Q n/a                        checkin
    # R n/a                        checkin
    # T n/a [+*_]tag uuid ?value?         - event|control
    # U     user
    # W     text
    # Z n/a

    while {[regexp "^(\[A-FJ-NP-RTUWZ\]) (\[^\n\]*)\n(.*)$" $manifest -> code data manifest]} {
	switch -exact -- $code {
	    A {
		if {[regexp {^(.*) (.*) (.*)$} $data -> m(aname) m(target) m(attachment)]} {
		    # Attachment added - Target = uuid of { event, ticket }, or wiki page name
		    set m(type) attachment
		    set m(operation) added
		    continue
		}
		if {[regexp {(.*) (.*)$} $data -> m(aname) m(target)]} {
		    # Attachment removed - Target = uuid of { event, ticket }, or wiki page name
		    set m(type) attachment
		    set m(operation) removed
		    continue
		}
		# error - bad syntax
	    }
	    B -
	    F -
	    Q -
	    R {
		set m(type) checkin
	    }
	    C {
		set m(comment) [Dearmor $data]
	    }
	    D {
		set m(when) $data
		set m(epoch) [Epoch $m(when)]
	    }
	    E {
		if {[regexp {(.*) (.*)$} $data -> m(when-event) m(eventid)]} {
		    set m(epoch-event) [Epoch $m(when-event)]
		    continue
		}
		# error - bad syntax
	    }
	    J {
		if {[regexp {(.*) (.*)$} $data -> fname value]} {
		    dict set m(field) $fname [Dearmor $value]
		    continue
		}
		# error - bad syntax
	    }
	    K {
		set m(ticket) $data
		set m(type) ticket
		# TODO: Pull the current ticket state.
		# TODO: Unify with the fields to have everything proper for dynamic routing.
		# TODO: Changes in m(fields) overwrite the current settings.
		# TODO: Get title here as well.
	    }
	    L {
		set m(title) $line
		set m(type) wiki
	    }
	    M {
		set m(type) cluster
	    }
	    N {
		set m(mimetype) $data
	    }
	    P {}
	    T {}
	    U {
		set m(user) $data
	    }
	    W {
		# line = number of characters to take
		# we take on more, which the closing \n
		set text [string range $manifest 0 $line]
		incr line
		set manifest [string range $manifest $line end]
		set m(text)  [string range $text 0 end-1]
	    }
	    Z {}
	}
    }

    if {![info exists m(type)]} {
	set m(type) control
    }

    return [array get m]
}

# # ## ### ##### ######## ############# ######################
## Supporting code.

namespace eval ::fx::manifest {
    variable map [list \\s { } \\n \n \\t \t \\r \r]
}

proc ::fx::manifest::Dearmor {s} {
    variable map
    # Should introduce K here
    return [string map $map $s]
}

proc ::fx::manifest::Epoch {when} {
    # Strip the subsecond part from the fossil time-stamp, ...
    regsub {\.\d+$} $when {} iso
    # ... then parse the now-regular ISO time into a proper epoch.
    return [clock::iso8601::parse_time $iso -gmt 1]
}

# # ## ### ##### ######## ############# ######################
## Manifest documentation. Cards, meaning and type of manifest.

# Ticket
# | Wiki
# | | Checkin
# | | | Control
# | | | | Cluster
# | | | | | Attachment (to ticket, wiki, or event)
# | | | | | | Event
# | | | | | | |
# T W C G - A E
#           *     A	uuid of attached file
#     *           B	uuid of baseline manifest (checkin is delta manifest)
#     *     * *   C	comment/description (of checkin or attachment)
# * * * *   * *   D	timestamp of change/manifest
#             *   E	event timestamp + uuid
#     *           F	file in checkin
# *               J	ticket field change
# *               K	uuid of ticket the change is for
#   *             L	wiki page title
#         *       M	uuid of artifact in the cluster
#   * *     * *   N	mimetype (of comment (C), wiki page (W))
#   * *       *   P	uuid of parent/prior checkin/page/event
#     *           Q	uuid of cherry picked parent checkin
#     *           R	repository checksum
#     * *     *   T	tag
# * * * *   * *   U	responsible user (name)
#   *         *   W	wiki page text, event text
# * * * * * * *   Z	manifest checksum
# K L ^   M A E		Primary identifying card.
#     BFQR

# Control artifacts, special (T)ags:
# 	user    -> U override
# 	comment -> C overrride
# 	date    -> D override

# Default N is text/x-fossil	Wiki page, Event description
# Default N is text/plain		Attachment

# Identifications

# A - *	Manifest is attachment
# E - *	Manifest is event
# B - 	Manifest is checkin
# F - 	Manifest is checkin
# J - 	Manifest is ticket change
# K - *	Manifest is ticket change
# L - *	Manifest is wiki page
# M - *	Manifest is cluster
# Q - 	Manifest is checkin
# R -  	Manifest is checkin

# When no other type claims the manifest:
# 	Manifest is control 

# # ## ### ##### ######## ############# ######################
package provide fx::manifest 0
return