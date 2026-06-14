#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# === This file is part of Calamares - <https://calamares.io> ===
#
#   SPDX-FileCopyrightText: 2014 Pier Luigi Fiorini <pierluigi.fiorini@gmail.com>
#   SPDX-FileCopyrightText: 2015-2017 Teo Mrnjavac <teo@kde.org>
#   SPDX-FileCopyrightText: 2016-2017 Kyle Robbertze <kyle@aims.ac.za>
#   SPDX-FileCopyrightText: 2017 Alf Gaida <agaida@siduction.org>
#   SPDX-FileCopyrightText: 2018 Adriaan de Groot <groot@kde.org>
#   SPDX-FileCopyrightText: 2018 Philip Müller <philm@manjaro.org>
#   SPDX-License-Identifier: GPL-3.0-or-later
#
#   Calamares is Free Software: see the License-Identifier above.
#
# --- Mainstream OS additions ---
#   PMPacmanFlatpak: hybrid backend that installs native packages with
#   pacman (official repos only — no AUR helper) and auto-routes Flatpak
#   refs to flatpak. The AUR is deliberately not used at install time.
#   Inserted after PMPacman, before PMPamac (alphabetical by backend name).
#

import abc
import os
from string import Template
import subprocess

import libcalamares
from libcalamares.utils import check_target_env_call, target_env_call
from libcalamares.utils import gettext_path, gettext_languages

import gettext
_translation = gettext.translation("calamares-python",
                                   localedir=gettext_path(),
                                   languages=gettext_languages(),
                                   fallback=True)
_ = _translation.gettext
_n = _translation.ngettext


total_packages = 0  # For the entire job
completed_packages = 0  # Done so far for this job
group_packages = 0  # One group of packages from an -install or -remove entry

# A PM object may set this to a string (take care of translations!)
# to override the string produced by pretty_status_message()
custom_status_message = None

INSTALL = object()
REMOVE = object()
mode_packages = None  # Changes to INSTALL or REMOVE


def _change_mode(mode):
    global mode_packages
    mode_packages = mode
    libcalamares.job.setprogress(completed_packages * 1.0 / total_packages)


def pretty_name():
    return _("Install packages.")


def pretty_status_message():
    if custom_status_message is not None:
        return custom_status_message
    if not group_packages:
        if (total_packages > 0):
            s = _("Processing packages (%(count)d / %(total)d)")
        else:
            s = _("Install packages.")

    elif mode_packages is INSTALL:
        s = _n("Installing one package.",
               "Installing %(num)d packages.", group_packages)
    elif mode_packages is REMOVE:
        s = _n("Removing one package.",
               "Removing %(num)d packages.", group_packages)
    else:
        s = _("Install packages.")

    return s % {"num": group_packages,
                "count": completed_packages,
                "total": total_packages}


class PackageManager(metaclass=abc.ABCMeta):
    """
    Package manager base class. A subclass implements package management
    for a specific backend, and must have a class property `backend`
    with the string identifier for that backend.

    Subclasses are collected below to populate the list of possible
    backends.
    """
    backend = None

    @abc.abstractmethod
    def install(self, pkgs, from_local=False):
        pass

    @abc.abstractmethod
    def remove(self, pkgs):
        pass

    @abc.abstractmethod
    def update_db(self):
        pass

    def run(self, script):
        if script != "":
            check_target_env_call(script.split(" "))

    def install_package(self, packagedata, from_local=False):
        if isinstance(packagedata, str):
            self.install([packagedata], from_local=from_local)
        else:
            self.run(packagedata["pre-script"])
            self.install([packagedata["package"]], from_local=from_local)
            self.run(packagedata["post-script"])

    def remove_package(self, packagedata):
        if isinstance(packagedata, str):
            self.remove([packagedata])
        else:
            self.run(packagedata["pre-script"])
            self.remove([packagedata["package"]])
            self.run(packagedata["post-script"])

    def operation_install(self, package_list, from_local=False):
        if all([isinstance(x, str) for x in package_list]):
            self.install(package_list, from_local=from_local)
        else:
            for package in package_list:
                self.install_package(package, from_local=from_local)

    def operation_try_install(self, package_list):
        for package in package_list:
            try:
                self.install_package(package)
            except subprocess.CalledProcessError:
                libcalamares.utils.warning("Could not install package %s" % package)

    def operation_remove(self, package_list):
        if all([isinstance(x, str) for x in package_list]):
            self.remove(package_list)
        else:
            for package in package_list:
                self.remove_package(package)

    def operation_try_remove(self, package_list):
        for package in package_list:
            try:
                self.remove_package(package)
            except subprocess.CalledProcessError:
                libcalamares.utils.warning("Could not remove package %s" % package)


