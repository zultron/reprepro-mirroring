#!/bin/bash -e

# Run get-ppa.sh -U and rsync to website

VERBOSE=false
CMD_VERBOSE=-q

while getopts v ARG; do
    case $ARG in
	v) VERBOSE=true; CMD_VERBOSE="" ;;
    esac
done


# Set directory
SCRIPT_DIR=$(readlink -f $(dirname $0))
TOP_DIR=$(readlink -f $SCRIPT_DIR/..)

# Read config
. $SCRIPT_DIR/config
export http_proxy

# Run get-ppa.sh
PPA_CMD="$SCRIPT_DIR/get-ppa.sh ${CMD_VERBOSE} -c all -U"
! ${VERBOSE} || echo "running '${PPA_CMD}'"
${PPA_CMD}

# Rsync
for target in $RSYNC_TARGETS; do
    TARGETS="$TOP_DIR/dists $TOP_DIR/pool"
    eval RSYNC_CMD="\"rsync -avz ${CMD_VERBOSE} $TARGETS \
	\$RSYNC_TARGET_$target\""
    ! ${VERBOSE} || echo "running '${RSYNC_CMD}'"
    ${RSYNC_CMD}
done
