#!/bin/bash -e

####################################################
# Variable initialization

# Verbose arg given to reprepro
# This may be reduced by one '-v'
REPREPRO_VERBOSE=-vv

####################################################
# Utility functions

# Print debug messages
debugmsg() {
    test -n "$DEBUG" || return 0
    echo "DEBUG:  $*" >&2
}

# Print info messages
msg() {
    echo -e "$@" >&2
}

usage() {
    set +x
    test -z "$1" || msg "$1"
    msg "Usage:"
    msg "    $0 -c [ codename | all ] [ -u | -U | -l | -i | -d |" \
	"-r REPREPO ARGS... ]"
    msg "	-u  check for updates"
    msg "	-U  pull updates"
    msg "	-l  list packages"
    msg "	-i  init configs"
    msg "	-d  enable debug output"
    msg "	-r  run reprepro with following args; must be last argument"
    exit 1
}

####################################################
# Read command line opts

# Process command line args
ORIG_ARGS="$@"
while getopts c:luUird ARG; do
    case $ARG in
        c) CODENAME="$OPTARG" ;;
	u) COMMAND=checkupdates ;;
	U) COMMAND=update ;;
	l) COMMAND=list-archive ;;
	i) COMMAND=render_archive_config ;;
	r) COMMAND=run-reprepro; break ;;
	d) DEBUG=1; REPREPRO_VERBOSE=-VV ;;
	*) usage
    esac
done
shift $((OPTIND-1))

####################################################
# Initialize variables

# Where this system lives
REPODIR=$(readlink -f $(dirname $0)/..)
SCRIPTSDIR=$REPODIR/scripts
CONFIG=$SCRIPTSDIR/config

# Force debug logging
#DEBUG=1

run-reprepro() {
    # reprepro command
    REPREPRO="reprepro $REPREPRO_VERBOSE -b $REPODIR \
	--confdir +b/conf-$CODENAME --dbdir +b/db-$CODENAME"
    debugmsg "running:  ${REPREPRO} $*"
    ${REPREPRO} "$@"
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
    run-reprepro --noskipold checkupdate $CODENAME
}

# Pull updates
update() {
    init-codename
    render_archive_config
    run-reprepro --noskipold update $CODENAME
}

####################################################
# Main program

# if CODENAME = all, rerun ourselves for each codename
if test "$CODENAME" = all; then
    . $CONFIG
    for CODENAME in $CODENAMES; do
	msg "\nRe-running for codename $CODENAME"
	$0 ${ORIG_ARGS/ all/ $CODENAME}
    done
elif test -n "$COMMAND"; then
    $COMMAND "$@"
else
    usage
fi
