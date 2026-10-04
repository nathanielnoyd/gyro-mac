#!/bin/zsh
# Unloads Gyro's privileged helper so a rebuilt copy can be installed again.
#
# When Gyro is signed ad hoc (no Team ID), macOS pins the helper's launch
# constraint to the exact binary it first approved. After a rebuild, launchd
# refuses to start the new helper ("Launch Constraint Violation") and
# reinstalling alone doesn't clear the pin. Unloading the job first does.
#
# Builds signed with a Team ID aren't affected. See App/Config/Base.xcconfig.

set -euo pipefail

label=io.github.nathanielnoyd.gyro.helper

if sudo launchctl bootout "system/$label" 2>/dev/null; then
    echo "Unloaded $label."
else
    echo "$label wasn't loaded."
fi
echo "Now open Gyro › Settings and click Uninstall, then Install."