### PACKAGE MANAGER IMPLEMENTATIONS
#
# Keep these alphabetical (by backend name).
#

class PMApk(PackageManager):
    backend = "apk"

    def install(self, pkgs, from_local=False):
        for pkg in pkgs:
            check_target_env_call(["apk", "add", pkg])

    def remove(self, pkgs):
        for pkg in pkgs:
            check_target_env_call(["apk", "del", pkg])

    def update_db(self):
        check_target_env_call(["apk", "update"])

    def update_system(self):
        check_target_env_call(["apk", "upgrade", "--available"])


class PMApt(PackageManager):
    backend = "apt"

    def install(self, pkgs, from_local=False):
        check_target_env_call(["apt-get", "-q", "-y", "install"] + pkgs)

    def remove(self, pkgs):
        check_target_env_call(["apt-get", "--purge", "-q", "-y", "remove"] + pkgs)
        check_target_env_call(["apt-get", "--purge", "-q", "-y", "autoremove"])

    def update_db(self):
        check_target_env_call(["apt-get", "update"])

    def update_system(self):
        pass


class PMDnf(PackageManager):
    backend = "dnf"

    def install(self, pkgs, from_local=False):
        check_target_env_call(["dnf-3", "-y", "install"] + pkgs)

    def remove(self, pkgs):
        target_env_call(["dnf-3", "--disablerepo=*", "-C", "-y", "remove"] + pkgs)

    def update_db(self):
        pass

    def update_system(self):
        check_target_env_call(["dnf-3", "-y", "upgrade"])


class PMDnf5(PackageManager):
    backend = "dnf5"

    def install(self, pkgs, from_local=False):
        check_target_env_call(["dnf5", "-y", "install"] + pkgs)

    def remove(self, pkgs):
        target_env_call(["dnf5", "--disablerepo=*", "-C", "-y", "remove"] + pkgs)

    def update_db(self):
        pass

    def update_system(self):
        check_target_env_call(["dnf5", "-y", "upgrade"])


class PMDummy(PackageManager):
    backend = "dummy"

    def install(self, pkgs, from_local=False):
        from time import sleep
        libcalamares.utils.debug("Dummy backend: Installing " + str(pkgs))
        sleep(3)

    def remove(self, pkgs):
        from time import sleep
        libcalamares.utils.debug("Dummy backend: Removing " + str(pkgs))
        sleep(3)

    def update_db(self):
        libcalamares.utils.debug("Dummy backend: Updating DB")

    def update_system(self):
        libcalamares.utils.debug("Dummy backend: Updating System")

    def run(self, script):
        libcalamares.utils.debug("Dummy backend: Running script '" + str(script) + "'")


class PMEntropy(PackageManager):
    backend = "entropy"

    def install(self, pkgs, from_local=False):
        check_target_env_call(["equo", "i"] + pkgs)

    def remove(self, pkgs):
        check_target_env_call(["equo", "rm"] + pkgs)

    def update_db(self):
        check_target_env_call(["equo", "update"])

    def update_system(self):
        pass


class PMFlatpak(PackageManager):
    backend = "flatpak"

    def install(self, pkgs, from_local=False):
        check_target_env_call(["flatpak", "install", "--assumeyes"] + pkgs)

    def remove(self, pkgs):
        check_target_env_call(["flatpak", "uninstall", "--noninteractive"] + pkgs)

    def update_db(self):
        pass

    def update_system(self):
        pass


class PMLuet(PackageManager):
    backend = "luet"

    def install(self, pkgs, from_local=False):
        check_target_env_call(["luet", "install", "-y"] + pkgs)

    def remove(self, pkgs):
        check_target_env_call(["luet", "uninstall", "-y"] + pkgs)

    def update_db(self):
        pass

    def update_system(self):
        check_target_env_call(["luet", "upgrade", "-y"])


