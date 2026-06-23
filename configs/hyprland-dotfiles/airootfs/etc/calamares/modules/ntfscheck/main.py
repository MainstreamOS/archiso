#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# Pre-resize guard for "Install alongside". Windows Fast Startup (and
# hibernation) leave the NTFS volume dirty, so ntfsresize refuses to shrink it
# and the partition module aborts with an opaque error. Catch that state first,
# before any partition is touched, and tell the user how to fix it.

import subprocess

import libcalamares
from libcalamares.utils import gettext_path, gettext_languages

import gettext
_translation = gettext.translation("calamares-python",
                                   localedir=gettext_path(),
                                   languages=gettext_languages(),
                                   fallback=True)
_ = _translation.gettext


# Phrases ntfsresize prints when a volume is dirty, hibernated, or scheduled
# for a Windows check. Matched case-insensitively against its combined output.
DIRTY_MARKERS = (
    "scheduled for check",
    "hibernat",
    "boot into windows",
    "chkdsk",
    "is dirty",
    "unclean",
)


def pretty_name():
    return _("Checking Windows partition state")


def ntfs_devices():
    """/dev paths of every NTFS partition visible to the live system."""
    try:
        out = subprocess.run(
            ["lsblk", "-rpno", "NAME,FSTYPE"],
            capture_output=True, text=True, timeout=30,
        ).stdout
    except (OSError, subprocess.SubprocessError) as exc:
        libcalamares.utils.warning("lsblk failed: {!s}".format(exc))
        return []

    devices = []
    for line in out.splitlines():
        fields = line.split()
        # Accept both the on-disk type ("ntfs") and the ntfs3-driver spelling.
        if len(fields) >= 2 and fields[1].lower() in ("ntfs", "ntfs3"):
            devices.append(fields[0])
    return devices


def ntfs_blocks_resize(device):
    """True when ntfsresize refuses the volume (dirty / hibernated)."""
    try:
        # A dirty volume errors out fast; the slow path is a full consistency
        # scan of a large clean volume, which must finish so it passes.
        result = subprocess.run(
            ["ntfsresize", "--info", device],
            capture_output=True, text=True, timeout=120,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        libcalamares.utils.warning(
            "ntfsresize check failed for {0}: {1!s}".format(device, exc))
        return False

    blob = (result.stdout + "\n" + result.stderr).lower()
    return any(marker in blob for marker in DIRTY_MARKERS)


def run():
    # Only the "alongside" choice resizes an existing NTFS volume; erase and
    # replace either wipe or leave it untouched, so there is nothing to guard.
    choices = libcalamares.globalstorage.value("partitionChoices") or {}
    if choices.get("install") != "alongside":
        return None

    for device in ntfs_devices():
        if ntfs_blocks_resize(device):
            libcalamares.utils.warning(
                "Refusing to resize {0}: dirty/hibernated NTFS".format(device))
            return (
                _("Cannot resize the Windows partition"),
                _("Your Windows installation was shutdown in a dirty/hibernated "
                  "state and your Windows partition is refusing to be resized. "
                  "Reboot into Windows and shutdown with the shutdown option in "
                  "the start menu to shutdown cleanly before retrying the "
                  "installation"),
            )

    return None
