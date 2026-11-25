#!/usr/bin/env python3
# Records the Custom app list's kernel, app source and Proton checkboxes for the
# install steps, and fetches the chosen Mainstream kernels before install-limine.

import os
import subprocess

import libcalamares

CHOICES_FILE = "/etc/mainstream-install/choices.conf"
FETCH_ONLINE = "/usr/local/bin/mainstream-fetch-online"
CPUINFO = "/proc/cpuinfo"
# Order of preference: the first one installed becomes the default.
KERNELS = ("linux-mainstream-performance", "linux-mainstream", "linux")
PROTONS = ("mainstream", "ge", "cachyos")
METHODS = ("default", "custom", "console", "os-only", "developer", "gaming")


def pretty_name():
    return "Saving the install choices"


def choice_items(operations):
    """Names of the checked choice items (kernel:, apps:, proton:) in the
    app list's package operations; no package or Flatpak name has a ':'."""
    names = set()
    for op in operations or []:
        if not isinstance(op, dict):
            continue
        for key in ("install", "try_install"):
            for item in op.get(key) or []:
                name = item.get("package") if isinstance(item, dict) else item
                if isinstance(name, str) and ":" in name:
                    names.add(name)
    return names


def cpu_runs_x86_64_v3(path=CPUINFO):
    """The performance kernel's CPU level; the same test as mainstream-kernels."""
    try:
        with open(path) as f:
            for line in f:
                if line.startswith("flags"):
                    flags = set(line.split(":", 1)[1].split())
                    break
            else:
                return False
    except OSError:
        return False
    needed = {"avx", "avx2", "bmi1", "bmi2", "f16c", "fma", "movbe", "xsave"}
    return needed <= flags and bool({"abm", "lzcnt"} & flags)


def resolve(method, items, v3):
    """(app source, kernels, protons). Without the Custom app list the install
    keeps today's defaults."""
    if method != "custom":
        return "native", ["linux-mainstream", "linux"], ["mainstream"]
    apps = "flatpak" if "apps:flatpak" in items else "native"
    kernels = []
    for k in KERNELS:
        if "kernel:" + k not in items:
            continue
        # A CPU without x86-64-v3 would not boot the performance kernel.
        if k == "linux-mainstream-performance" and not v3:
            k = "linux-mainstream"
        if k not in kernels:
            kernels.append(k)
    protons = [p for p in PROTONS if "proton:" + p in items]
    return apps, kernels or ["linux-mainstream"], protons


def edition_kernel(root):
    """The kernel the image installs; an edition with its own (linux-t2) takes no other."""
    modules = os.path.join(root, "usr/lib/modules")
    try:
        entries = sorted(os.listdir(modules))
    except OSError:
        entries = []
    for d in entries:
        try:
            with open(os.path.join(modules, d, "pkgbase")) as f:
                name = f.read().strip()
        except OSError:
            continue
        if name and not name.startswith("linux-mainstream"):
            return name
    return "linux"


def run():
    gs = libcalamares.globalstorage
    method = gs.value("installmethod_choice")
    method = method if method in METHODS else "default"
    root = gs.value("rootMountPoint")
    if not root:
        return ("No target to record the install choices in",
                "The installer did not report where the new system is mounted.")
    apps, kernels, protons = resolve(method, choice_items(gs.value("packageOperations")), cpu_runs_x86_64_v3())
    path = os.path.join(root, CHOICES_FILE.lstrip("/"))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("APP_SOURCE=%s\nKERNELS=%s\nPROTONS=%s\nMETHOD=%s\n"
                % (apps, " ".join(kernels), " ".join(protons), method))
    os.chmod(path, 0o644)
    # The packages step installs the Custom app list's apps from this source.
    gs.insert("installchoices_appsource", apps)
    libcalamares.utils.debug("install choices: apps %s, kernels %s, protons %s, method %s"
                             % (apps, kernels, protons, method))

    wanted = [k for k in kernels if k.startswith("linux-mainstream")] if edition_kernel(root) == "linux" else []
    if wanted and os.access(FETCH_ONLINE, os.X_OK):
        args = [FETCH_ONLINE, root]
        for k in wanted:
            args += ["--kernel", k]
        try:
            result = subprocess.run(args, timeout=1800, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True)
            for line in result.stdout.splitlines():
                libcalamares.utils.debug(line)
        except (OSError, subprocess.SubprocessError) as e:
            # The boot loader step then keeps Arch's kernel.
            libcalamares.utils.warning("could not download the chosen kernels: %s" % e)
    return None
