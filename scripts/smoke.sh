#!/usr/bin/env bash
# Smoke test in a real Plasma session: restart the shell and fail if the widget does not load.
# The headless tests strip the views (they need real Plasma components) and qmllint cannot
# resolve every Plasma type, so errors like an unknown property only show up here.
set -u
systemctl --user restart plasma-plasmashell.service
sleep 15
errors=$(journalctl --user -u plasma-plasmashell --since "-40sec" --no-pager \
    | grep -E 'solat\.(widget|lockscreen)|plasmoids/solat' | grep -iE 'error|cannot|typeerror|referenceerror|non-existent|unable')
if [ -n "$errors" ]; then
    echo "FAIL: widget did not load cleanly:"
    echo "$errors"
    exit 1
fi
echo "ok - plasmashell restarted, no widget load errors"