class PMPackageKit(PackageManager):
    backend = "packagekit"

    def install(self, pkgs, from_local=False):
        for pkg in pkgs:
            check_target_env_call(["pkcon", "-py", "install", pkg])

    def remove(self, pkgs):
        for pkg in pkgs:
            check_target_env_call(["pkcon", "-py", "remove", pkg])

    def update_db(self):
        check_target_env_call(["pkcon", "refresh"])

    def update_system(self):
        check_target_env_call(["pkcon", "-py", "update"])


class PMPacman(PackageManager):
    backend = "pacman"

    def __init__(self):
        import re
        progress_match = re.compile("^\\((\\d+)/(\\d+)\\)")

        def line_cb(line):
            if line.startswith(":: "):
                self.in_package_changes = "package" in line or "hooks" in line
            else:
                if self.in_package_changes and line.endswith("...\n"):
                    global custom_status_message
                    custom_status_message = "pacman: " + line.strip()
                    libcalamares.job.setprogress(self.progress_fraction)
            libcalamares.utils.debug(line)

        self.in_package_changes = False
        self.line_cb = line_cb

        pacman = libcalamares.job.configuration.get("pacman", None)
        if pacman is None:
            pacman = dict()
        if type(pacman) is not dict:
            libcalamares.utils.warning("Job configuration *pacman* will be ignored.")
            pacman = dict()
        self.pacman_num_retries = pacman.get("num_retries", 0)
        self.pacman_disable_timeout = pacman.get("disable_download_timeout", False)
        self.pacman_needed_only = pacman.get("needed_only", False)

    def reset_progress(self):
        self.in_package_changes = False
        self.progress_fraction = (completed_packages * 1.0 / total_packages)

    def run_pacman(self, command, callback=False):
        pacman_count = 0
        while pacman_count <= self.pacman_num_retries:
            pacman_count += 1
            try:
                if False:  # callback:
                    libcalamares.utils.target_env_process_output(command, self.line_cb)
                else:
                    libcalamares.utils.target_env_process_output(command)
                return
            except subprocess.CalledProcessError:
                if pacman_count <= self.pacman_num_retries:
                    pass
                else:
                    raise

    def install(self, pkgs, from_local=False):
        command = ["pacman"]

        if from_local:
            command.append("-U")
        else:
            command.append("-S")

        command.append("--noconfirm")
        command.append("--noprogressbar")

        if self.pacman_needed_only is True:
            command.append("--needed")

        if self.pacman_disable_timeout is True:
            command.append("--disable-download-timeout")

        command += pkgs

        self.reset_progress()
        self.run_pacman(command, True)

    def remove(self, pkgs):
        self.reset_progress()
        self.run_pacman(["pacman", "-Rs", "--noconfirm"] + pkgs, True)

    def update_db(self):
        self.run_pacman(["pacman", "-Sy"])

    def update_system(self):
        command = ["pacman", "-Su", "--noconfirm"]
        if self.pacman_disable_timeout is True:
            command.append("--disable-download-timeout")
        self.run_pacman(command)


class PMPamac(PackageManager):
    backend = "pamac"

    def del_db_lock(self, lock="/var/lib/pacman/db.lck"):
        check_target_env_call(["rm", "-f", lock])

    def install(self, pkgs, from_local=False):
        self.del_db_lock()
        check_target_env_call([self.backend, "install", "--no-confirm"] + pkgs)

    def remove(self, pkgs):
        self.del_db_lock()
        check_target_env_call([self.backend, "remove", "--no-confirm"] + pkgs)

    def update_db(self):
        self.del_db_lock()
        check_target_env_call([self.backend, "update", "--no-confirm"])

    def update_system(self):
        self.del_db_lock()
        check_target_env_call([self.backend, "upgrade", "--no-confirm"])


class PMPisi(PackageManager):
    backend = "pisi"

    def install(self, pkgs, from_local=False):
        check_target_env_call(["pisi", "install" "-y"] + pkgs)

    def remove(self, pkgs):
        check_target_env_call(["pisi", "remove", "-y"] + pkgs)

    def update_db(self):
        check_target_env_call(["pisi", "update-repo"])

    def update_system(self):
        pass


class PMPortage(PackageManager):
    backend = "portage"

    def install(self, pkgs, from_local=False):
        check_target_env_call(["emerge", "-v"] + pkgs)

    def remove(self, pkgs):
        check_target_env_call(["emerge", "-C"] + pkgs)
        check_target_env_call(["emerge", "--depclean", "-q"])

    def update_db(self):
        check_target_env_call(["emerge", "--sync"])

    def update_system(self):
        pass


