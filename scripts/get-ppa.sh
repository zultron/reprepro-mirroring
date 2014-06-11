#!/bin/bash -e

usage() {
    set +x
    test -z "$1" || echo "$1" >&2
    echo "Usage:" >&2
    echo "    $0 -c codename [ -u | -U | -l | -i ]" >&2
    echo "	-u  check for updates" >&2
    echo "	-U  pull updates" >&2
    echo "	-l  list packages" >&2
    echo "	-i  init configs" >&2
    echo "  Set non-empty \$DEBUG environment variable for debug output" >&2
    exit 1
}

# Print debug messages
debugmsg() {
    test -n "$DEBUG" || return 0
    echo "DEBUG:  $*" >&2
}

####################################################
# Read command line opts

# Process command line args
while getopts c:luUi ARG; do
    case $ARG in
        c) CODENAME="$OPTARG" ;;
	u) COMMAND=checkupdates ;;
	U) COMMAND=update ;;
	l) COMMAND=list-archive ;;
	i) COMMAND=render_archive_config ;;
	*) usage
    esac
done

####################################################
# Initialize variables

# Where this system lives
REPODIR=$(readlink -f $(dirname $0)/..)
SCRIPTSDIR=$REPODIR/scripts
CONFIG=$SCRIPTSDIR/config

# Force debug logging
DEBUG=1

run-reprepro() {
    # reprepro command
    REPREPRO="reprepro -VV -b $REPODIR \
	--confdir +b/conf-$CODENAME --dbdir +b/db-$CODENAME"
    debugmsg "running:  ${REPREPRO} $*"
    ${REPREPRO} $*
}

init-codename() {
    # only do this once
    test -z "${CODENAMES}" || return 0

    # read configuration
    . $CONFIG
    debugmsg "Read configuration from $CONFIG"

    # check -c option is valid
    test -n "$CODENAME" || usage "No codename specified"
    test "$CODENAMES" != "${CODENAMES/${CODENAME}}" || \
	usage "Valid codenames are:  ${CODENAMES}"
    debugmsg "Validated codename:  ${CODENAME}"

    # Get list of updates for the codename
    eval UPDATES=\${UPDATES_${CODENAME}}
    # Expand input template file names
    UPDATES_TEMPLATES=$(for u in $UPDATES; do echo -n "tmpl.updates-$u "; done)

    # Set config dir
    CONFIGDIR=$REPODIR/conf-${CODENAME}
    debugmsg "Archive configuration directory: ${CONFIGDIR}"

    # If override repo exists, use it
    OVERRIDE_TEST_URL=$MK_BUILDBOT_OVERRIDE_REPO/dists/$CODENAME/Release
    if curl -s -o /dev/null $OVERRIDE_TEST_URL; then
	MK_BUILDBOT_REPO=$MK_BUILDBOT_OVERRIDE_REPO
	debugmsg "Using buildbot override repo:"
	debugmsg "    $MK_BUILDBOT_OVERRIDE_REPO"
    fi
}

####################################################
# render templates

# generic config file rendering
render_configfile() {
    local DST_CONFIG=$CONFIGDIR/$1; shift
    local SRC_CONFIGS="$*"
    debugmsg "Rendering config file:  ${DST_CONFIG}"
    debugmsg "    from source templates:  ${SRC_CONFIGS}"

    # clean out DST_CONFIG for appending
    echo -e "#\t\t\t\t\t\t\t\t-*-conf-*-" > $DST_CONFIG

    # render each SRC_CONFIG and append to DST_CONFIG
    for SRC_CONFIG in $SRC_CONFIGS; do
	sed -n $SCRIPTSDIR/$SRC_CONFIG \
	    -e "s,@CODENAME@,${CODENAME},g" \
	    -e "s,@MK_BUILDBOT_REPO@,${MK_BUILDBOT_REPO}," \
	    -e "s,@MK_DEPS_REPO@,${MK_DEPS_REPO}," \
	    -e "s,@UPDATES@,${UPDATES},g" \
	    -e '2,$p' \
	    >> $DST_CONFIG
	# test -n "$DEBUG" || { echo -e "\n${DST_CONFIG}:"; cat $DST_CONFIG; }
    done
}

# set up distributions and updates files
render_archive_config() {
    init-codename

    debugmsg "Rendering archive configuration with replacements:"
    debugmsg "    CODENAME -> ${CODENAME}"
    debugmsg "    MK_BUILDBOT_REPO -> ${MK_BUILDBOT_REPO}"
    debugmsg "    MK_DEPS_REPO -> ${MK_DEPS_REPO}"

    render_configfile distributions tmpl.distributions
    render_configfile updates $UPDATES_TEMPLATES
}

####################################################
# reprepro functions

# List Debian archive
list-archive() {
    init-codename
    run-reprepro -C main list $CODENAME
}

# Testing:  see what updates would be pulled
checkupdates() {
    init-codename
    render_archive_config
    run-reprepro checkupdate $CODENAME
}

# Pull updates
update() {
    init-codename
    render_archive_config
    run-reprepro update $CODENAME
}

####################################################
# Main program

if test -n "$COMMAND"; then
    $COMMAND
else
    usage
fi
