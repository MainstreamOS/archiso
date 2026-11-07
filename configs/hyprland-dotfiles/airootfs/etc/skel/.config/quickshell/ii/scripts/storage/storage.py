#!/usr/bin/env python3
"""Measures disk use and frees space for the Settings Storage page.

scan             One JSON object per line as each result is ready, the last scan's first.
list PATH        The entries of a folder inside Home with their sizes, as JSON.
large            The largest files in Home outside hidden folders, as JSON.
clean ID         Runs one of the cleanups scan offers.
trash PATH       Moves something inside Home to the Trash.
"""

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path

HOME = Path.home()
CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache"))
DATA = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))
LAST_SCAN = CACHE / "quickshell/user/generated/storage-scan.jsonl"
TRASH = DATA / "Trash"
COREDUMPS = Path("/var/lib/systemd/coredump")
KEPT_JOURNAL = 200 * 1024 * 1024
THUMBNAILS = [CACHE / "thumbnails"]
TOOL_CACHES = [CACHE / name for name in ("yay", "paru", "uv", "pip", "pnpm", "go-build")] + [HOME / ".npm/_cacache"]
APPLICATIONS = DATA / "applications"
# Where AppImages are kept by default. Mainstream OS places them in ~/AppImages by default.
APPIMAGE_DIRS = [
    HOME / "AppImages",
    HOME / "Applications",
    HOME / "Downloads",
    HOME / "Desktop",
    HOME / ".local/bin",
    HOME / "bin",
    HOME / ".local/share/AppImages",
    HOME / ".local/share/appimagekit",
    HOME / ".local/share/gearlever",
]
LARGEST_FILES = 15
LARGEST_FILE_MIN = 100 * 1024 * 1024
ENV = {**os.environ, "LC_ALL": "C"}
# Filesystems that hold no files of the user's own.
PSEUDO = {"tmpfs", "devtmpfs", "squashfs", "overlay", "efivarfs", "autofs", "ramfs", "iso9660"}


def run(*command):
    try:
        return subprocess.run(command, capture_output=True, text=True, env=ENV).stdout
    except OSError:
        return ""


def du(*paths, depth=None, every_file=False):
    """{path: bytes} for what du can read; a folder it can't read counts for what it could."""
    command = ["du", "-x", "-B1"]
    if depth is not None:
        command.append(f"--max-depth={depth}")
    if every_file:
        command.append("-a")
    found = [str(path) for path in paths if os.path.lexists(path)]
    if not found:
        return {}
    result = {}
    for line in run(*command, "--", *found).splitlines():
        size, _, path = line.partition("\t")
        if size.isdigit():
            result[path] = int(size)
    return result


def size_of(paths):
    return sum(du(path).get(str(path), 0) for path in paths)


def parse_size(text):
    match = re.search(r"([\d.]+)\s*([KMGT]?)i?B?", text)
    if not match:
        return 0
    return round(float(match[1]) * 1024 ** " KMGT".index(match[2] or " "))


def mounts():
    """(mount, device, filesystem) of every real filesystem, longest path first."""
    found = []
    for line in Path("/proc/self/mountinfo").read_text().splitlines():
        left, _, right = line.partition(" - ")
        mount = left.split()[4].replace("\\040", " ")
        fstype, device = right.split()[:2]
        if fstype not in PSEUDO and device.startswith("/dev/") and not device.startswith("/dev/loop"):
            found.append((mount, device, fstype))
    return sorted(found, key=lambda entry: len(entry[0]), reverse=True)


def device_of(path):
    for mount, device, _ in mounts():
        if str(path) == mount or str(path).startswith(mount.rstrip("/") + "/"):
            return device
    return ""


def disks():
    seen = {}
    for mount, device, fstype in mounts():
        # One filesystem mounted in several places shows once, at its shortest path.
        seen[device] = (mount, fstype)
    result = []
    for device, (mount, fstype) in seen.items():
        if mount == "/boot" or mount.startswith(("/boot/", "/efi")):
            continue
        try:
            stat = os.statvfs(mount)
        except OSError:
            continue
        total = stat.f_blocks * stat.f_frsize
        if total > 0:
            result.append({"kind": "disk", "mount": mount, "device": device, "fstype": fstype, "total": total,
                           "free": stat.f_bavail * stat.f_frsize, "used": total - stat.f_bfree * stat.f_frsize})
    return sorted(result, key=lambda disk: (disk["mount"] != "/", disk["mount"]))