class PMXbps(PackageManager):
    backend = "xbps"

    def line_cb(self, line):
        libcalamares.utils.debug(line)

    def run_xbps(self, command):
        libcalamares.utils.target_env_process_output(command, self.line_cb)

    def install(self, pkgs, from_local=False):
        self.run_xbps(["xbps-install", "-Sy"] + pkgs)

    def remove(self, pkgs):
        self.run_xbps(["xbps-remove", "-Ry"] + pkgs)

    def update_db(self):
        self.run_xbps(["xbps-install", "-S"])

    def update_system(self):
        self.run_xbps(["xbps", "-Suy"])


class PMPacmanFlatpak(PackageManager):
    """
    Hybrid backend: native packages via pacman (official repos only),
    Flatpak refs via flatpak. No AUR helper is involved.

    The netinstall list mixes native Arch package names (gnome-disk-utility,
    mpv, steam) with Flatpak refs (com.spotify.Client, org.gnome.TextEditor).
    install() routes each entry by name shape:
      - dotted reverse-DNS name → flatpak (installed from the live env so
        bwrap can unshare a user namespace; see _flatpak_run)
      - everything else → pacman -S in the target chroot, official repos
        only. The AUR is intentionally not a supported install source.

    remove()/update_db()/update_system() use pacman directly. Each package
    in try_install() is attempted individually so one failure does not block
    the rest of the optional install list.
    """
    backend = "pacmanflatpak"

    def __init__(self):
        self.in_package_changes = False
        self.progress_fraction = 0.0
        # Lazy flathub-remote setup: the first time install() encounters a
        # Flatpak ref in the package list, _ensure_flathub_remote() runs
        # `flatpak remote-add --if-not-exists flathub ...` once and flips
        # this flag. Idempotent on rerun (the remote-add is itself
        # idempotent, this just saves a fork per package).
        self.flathub_added = False

        # Pipe pacman/flatpak output to the Calamares log, but DON'T let it
        # overwrite custom_status_message — the per-package iteration in
        # install() already sets "Installing PKG" as a clean, stable label,
        # and we don't want it replaced (even momentarily) by transitional
        # lines like ":: Synchronizing package databases..." or pacman's
        # "warning: foo is up to date -- reinstalling", which would look
        # alarming under the progress bar even when the install is fine.
        # The log panel (when expanded) still shows everything verbatim.
        def line_cb(line):
            libcalamares.utils.debug(line)

        self.line_cb = line_cb

    @staticmethod
    def _is_flatpak_ref(name):
        """A Flatpak ref is a reverse-DNS triple like com.spotify.Client or
        org.gnome.TextEditor. Native Arch package names don't contain dots —
        the dot is a reliable single-character discriminator without needing
        a registry of known refs.
        """
        return "." in name

    def _flatpak_run(self, args, output_cb=None):
        """Run a flatpak command from the LIVE env, with FLATPAK_SYSTEM_DIR
        pointed at the install target.

        We cannot chroot into the target for this — bwrap (used internally
        by flatpak to sandbox apply_extra scripts that Chrome / Spotify
        ship) can't create a user namespace inside a chroot, so any
        extra-data ref fails with:

            bwrap: No permissions to create a new namespace
            apply_extra script failed, exit status 256

        Running flatpak directly from the live env keeps bwrap operating
        on the host kernel where namespace cloning works. The
        FLATPAK_SYSTEM_DIR env var redirects flatpak's system data dir
        (default /var/lib/flatpak) into the target's filesystem, so the
        install persists on the installed system exactly as if it had
        been run in-chroot.

        (Note: `flatpak --sysroot` does NOT exist — the only ways to
        retarget the system dir are FLATPAK_SYSTEM_DIR or the named
        `--installation=NAME` mechanism with a /etc/flatpak/installations.d
        config file. The env var is the lighter touch.)

        Requires the live ISO to ship the `flatpak` package — added to
        packages.x86_64 alongside the calamares-mainstream block.
        """
        rootmount = libcalamares.globalstorage.value("rootMountPoint") or "/"
        env = os.environ.copy()
        env["FLATPAK_SYSTEM_DIR"] = rootmount.rstrip("/") + "/var/lib/flatpak"
        cmd = ["flatpak"] + list(args)
        # Stream output line-by-line through output_cb so the Calamares
        # log mirrors what target_env_process_output used to give us.
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, env=env)
        captured = []
        if proc.stdout is not None:
            for line in proc.stdout:
                captured.append(line)
                if output_cb is not None:
                    output_cb(line)
        proc.wait()
        if proc.returncode != 0:
            raise subprocess.CalledProcessError(
                proc.returncode, cmd, output="".join(captured))

    def _ensure_flathub_remote(self):
        """Add the Flathub remote system-wide if it's missing. Runs from
        the live env via _flatpak_run so --sysroot redirects the remote
        config into the target's /var/lib/flatpak.

        `--if-not-exists` is idempotent; we still cache on self so we
        don't fork+exec on every Flatpak install in a long selection.
        """
        if self.flathub_added:
            return
        try:
            self._flatpak_run(
                ["remote-add", "--if-not-exists", "--system",
                 "flathub", "https://flathub.org/repo/flathub.flatpakrepo"],
                self.line_cb)
        except subprocess.CalledProcessError as e:
            libcalamares.utils.warning(
                "flatpak remote-add for flathub failed (continuing): " + str(e))
        self.flathub_added = True

    def reset_progress(self):
        self.in_package_changes = False
        self.progress_fraction = (completed_packages * 1.0 / total_packages)

    def install_package(self, packagedata, from_local=False):
        """
        Override the base class's install_package() so the dict shape
        carries through to install() intact. Upstream strips out the
        `display` key (and anything else not in {pre-script, package,
        post-script}) by passing only `packagedata["package"]` to
        install(); we want install() to see the whole dict so the
        per-package status message can use the friendly display label.
        """
        if isinstance(packagedata, str):
            self.install([packagedata], from_local=from_local)
        else:
            pre = packagedata.get("pre-script", "")
            post = packagedata.get("post-script", "")
            if pre:
                self.run(pre)
            self.install([packagedata], from_local=from_local)
            if post:
                self.run(post)

    @staticmethod
    def _unpack(pkg):
        """Resolve (install_name, display_label) for either format.

        netinstall packages with a `display:` field arrive here as a
        dict {package: "com.spotify.Client", display: "Spotify",
        [pre-script, post-script]}. Plain entries (no display, no
        scripts) arrive as a bare string.
        """
        if isinstance(pkg, dict):
            name = pkg.get("package", "")
            display = pkg.get("display") or name
        else:
            name = pkg
            display = pkg
        return name, display

    def install(self, pkgs, from_local=False):
        """
        Install packages ONE AT A TIME so each install can update the
        progress bar's status line with the current package name, and so
        one failing entry (a Flatpak ref that vanished from Flathub, say)
        does not abort the whole curated selection. Every iteration sets
        ``custom_status_message = "Installing X"`` first, so the panel
        below the progress bar tracks real progress instead of sitting on
        a stale "Install packages." string.

        Cost: pacman startup + a separate transaction per native package.
        For repo packages that's cheap relative to the download, and the
        per-package UI feedback pays for it. ``--needed`` makes the
        separate transactions idempotent and dedup-safe.
        """
        if not pkgs:
            return
        self.reset_progress()

        global custom_status_message
        for idx, pkg in enumerate(pkgs):
            pkg_name, pkg_display = self._unpack(pkg)
            # Surface the current package name under the progress bar.
            # setprogress() is what triggers a UI refresh of the status
            # message, so the order matters — set the message THEN call
            # setprogress to push the update to the QML view.
            custom_status_message = _("Installing %s") % pkg_display
            progress = (completed_packages + idx) * 1.0 / total_packages
            libcalamares.job.setprogress(progress)

            # localInstall: pkg_name is a local .pkg.tar.zst path, which
            # contains dots and would otherwise be misrouted to flatpak by
            # the ref check below. Local files are always pacman -U. Checked
            # first so the from_local contract holds.
            if from_local:
                command = [
                    "pacman", "-U", "--noconfirm", "--needed",
                    "--noprogressbar", "--", pkg_name,
                ]
                libcalamares.utils.target_env_process_output(command, self.line_cb)
                continue

            # Auto-route: Flatpak refs (containing dots) → flatpak,
            # everything else → pacman. The netinstall mixes both freely;
            # com.spotify.Client goes to Flathub, gnome-disk-utility / mpv
            # / steam go to the official Arch repos.
            if self._is_flatpak_ref(pkg_name):
                self._ensure_flathub_remote()
                # `_flatpak_run` runs flatpak on the LIVE env with
                # FLATPAK_SYSTEM_DIR pointed at the target's
                # /var/lib/flatpak. This is necessary because the same
                # call inside target_env_call would chroot, and bwrap
                # (used internally for the apply_extra sandbox in
                # extra-data refs like Chrome / Spotify) can't unshare
                # CLONE_NEWUSER inside a chroot. State still lands in
                # the target's /var/lib/flatpak via the env-var
                # redirect, so the installed system has the apps
                # available as if the install had run in-chroot.
                self._flatpak_run(
                    ["install", "--system",
                     "--noninteractive", "--assumeyes",
                     "flathub", pkg_name],
                    self.line_cb)
                continue
            # Native package → pacman -S in the target chroot as root, from
            # the official repos only. No AUR helper: the netinstall list is
            # curated so every native entry resolves from the repos, and the
            # AUR is not a trusted install source.
            command = [
                "pacman", "-S", "--noconfirm", "--needed",
                "--noprogressbar", "--", pkg_name,
            ]
            libcalamares.utils.target_env_process_output(command, self.line_cb)

    def remove(self, pkgs):
        if not pkgs:
            return
        self.reset_progress()
        # Flatpak-installed apps aren't pacman-owned, but the netinstall
        # only ever installs (never removes) Flatpak refs, so -Rs on the
        # native names is all this path needs.
        check_target_env_call(["pacman", "-Rs", "--noconfirm"] + pkgs)

    def update_db(self):
        check_target_env_call(["pacman", "-Sy"])

    def update_system(self):
        check_target_env_call(["pacman", "-Su", "--noconfirm"])


