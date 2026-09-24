#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# Pre-resize guard for "Install alongside" and manual partitioning. Windows
# Fast Startup (and hibernation) leave the NTFS volume dirty, so ntfsresize
# refuses to shrink it and the partition module aborts with an opaque error.
# Catch that state first, before any partition is touched, and tell the user
# how to fix it.

import json
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


def ntfs_devices(skip_external=False):
    """/dev paths of every NTFS partition visible to the live system.

    With skip_external, partitions on removable, hotplug or USB drives are
    left out.
    """
    try:
        out = subprocess.run(
            ["lsblk", "-Jpo", "NAME,FSTYPE,RM,HOTPLUG,TRAN"],
            capture_output=True, text=True, timeout=30,
        ).stdout
        tree = json.loads(out or "{}")
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        libcalamares.utils.warning("lsblk failed: {!s}".format(exc))
        return []

    devices = []

    def walk(nodes, parent_external):
        for node in nodes or ():
            # lsblk names the transport on the whole disk only, so a partition
            # takes it from the disk above it.
            external = parent_external or node.get("rm") in (True, "1") \
                or node.get("hotplug") in (True, "1") or node.get("tran") == "usb"
            name = node.get("name")
            # Accept both the on-disk type ("ntfs") and the ntfs3-driver
            # spelling.
            fstype = (node.get("fstype") or "").lower()
            if fstype in ("ntfs", "ntfs3") and name and name not in devices \
                    and not (skip_external and external):
                devices.append(name)
            walk(node.get("children"), external)

    walk(tree.get("blockdevices"), False)
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
    # "alongside" shrinks an existing NTFS volume, and "manual" can resize one
    # or keep one beside the new system. Which partitions a manual layout
    # touches is known only inside the partition module, whose plan reaches
    # global storage after this runs, so manual checks every NTFS partition
    # except those on drives that can be unplugged: a USB disk last pulled
    # from a Windows machine without ejecting is often dirty, and is almost
    # never part of the layout. Erase and replace either wipe or leave it
    # untouched, so there is nothing to guard.
    choices = libcalamares.globalstorage.value("partitionChoices") or {}
    install = choices.get("install")
    if install not in ("alongside", "manual"):
        return None

    for device in ntfs_devices(skip_external=(install == "manual")):
        if ntfs_blocks_resize(device):
            libcalamares.utils.warning(
                "Refusing to install ({0}): dirty/hibernated NTFS on {1}".format(
                    install, device))
            if install == "manual":
                return (
                    _("Windows was not shut down cleanly"),
                    _("The Windows partition {0} was left hibernated or in a "
                      "dirty state, so it cannot be resized or safely kept "
                      "beside the new system. Start Windows, hold Shift while "
                      "you choose Shut down from the Start menu, then run the "
                      "installer again. With Fast Startup on, a normal Shut "
                      "down hibernates Windows again, so either hold Shift or "
                      "turn Fast Startup off in Power Options. If that "
                      "partition is on a drive the new system does not need, "
                      "you can unplug the drive and run the installer again "
                      "instead. To remove that partition, use Erase disk or "
                      "Replace a partition, which skip this "
                      "check.").format(device),
                )
            return (
                _("Cannot resize the Windows partition"),
                _("Your Windows installation was shut down in a dirty or "
                  "hibernated state, and your Windows partition is refusing "
                  "to be resized. Start Windows, hold Shift while you choose "
                  "Shut down from the Start menu, then retry the "
                  "installation. With Fast Startup on, a normal Shut down "
                  "hibernates Windows again, so either hold Shift or turn "
                  "Fast Startup off in Power Options."),
            )

    return None
