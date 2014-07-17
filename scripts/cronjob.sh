#!/bin/bash -xe

# Run get-ppa.sh -U and rsync to website

# Set directory
SCRIPT_DIR=$(readlink -f $(dirname $0))
TOP_DIR=$(readlink -f $SCRIPT_DIR/..)

# Read config
. $SCRIPT_DIR/config
export http_proxy

# Run get-ppa.sh
$SCRIPT_DIR/get-ppa.sh -c all -U

# Rsync
for target in $RSYNC_TARGETS; do
    eval "rsync -avz $TOP_DIR/{dists,pool} \$RSYNC_TARGET_$target"
done
