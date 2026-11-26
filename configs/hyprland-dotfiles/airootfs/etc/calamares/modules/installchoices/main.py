#!/usr/bin/env python3
# Records the Custom app list's kernel, app source and Proton checkboxes for the
# install steps, and fetches the chosen Mainstream kernels before install-limine,
# with the NVIDIA driver an older card needs before install-gpu-drivers.

import os
import subprocess

import libcalamares

CHOICES_FILE = "/etc/mainstream-install/choices.conf"
FETCH_ONLINE = "/usr/local/bin/mainstream-fetch-online"
CPUINFO = "/proc/cpuinfo"
PCI_DEVICES = "/sys/bus/pci/devices"
# Order of preference: the first one installed becomes the default.
KERNELS = ("linux-mainstream-performance", "linux-mainstream", "linux")
PROTONS = ("mainstream", "ge", "cachyos")
METHODS = ("default", "custom", "console", "os-only", "developer", "gaming")
# install-limine's room on the boot partition for each kernel it adds.
KERNEL_MIN_FREE_MIB = 512


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
        return "native", ["linux-mainstream"], ["mainstream"]
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


def has_nvidia_display():
    """Whether an NVIDIA display controller is present. fetch-online works out
    whether its driver has to be downloaded."""
    try:
        entries = os.listdir(PCI_DEVICES)
    except OSError:
        return False
    for d in entries:
        try:
            with open(os.path.join(PCI_DEVICES, d, "vendor")) as f:
                vendor = f.read().strip()
            with open(os.path.join(PCI_DEVICES, d, "class")) as f:
                cls = f.read().strip()
        except OSError:
            continue
        if vendor == "0x10de" and cls.startswith("0x03"):
            return True
    return False


def target_kernels(root):
    """The packages of the kernels whose modules are in the target."""
    modules = os.path.join(root, "usr/lib/modules")
    try:
        entries = sorted(os.listdir(modules))
    except OSError:
        entries = []
    names = []
    for d in entries:
        try:
            with open(os.path.join(modules, d, "pkgbase")) as f:
                name = f.read().strip()
        except OSError:
            continue
        if name and name not in names:
            names.append(name)
    return names


def boot_free_mib(root):
    """Free MiB where install-limine puts the boot images: the EFI partition on UEFI."""
    path = os.path.join(root, "boot/efi")
    if not os.path.ismount(path):
        path = os.path.join(root, "boot")
    try:
        st = os.statvfs(path)
    except OSError:
        return None
    return st.f_bavail * st.f_frsize // (1024 * 1024)


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

    # Only the kernels the target lacks: the store does not list the image's own,
    # so fetch-online would download it again.
    wanted = []
    present = target_kernels(root)
    added = [k for k in kernels if k not in present]
    free = boot_free_mib(root)
    for k in added:
        if not k.startswith("linux-mainstream"):
            continue
        # install-limine would leave it out, so the download would be wasted.
        if free is not None and free < KERNEL_MIN_FREE_MIB * (added.index(k) + 1):
            libcalamares.utils.debug("the boot partition has %d MiB free, too little for %s as well; "
                                     "it is not downloaded" % (free, k))
            continue
        wanted.append(k)
    args = [FETCH_ONLINE, root]
    for k in wanted:
        args += ["--kernel", k]
    if has_nvidia_display():
        args.append("--nvidia")
    if len(args) > 2 and os.access(FETCH_ONLINE, os.X_OK):
        try:
            # An older NVIDIA card's driver is several hundred MB on top of the kernels.
            result = subprocess.run(args, timeout=3600, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True)
            for line in result.stdout.splitlines():
                libcalamares.utils.debug(line)
        except (OSError, subprocess.SubprocessError) as e:
            # The boot loader step then keeps the image's kernel, and an older
            # NVIDIA card runs on nouveau until the system update.
            libcalamares.utils.warning("could not download the chosen kernels or the NVIDIA driver: %s" % e)
    return None