def _mount_for_device(target_dev):
    """Find mountpoint for a block device, stripping Btrfs [/subvol] suffixes."""
    try:
        out = subprocess.check_output(["findmnt", "-rn", "-o", "SOURCE,TARGET"], text=True, stderr=subprocess.DEVNULL)
        first_hit = ""
        for line in out.splitlines():
            cols = line.split(None, 1)
            if len(cols) < 2:
                continue
            src = re.sub(r"\[.*\]$", "", cols[0])
            if src == target_dev:
                if cols[1] == "/":
                    return "/"
                if not first_hit:
                    first_hit = cols[1]
        return first_hit
    except Exception:
        return ""


def efi_info():
    """Information about the EFI system partition and unprivileged GPT resize plan."""
    if not Path("/sys/firmware/efi").exists():
        return None
    esp_gpt_guid = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
    safety_margin = 4 * 1024 * 1024 * 1024  # 4 GiB Btrfs headroom
    cushion = 128 * 1024 * 1024

    for candidate in ("/boot/efi", "/efi", "/boot"):
        try:
            out = subprocess.check_output(
                ["findmnt", "-n", "-o", "SOURCE,FSTYPE,UUID", "-M", candidate],
                text=True, stderr=subprocess.DEVNULL
            ).strip()
        except Exception:
            continue
        if not out:
            continue
        parts = out.split()
        if len(parts) < 2 or parts[1] != "vfat":
            continue
        dev = re.sub(r"\[.*\]$", "", parts[0])
        uuid = parts[2] if len(parts) > 2 else ""

        try:
            ptype = subprocess.check_output(
                ["lsblk", "-dno", "PARTTYPE", dev], text=True, stderr=subprocess.DEVNULL
            ).strip().lower()
        except Exception:
            ptype = ""
        if candidate == "/boot" and ptype != esp_gpt_guid:
            continue

        try:
            stat = os.statvfs(candidate)
        except OSError:
            continue
        total = stat.f_blocks * stat.f_frsize
        if total <= 0:
            continue
        free = stat.f_bavail * stat.f_frsize
        used = total - stat.f_bfree * stat.f_frsize

        # Use raw block device size when readable so FAT overhead doesn't under-report 1 GiB / 2 GiB tiers
        part_bytes = total
        try:
            sz_out = subprocess.check_output(["lsblk", "-bdno", "SIZE", dev], text=True, stderr=subprocess.DEVNULL).strip()
            if sz_out.isdigit():
                part_bytes = int(sz_out)
        except Exception:
            pass

        disk_dev = ""
        part_num = 1
        strategy = "unsupported"
        can_resize = False
        reason = ""
        max_target_bytes = 0
        tail_dev = ""
        tail_fstype = ""
        tail_mount = ""
        tail_free = 0

        try:
            base = os.path.basename(dev)
            sys_part = Path("/sys/class/block") / base
            if (sys_part / "partition").exists():
                part_num = int((sys_part / "partition").read_text().strip())
            pk = subprocess.check_output(["lsblk", "-dno", "PKNAME", dev], text=True, stderr=subprocess.DEVNULL).strip()
            if pk:
                disk_dev = f"/dev/{pk}"
                pttype = subprocess.check_output(
                    ["lsblk", "-dno", "PTTYPE", disk_dev], text=True, stderr=subprocess.DEVNULL
                ).strip().lower()
                sys_disk = Path("/sys/class/block") / pk
                # Linux /sys/class/block/*/start and size are always in 512-byte sectors
                disk_sectors = int((sys_disk / "size").read_text().strip()) if (sys_disk / "size").exists() else 0
                usable_end = max(0, disk_sectors - 34)  # GPT backup header takes 33 512B sectors

                if pttype != "gpt":
                    reason = f"Disk {disk_dev} uses {pttype or 'non-GPT'} partitioning; GPT is required."
                elif disk_sectors > 0:
                    part_entries = []
                    for child in sys_disk.iterdir():
                        if (child / "partition").exists() and (child / "start").exists() and (child / "size").exists():
                            try:
                                st = int((child / "start").read_text().strip())
                                sz = int((child / "size").read_text().strip())
                                part_entries.append((st, sz, f"/dev/{child.name}"))
                            except ValueError:
                                continue
                    part_entries.sort(key=lambda x: x[0])

                    align_sec = 2048  # 1 MiB in 512-byte sectors
                    esp_start = 0
                    next_after_esp = usable_end + 1
                    best_gap_sec = 0
                    cursor = 2048
                    prev_is_esp = False

                    for st, sz, pnode in part_entries:
                        aligned_cur = ((cursor + align_sec - 1) // align_sec) * align_sec
                        if st > aligned_cur:
                            best_gap_sec = max(best_gap_sec, st - aligned_cur)
                        if prev_is_esp:
                            next_after_esp = st
                            prev_is_esp = False
                        if pnode == dev:
                            esp_start = st
                            prev_is_esp = True
                        cursor = st + sz
                        tail_dev = pnode
                        tail_end_sec = st + sz

                    aligned_tail = ((cursor + align_sec - 1) // align_sec) * align_sec
                    if usable_end + 1 > aligned_tail:
                        best_gap_sec = max(best_gap_sec, usable_end + 1 - aligned_tail)

                    max_inplace_bytes = (next_after_esp - esp_start) * 512 if esp_start > 0 else 0
                    best_gap_bytes = best_gap_sec * 512
                    min_next_bytes = part_bytes + 512 * 1024 * 1024

                    if max_inplace_bytes >= min_next_bytes:
                        strategy = "inplace_grow"
                        can_resize = True
                        max_target_bytes = max_inplace_bytes
                        reason = f"Unallocated space follows {dev}; expands directly in place."
                    elif len(part_entries) < 128 and best_gap_bytes >= min_next_bytes:
                        strategy = "new_esp_unallocated"
                        can_resize = True
                        max_target_bytes = best_gap_bytes
                        reason = f"Unallocated space on {disk_dev} will host a dedicated EFI partition."
                    elif tail_dev and tail_dev != dev and len(part_entries) < 128:
                        tail_fstype = subprocess.check_output(
                            ["lsblk", "-dno", "FSTYPE", tail_dev], text=True, stderr=subprocess.DEVNULL
                        ).strip()
                        tail_mount = _mount_for_device(tail_dev)
                        if tail_fstype == "crypto_LUKS":
                            reason = f"Partition {tail_dev} is LUKS-encrypted without unallocated disk space. Shrink it from a live USB first."
                        elif tail_fstype != "btrfs":
                            reason = f"Last partition {tail_dev} uses {tail_fstype or 'unknown'} (online shrink requires mounted Btrfs or unallocated space)."
                        elif not tail_mount:
                            reason = f"Btrfs partition {tail_dev} is not mounted."
                        else:
                            s_tail = os.statvfs(tail_mount)
                            tail_free = s_tail.f_bavail * s_tail.f_frsize
                            trailing_unalloc = max(0, (usable_end + 1 - tail_end_sec) * 512)
                            shrinkable = tail_free + trailing_unalloc - safety_margin - cushion
                            max_target_bytes = max(0, shrinkable)
                            if shrinkable >= min_next_bytes:
                                strategy = "tail_btrfs_relocate"
                                can_resize = True
                                reason = f"Reclaims space from Btrfs ({tail_mount}) to create a dedicated EFI System Partition."
                            else:
                                reason = f"Not enough free space on {tail_mount} to safely carve out a larger EFI partition."
        except Exception:
            pass

        return {
            "kind": "efi",
            "mount": candidate,
            "device": dev,
            "fstype": "vfat",
            "uuid": uuid,
            "total": total,
            "part_bytes": part_bytes,
            "free": free,
            "used": used,
            "disk_device": disk_dev,
            "part_num": part_num,
            "strategy": strategy,
            "can_resize": can_resize,
            "reason": reason,
            "max_target_bytes": max_target_bytes,
            "tail_device": tail_dev,
            "tail_fstype": tail_fstype,
            "tail_mount": tail_mount,
            "tail_free": tail_free,
        }
    return None


def user_folders():
    names = {"documents": ("DOCUMENTS", "Documents"), "downloads": ("DOWNLOAD", "Downloads"),
             "pictures": ("PICTURES", "Pictures"), "videos": ("VIDEOS", "Videos"), "music": ("MUSIC", "Music")}
    configured = {}
    try:
        for line in (Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "user-dirs.dirs").read_text().splitlines():
            match = re.match(r'XDG_(\w+)_DIR="(.*)"', line)
            if match:
                configured[match[1]] = match[2].replace("$HOME", str(HOME))
    except OSError:
        pass
    return {key: Path(configured.get(xdg, HOME / folder)) for key, (xdg, folder) in names.items()}


def appimage_type(path):
    """1 or 2 for an AppImage (ELF magic \x7fELF + AI + Type 1/2), else 0."""
    try:
        with open(path, "rb") as file:
            head = file.read(11)
        if head[:4] == b"\x7fELF" and head[8:10] == b"AI" and head[10] in (1, 2):
            return head[10]
    except OSError:
        pass
    return 0


def is_appimage(path):
    """Whether a path is an AppImage file, checking extension or binary header."""
    try:
        if not path.is_file() or path.is_symlink():
            return False
        if path.name.lower().endswith(".appimage"):
            return True
        return appimage_type(path) != 0
    except OSError:
        return False


def appimages():
    """The AppImage files in Home: those the launcher starts, standard folders (~/AppImages, ~/Applications, etc.), and any in Home."""
    found = set()

    # 1. Launcher desktop entries across user, system, and flatpak locations
    desktop_dirs = [
        APPLICATIONS,
        Path("/usr/share/applications"),
        Path("/usr/local/share/applications"),
    ]
    try:
        desktop_dirs.extend(HOME.glob(".var/app/*/data/applications"))
    except OSError:
        pass

    for folder in desktop_dirs:
        if not folder.exists():
            continue
        try:
            entries = folder.glob("*.desktop")
        except OSError:
            continue
        for entry in entries:
            try:
                lines = entry.read_text(errors="ignore").splitlines()
            except OSError:
                continue
            for line in lines:
                line = line.strip()
                for prefix in ("X-Mainstream-AppImage=", "X-Gearlever-Location=", "X-AppImage-Old-Exec=", "Exec=", "TryExec="):
                    if line.startswith(prefix):
                        val = line[len(prefix):].strip()
                        try:
                            words = shlex.split(val)
                        except ValueError:
                            words = val.split()
                        for word in words:
                            word = word.strip("\"'")
                            if word.startswith("/") or word.startswith("~"):
                                candidate = Path(os.path.expanduser(word))
                                if candidate.is_relative_to(HOME) and is_appimage(candidate):
                                    found.add(candidate)

    # 2. Designated and common AppImage folders (including ~/AppImages)
    for folder in APPIMAGE_DIRS:
        if not folder.exists():
            continue
        for where, dirs, names in os.walk(folder):
            try:
                rel = Path(where).relative_to(folder)
                if len(rel.parts) > 3:
                    dirs.clear()
                    continue
            except ValueError:
                pass
            for name in names:
                candidate = Path(where, name)
                if is_appimage(candidate):
                    found.add(candidate)

    # 3. Fast depth-limited search across Home for any *.appimage outside cache/trash/git
    try:
        home_str = str(HOME)
        output = run("find", home_str, "-maxdepth", "4",
                     "(", "-path", f"{home_str}/.cache", "-o",
                          "-path", f"{home_str}/.local/share/Trash", "-o",
                          "-path", f"{home_str}/.git", ")", "-prune",
                     "-o", "-type", "f", "-iname", "*.appimage", "-print")
        for line in output.splitlines():
            line = line.strip()
            if line:
                candidate = Path(line)
                if candidate.is_relative_to(HOME) and is_appimage(candidate):
                    found.add(candidate)
    except Exception:
        pass

    return sorted(path for path in found if path.is_relative_to(HOME) and path.is_file() and not path.is_symlink())


def usage():
    """What fills the disk. Home is measured once, a few levels deep, and read from for its parts."""
    home = du(HOME, depth=3)
    folders = user_folders()
    parts = {key: [path] for key, path in folders.items()}
    parts["games"] = [DATA / "Steam", HOME / ".steam/steam", HOME / "Games"]
    parts["cache"] = [CACHE]
    parts["trash"] = [TRASH]
    parts["flatpak"] = [DATA / "flatpak"]
    # Each folder is counted once. A symlink such as ~/.steam/steam would count what its target
    # already did, a folder set to Home itself is how a user folder is turned off, and a folder
    # named twice or inside another's counts only where it is named first or most closely.
    counted = []
    for key, paths in parts.items():
        for path in paths:
            if (not path.is_symlink() and str(path) in home and path.is_relative_to(HOME) and path != HOME
                    and all(path != other for other, _ in counted)):
                counted.append((path, key))
    sizes = {key: 0 for key in parts}
    for path, key in counted:
        inside = [other for other, _ in counted if other != path and other.is_relative_to(path)]
        nearest = [other for other in inside if not any(other != mid and other.is_relative_to(mid) for mid in inside)]
        sizes[key] += max(0, home[str(path)] - sum(home[str(other)] for other in nearest))
    # An AppImage is one file, so it moves from the part that holds it to a part of its own.
    sizes["appimages"] = 0
    kept = []
    for image in appimages():
        try:
            size = image.stat().st_blocks * 512
        except OSError:
            continue
        holders = [(path, key) for path, key in counted if image.is_relative_to(path)]
        if holders:
            key = max(holders, key=lambda holder: len(holder[0].parts))[1]
            sizes[key] = max(0, sizes[key] - size)
        sizes["appimages"] += size
        kept.append(image)
    folder = Counter(image.parent for image in kept).most_common(1)
    appimage_home_dir = HOME / "AppImages"
    if any(image.is_relative_to(appimage_home_dir) for image in kept):
        parts["appimages"] = [appimage_home_dir]
    else:
        default_dir = appimage_home_dir if appimage_home_dir.exists() else (HOME / "Applications" if (HOME / "Applications").exists() else HOME)
        parts["appimages"] = [folder[0][0]] if folder else [default_dir]
    sizes["otherHome"] = max(0, home.get(str(HOME), 0) - sum(sizes.values()))
    home_device = device_of(HOME)
    for key, size in sizes.items():
        paths = parts.get(key, [HOME])
        path = next((path for path in paths if path.exists()), paths[0])
        yield {"kind": "usage", "id": key, "size": size, "path": str(path), "device": home_device}
    system = du("/usr", "/opt", "/var/lib/flatpak")
    yield {"kind": "usage", "id": "apps", "size": system.get("/usr", 0) + system.get("/opt", 0), "path": "",
           "device": device_of("/usr")}
    # Flatpak's system apps usually sit beside the user's, and a split /home splits them too.
    yield {"kind": "usage", "id": "flatpakSystem", "size": system.get("/var/lib/flatpak", 0), "path": "",
           "device": device_of("/var/lib/flatpak")}


def orphans():
    return run("pacman", "-Qdttq").split()


def unused_flatpaks():
    if not shutil.which("flatpak"):
        return []
    try:
        output = subprocess.run(["flatpak", "uninstall", "--unused"], input="n\n", capture_output=True, text=True, env=ENV).stdout
    except OSError:
        return []
    return re.findall(r"^\s*\d+\.\s+(\S+)", output, re.M)


def cleanups():
    yield {"kind": "clean", "id": "trash", "size": size_of([TRASH]), "items": []}
    match = re.search(r"disk space saved: ([\d.]+ \w+)", run("paccache", "-dk1"))
    yield {"kind": "clean", "id": "packages", "size": parse_size(match[1]) if match else 0, "items": []}
    yield {"kind": "clean", "id": "toolCaches", "size": size_of(TOOL_CACHES), "items": []}
    yield {"kind": "clean", "id": "thumbnails", "size": size_of(THUMBNAILS), "items": []}
    match = re.search(r"take up ([\d.]+\s*\w+)", run("journalctl", "--disk-usage"))
    journal = parse_size(match[1]) if match else 0
    yield {"kind": "clean", "id": "logs", "size": max(0, journal - KEPT_JOURNAL), "items": []}
    yield {"kind": "clean", "id": "coredumps", "size": size_of([COREDUMPS]), "items": []}
    names = orphans()
    size = 0
    if names:
        for line in run("pacman", "-Qi", *names).splitlines():
            if line.startswith("Installed Size"):
                size += parse_size(line.split(":", 1)[1])
    yield {"kind": "clean", "id": "orphans", "size": size, "items": names}
    yield {"kind": "clean", "id": "flatpaks", "size": 0, "items": unused_flatpaks()}


def scan():
    def emit(entry):
        print(json.dumps(entry), flush=True)

    for disk in disks():
        emit(disk)
    efi = efi_info()
    if efi:
        emit(efi)
    try:
        for line in LAST_SCAN.read_text().splitlines():
            print(line, flush=True)
    except OSError:
        pass
    emit({"kind": "cached"})
    fresh = []
    for source in (usage, cleanups):
        for entry in source():
            fresh.append(entry)
            emit(entry)
    LAST_SCAN.parent.mkdir(parents=True, exist_ok=True)
    tmp = LAST_SCAN.with_suffix(".tmp")
    tmp.write_text("".join(json.dumps(entry) + "\n" for entry in fresh))
    tmp.replace(LAST_SCAN)


def inside_home(path):
    resolved = Path(path).absolute()
    return resolved if resolved.is_relative_to(HOME) and ".." not in resolved.parts else None


def list_folder(path):
    folder = inside_home(path)
    if folder is None or not folder.is_dir():
        sys.exit("That folder is not inside Home.")
    sizes = du(folder, depth=1, every_file=True)
    entries = []
    for entry, size in sizes.items():
        item = Path(entry)
        if item == folder:
            continue
        entries.append({"name": item.name, "path": entry, "size": size,
                        "folder": item.is_dir() and not item.is_symlink(), "protected": is_protected(item)})
    entries.sort(key=lambda entry: entry["size"], reverse=True)
    print(json.dumps({"path": str(folder), "size": sizes.get(str(folder), 0), "entries": entries}))


def is_protected(path):
    """Home's hidden folders hold what apps need to run, and Home's own folders are expected to be there."""
    return path == HOME or (path.parent == HOME and (path.name.startswith(".") or path in user_folders().values()))


def large():
    output = run("find", str(HOME), "-xdev", "(", "-name", ".*", "-prune", ")", "-o", "-type", "f",
                 "-size", f"+{LARGEST_FILE_MIN}c", "-printf", "%b\t%p\n")
    files = []
    for line in output.splitlines():
        blocks, _, path = line.partition("\t")
        if blocks.isdigit():
            files.append({"name": os.path.basename(path), "path": path, "size": int(blocks) * 512,
                          "folder": False, "protected": False})
    files.sort(key=lambda entry: entry["size"], reverse=True)
    print(json.dumps({"entries": files[:LARGEST_FILES]}))


def remove_all(paths):
    for path in paths:
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path, ignore_errors=True)


def exec_or_fail(*command):
    if not shutil.which(command[1] if command[0] == "pkexec" else command[0]):
        sys.exit(f"{command[1] if command[0] == 'pkexec' else command[0]} is not installed.")
    os.execvp(command[0], command)


def empty_trash():
    remove_all([TRASH / "files", TRASH / "info"])
    (TRASH / "directorysizes").unlink(missing_ok=True)
    for folder in ("files", "info"):
        (TRASH / folder).mkdir(parents=True, exist_ok=True)


def clean(action):
    if action == "trash":
        empty_trash()
    elif action == "packages":
        exec_or_fail("pkexec", "paccache", "-rk1")
    elif action == "toolCaches":
        remove_all(TOOL_CACHES)
    elif action == "thumbnails":
        remove_all(THUMBNAILS)
    elif action == "logs":
        exec_or_fail("pkexec", "journalctl", f"--vacuum-size={KEPT_JOURNAL}")
    elif action == "coredumps":
        exec_or_fail("pkexec", "find", str(COREDUMPS), "-type", "f", "-delete")
    elif action == "orphans":
        names = orphans()
        if names:
            exec_or_fail("pkexec", "pacman", "-Rns", "--noconfirm", "--", *names)
    elif action == "flatpaks":
        exec_or_fail("flatpak", "uninstall", "--unused", "--noninteractive")
    else:
        sys.exit(f"Unknown cleanup: {action}")


def trash(path):
    item = inside_home(path)
    if item is None or not os.path.lexists(item) or is_protected(item):
        sys.exit("That can't be moved to the Trash from here.")
    exec_or_fail("gio", "trash", "--", str(item))


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "scan":
        scan()
    elif command == "large":
        large()
    elif command == "list" and len(sys.argv) == 3:
        list_folder(sys.argv[2])
    elif command == "clean" and len(sys.argv) == 3:
        clean(sys.argv[2])
    elif command == "trash" and len(sys.argv) == 3:
        trash(sys.argv[2])
    elif command == "efi":
        print(json.dumps(efi_info()))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