class PMYum(PackageManager):
    backend = "yum"

    def install(self, pkgs, from_local=False):
        check_target_env_call(["yum", "-y", "install"] + pkgs)

    def remove(self, pkgs):
        check_target_env_call(["yum", "--disablerepo=*", "-C", "-y", "remove"] + pkgs)

    def update_db(self):
        pass

    def update_system(self):
        check_target_env_call(["yum", "-y", "upgrade"])


class PMZypp(PackageManager):
    backend = "zypp"

    def install(self, pkgs, from_local=False):
        check_target_env_call(["zypper", "--non-interactive",
                               "--quiet-install", "install",
                               "--auto-agree-with-licenses",
                               "install"] + pkgs)

    def remove(self, pkgs):
        check_target_env_call(["zypper", "--non-interactive", "remove"] + pkgs)

    def update_db(self):
        check_target_env_call(["zypper", "--non-interactive", "update"])

    def update_system(self):
        pass


# Collect all subclasses of PackageManager defined above,
# indexed by their backend property.
backend_managers = [
    (c.backend, c)
    for c in globals().values()
    if type(c) is abc.ABCMeta and issubclass(c, PackageManager) and c.backend]


def subst_locale(plist):
    locale = libcalamares.globalstorage.value("locale")
    if not locale:
        locale = "en"

    ret = []
    for packagedata in plist:
        if isinstance(packagedata, str):
            packagename = packagedata
        else:
            packagename = packagedata["package"]

        if locale != "en":
            packagename = Template(packagename).safe_substitute(LOCALE=locale)
        elif 'LOCALE' in packagename:
            packagename = None

        if packagename is not None:
            if isinstance(packagedata, str):
                packagedata = packagename
            else:
                packagedata["package"] = packagename
            ret.append(packagedata)

    return ret


