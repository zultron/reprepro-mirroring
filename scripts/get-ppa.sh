#!/bin/bash -e

####################################################
# Utility functions

# Print debug messages
debugmsg() {
    test -n "$DEBUG" || return 0
    echo "DEBUG:  $*" >&2
}

# Print info messages
msg() {
    ! ${QUIET} || return 0
    echo -e "$@" >&2
}

usage() {
    set +x
    test -z "$1" || msg "$1"
    msg "Usage:"
    msg "    $0 -c [ CODENAME | all ] [ -d ] [ -m ] \\"
    msg "	[ -u | -U | -l | -i | -r REPREPO ARGS... ]"
    msg "    $0 -k"
    msg "	-c  CODENAME (wheezy, jessie, etc.) or 'all'"
    msg "	-d  enable debug output"
    msg "	-m  run manual updates"
    msg "	-u  check for updates"
    msg "	-U  pull updates"
    msg "	-l  list packages"
    msg "	-i  init configs"
    msg "	-r  run reprepro with following args; must be last argument"
    msg "	-k  dump gpg package signing public key"
    exit 1
}

####################################################
# Variable initialization

# Verbose arg given to reprepro
# This may be reduced by one '-v'
REPREPRO_VERBOSE=-vv

# Don't run manual updates by default
RUN_MANUAL_UPDATES=false

# Quiet mode for cronjobs
QUIET=false

# Some commands don't need reprepro config initialized
INIT=true

# Where this system lives
REPODIR=$(readlink -f $(dirname $0)/..)
SCRIPTSDIR=$REPODIR/scripts
CONFIG=$SCRIPTSDIR/config

# read configuration
. $CONFIG
debugmsg "Read configuration from $CONFIG"

# GPG handling
if test -n "$GNUPGHOME"; then
    export GNUPGHOME
    GPG_ARG="--gnupghome $GNUPGHOME"
fi

# Force debug logging
#DEBUG=1

####################################################
# Read command line opts

# Process command line args
ORIG_ARGS="$@"
while getopts c:luUirdkmq ARG; do
    case $ARG in
        c) CODENAME="$OPTARG" ;;
	u) COMMAND=checkupdates ;;
	U) COMMAND=update ;;
	l) COMMAND=list-archive ;;
	i) COMMAND=render_archive_config ;;
	r) COMMAND=run-reprepro; break ;;
	d) DEBUG=1; REPREPRO_VERBOSE=-VV ;;
	m) RUN_MANUAL_UPDATES=true ;;
	q) QUIET=true; REPREPRO_VERBOSE=-s ;;
	k) gpg --export --armor $PACKAGE_SIGNING_KEY; exit ;;
	*) usage
    esac
done
shift $((OPTIND-1))

####################################################
# Utility functions

run-reprepro() {
    # reprepro command
    REPREPRO="reprepro $REPREPRO_VERBOSE $GPG_ARG -b $REPODIR \
	--confdir +b/conf-$CODENAME --dbdir +b/db-$CODENAME"
    debugmsg running:  ${REPREPRO} $*
    ${REPREPRO} "$@"
}

init-codename() {
    # check -c option is valid
    test -n "$CODENAME" || usage "No codename specified"
    test "$CODENAMES" != "${CODENAMES/${CODENAME}}" || \
	usage "Valid codenames are:  ${CODENAMES}"
    debugmsg "Validated codename:  ${CODENAME}"

    # Get list of updates for the codename
    eval UPDATES=\${UPDATES_${CODENAME}}
    eval MANUAL_UPDATES=\${MANUAL_UPDATES_${CODENAME}}

    # List of updates for this run
    ALL_UPDATES="${UPDATES}"
    ${RUN_MANUAL_UPDATES} && ALL_UPDATES+=" ${MANUAL_UPDATES}"
    debugmsg "Updates for this run:  $ALL_UPDATES"

    # Expand input template file names
    UPDATES_TEMPLATES=$(for u in $ALL_UPDATES; do \
	echo -n "tmpl.updates-$u "; done)

    # Set config dir
    CONFIGDIR=$REPODIR/conf-${CODENAME}
    debugmsg "Archive configuration directory: ${CONFIGDIR}"

    # Create any missing directories
    if ! test -f $CONFIGDIR; then
	debugmsg "Creating configuration directory $CONFIGDIR"
	mkdir -p $CONFIGDIR
    fi

    # If override repo exists, use it
    OVERRIDE_TEST_URL=$MK_BUILDBOT_OVERRIDE_REPO/dists/$CODENAME/Release
    if curl -f -s -o /dev/null $OVERRIDE_TEST_URL; then
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
	    -e "s,@DA_TEST_REPO@,${DA_TEST_REPO}," \
	    -e "s,@UPDATES@,${ALL_UPDATES},g" \
	    -e '2,$p' \
	    >> $DST_CONFIG
	# test -n "$DEBUG" || { echo -e "\n${DST_CONFIG}:"; cat $DST_CONFIG; }
    done
}

# set up distributions and updates files
render_archive_config() {
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
    run-reprepro -C main list $CODENAME
}

# Testing:  see what updates would be pulled
checkupdates() {
    render_archive_config
    run-reprepro --noskipold checkupdate $CODENAME
}

# Pull updates
update() {
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
    if ${INIT}; then
	init-codename
	if test -z "${ALL_UPDATES}"; then
	    msg "No repos configured for update; exiting"
	    exit 0
	fi
    fi    
    $COMMAND "$@"
else
    usage
fi
