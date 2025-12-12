#!/bin/bash
/bin/bash /usr/local/bin/rdiff-wrapper.sh -t "bu-ex-wbox" -e "daily" -mu
EXITVALUE="$?"
if [ "$EXITVALUE" != 0 ]; then
	/usr/bin/logger -t "ERROR: $me exited with with $EXITVALUE"
else
	exit "$EXITVALUE"
fi