def run_operations(pkgman, entry):
    global group_packages, completed_packages, mode_packages

    for key in entry.keys():
        package_list = subst_locale(entry[key])
        group_packages = len(package_list)
        if key == "install":
            _change_mode(INSTALL)
            pkgman.operation_install(package_list)
        elif key == "try_install":
            _change_mode(INSTALL)
            pkgman.operation_try_install(package_list)
        elif key == "remove":
            _change_mode(REMOVE)
            pkgman.operation_remove(package_list)
        elif key == "try_remove":
            _change_mode(REMOVE)
            pkgman.operation_try_remove(package_list)
        elif key == "localInstall":
            _change_mode(INSTALL)
            pkgman.operation_install(package_list, from_local=True)
        elif key == "source":
            libcalamares.utils.debug("Package-list from {!s}".format(entry[key]))
        else:
            libcalamares.utils.warning("Unknown package-operation key {!s}".format(key))
        completed_packages += len(package_list)
        libcalamares.job.setprogress(completed_packages * 1.0 / total_packages)
        libcalamares.utils.debug("Pretty name: {!s}, setting progress..".format(pretty_name()))

    group_packages = 0
    _change_mode(None)


def run():
    global mode_packages, total_packages, completed_packages, group_packages

    backend = libcalamares.job.configuration.get("backend")

    for identifier, impl in backend_managers:
        if identifier == backend:
            pkgman = impl()
            break
    else:
        return "Bad backend", "backend=\"{}\"".format(backend)

    skip_this = libcalamares.job.configuration.get("skip_if_no_internet", False)
    if skip_this and not libcalamares.globalstorage.value("hasInternet"):
        libcalamares.utils.warning("Package installation has been skipped: no internet")
        return None

    update_db = libcalamares.job.configuration.get("update_db", False)
    if update_db and libcalamares.globalstorage.value("hasInternet"):
        try:
            pkgman.update_db()
        except subprocess.CalledProcessError as e:
            libcalamares.utils.warning(str(e))
            libcalamares.utils.debug("stdout:" + str(e.stdout))
            libcalamares.utils.debug("stderr:" + str(e.stderr))
            return (_("Package Manager error"),
                    _("The package manager could not prepare updates. The command <pre>{!s}</pre> returned error code {!s}.")
                    .format(e.cmd, e.returncode))

    update_system = libcalamares.job.configuration.get("update_system", False)
    if update_system and libcalamares.globalstorage.value("hasInternet"):
        try:
            pkgman.update_system()
        except subprocess.CalledProcessError as e:
            libcalamares.utils.warning(str(e))
            libcalamares.utils.debug("stdout:" + str(e.stdout))
            libcalamares.utils.debug("stderr:" + str(e.stderr))
            return (_("Package Manager error"),
                    _("The package manager could not update the system. The command <pre>{!s}</pre> returned error code {!s}.")
                    .format(e.cmd, e.returncode))

    operations = libcalamares.job.configuration.get("operations", [])
    if libcalamares.globalstorage.contains("packageOperations"):
        operations += libcalamares.globalstorage.value("packageOperations")

    mode_packages = None
    total_packages = 0
    completed_packages = 0
    for op in operations:
        for packagelist in op.values():
            total_packages += len(subst_locale(packagelist))

    if not total_packages:
        # Loud no-op warning. Hit this when the user picked Default Apps
        # (or any preselect-group install method) but `packageOperations`
        # ended up empty in GlobalStorage — usually means
        # NetInstallViewStep's auto-skip path didn't reach
        # finalizeGlobalStorage with selections applied. Worth a clear
        # log line because the progress bar still races to 100% and the
        # user has no other signal that the install list disappeared.
        choice = libcalamares.globalstorage.value("installmethod_choice") or "<unset>"
        preselect = libcalamares.globalstorage.value("installmethod_preselect_group") or "<unset>"
        has_pko = libcalamares.globalstorage.contains("packageOperations")
        libcalamares.utils.warning(
            "packages: nothing to do — total_packages == 0. "
            "installmethod_choice=%r preselect_group=%r "
            "globalstorage_has_packageOperations=%s inline_operations=%d"
            % (choice, preselect, has_pko, len(libcalamares.job.configuration.get("operations", []))))
        return None

    for entry in operations:
        group_packages = 0
        libcalamares.utils.debug(pretty_name())
        try:
            run_operations(pkgman, entry)
        except subprocess.CalledProcessError as e:
            libcalamares.utils.warning(str(e))
            libcalamares.utils.debug("stdout:" + str(e.stdout))
            libcalamares.utils.debug("stderr:" + str(e.stderr))
            return (_("Package Manager error"),
                    _("The package manager could not make changes to the installed system. The command <pre>{!s}</pre> returned error code {!s}.")
                    .format(e.cmd, e.returncode))

    mode_packages = None
    libcalamares.job.setprogress(1.0)
    return None
