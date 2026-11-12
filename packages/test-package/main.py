import sys

import humanize


def main():
    # humanize is vendored into the zip by build.sh, so its path shows where the code was loaded from
    return "test-package on python %d.%d: 1234567890 bytes is %s (humanize from %s)\n" % (
        sys.version_info.major,
        sys.version_info.minor,
        humanize.naturalsize(1234567890),
        humanize.__file__,
    )
