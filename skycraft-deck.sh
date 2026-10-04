#!/usr/bin/env bash
# SkyCraft for Steam Deck (https://github.com/chasesfloorboard/SkyCraft-Deck): installs SkyCraft (https://github.com/chasmlol/SkyCraft) into Steam's
# Skyrim Special Edition and its Proton prefix. Run it in Desktop Mode, from Konsole.
#
#   ./skycraft-deck.sh install     install or update everything (the default)
#   ./skycraft-deck.sh signin      open SkyCraft's Prism Launcher to sign in to Minecraft
#   ./skycraft-deck.sh status      show what's installed
#   ./skycraft-deck.sh logs        show the end of SkyCraft's and Minecraft's logs
#   ./skycraft-deck.sh uninstall   remove what this script installed (--purge: Minecraft too)
#
# Environment overrides: STEAM_ROOT (Steam's folder), DOWNLOADS (where Nexus downloads are),
# SKYCRAFT_ZIP (a local SkyCraft-<version>.zip instead of the latest GitHub release).

set -euo pipefail

APPID=489830
SKYCRAFT_REPO=chasmlol/SkyCraft
TESTED_VERSION=1.7.104
DOWNLOADS=${DOWNLOADS:-$HOME/Downloads}

# ---------------------------------------------------------------------------------------------
# Output

if [[ -t 1 ]]; then
	B=$'\e[1m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' N=$'\e[0m'
else
	B='' G='' Y='' R='' N=''
fi
say()  { printf '%s\n' "$*"; }
step() { printf '\n%s==> %s%s\n' "$B" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '\n%sError:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "this needs '$1', which isn't installed"; }

# ---------------------------------------------------------------------------------------------
# Finding Steam, Skyrim and its Proton prefix

find_steam_root() {
	local candidate
	for candidate in "${STEAM_ROOT:-}" "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root" \
		"$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
		if [[ -n $candidate && -f $candidate/steamapps/libraryfolders.vdf ]]; then
			STEAM_ROOT=$(cd "$candidate" && pwd -P)
			return
		fi
	done
	die "couldn't find Steam (set STEAM_ROOT to Steam's folder)"
}

# Every Steam library folder (internal storage, SD card, ...).
steam_libraries() {
	printf '%s\n' "$STEAM_ROOT"
	sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$STEAM_ROOT/steamapps/libraryfolders.vdf"
}

find_skyrim() {
	find_steam_root
	local lib manifest installdir
	while IFS= read -r lib; do
		manifest=$lib/steamapps/appmanifest_$APPID.acf
		[[ -f $manifest ]] || continue
		installdir=$(sed -n 's/^[[:space:]]*"installdir"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$manifest")
		GAME=$lib/steamapps/common/${installdir:-Skyrim Special Edition}
		COMPAT=$lib/steamapps/compatdata/$APPID
		LIBRARY=$lib
		[[ -f $GAME/SkyrimSE.exe ]] || die "Skyrim's Steam files are incomplete ($GAME has no SkyrimSE.exe). Let Steam finish installing it."
		PFX=$COMPAT/pfx
		USERDIR=$PFX/drive_c/users/steamuser
		LOCALAPPDATA=$USERDIR/AppData/Local
		MANIFEST=$GAME/.skycraft-deck/installed-files
		return
	done < <(steam_libraries | awk '!seen[$0]++')
	die "Skyrim Special Edition isn't installed in Steam (app $APPID). Install it first."
}

need_prefix() {
	[[ -d $USERDIR ]] || die "Skyrim's Proton prefix doesn't exist yet. Start Skyrim once from Steam, wait for its main menu, quit, then run this again."
}

# File version of a Windows .exe/.dll (from its VS_FIXEDFILEINFO), as major.minor.build.
pe_version() {
	python3 - "$1" <<'EOF'
import struct, sys
data = open(sys.argv[1], "rb").read()
at = data.find(b"\xbd\x04\xef\xfe")
if at < 0:
    sys.exit(1)
ms, ls = struct.unpack_from("<II", data, at + 8)
print(f"{ms >> 16}.{ms & 0xFFFF}.{ls >> 16}")
EOF
}

# ---------------------------------------------------------------------------------------------
# Archives

extract() {
	local archive=$1 into=$2
	mkdir -p "$into"
	if command -v bsdtar >/dev/null 2>&1; then
		bsdtar -xf "$archive" -C "$into"
	elif command -v 7z >/dev/null 2>&1; then
		7z x -y -o"$into" "$archive" >/dev/null
	elif [[ $archive == *.zip ]] && command -v unzip >/dev/null 2>&1; then
		unzip -qo "$archive" -d "$into"
	else
		die "can't unpack $(basename "$archive"): no bsdtar, 7z or unzip"
	fi
}

# The folder inside an unpacked mod archive that corresponds to Skyrim's Data folder.
data_root() {
	local dir=$1 entries
	while :; do
		local data
		data=$(find "$dir" -mindepth 1 -maxdepth 1 -type d -iname data -print -quit)
		if [[ -n $data ]]; then
			printf '%s\n' "$data"
			return
		fi
		if [[ -n $(find "$dir" -mindepth 1 -maxdepth 1 \( -iname skse -o -iname '*.esp' -o -iname '*.esm' -o -iname '*.esl' -o -iname '*.bsa' -o -iname scripts -o -iname meshes -o -iname textures \) -print -quit) ]]; then
			printf '%s\n' "$dir"
			return
		fi
		mapfile -t entries < <(find "$dir" -mindepth 1 -maxdepth 1)
		if [[ ${#entries[@]} -eq 1 && -d ${entries[0]} ]]; then
			dir=${entries[0]}
		else
			printf '%s\n' "$dir"
			return
		fi
	done
}

# Copies a folder's files into another, merging folder names case-insensitively the way Windows
# would (so an archive's "skse/plugins" lands in an existing "SKSE/Plugins" rather than beside it;
# Proton would only see one of the two). Records each file, relative to $GAME, in $MANIFEST.
# Prints the plugin files (.esp/.esm/.esl) it copied to the top level.
install_tree() {
	mkdir -p "$(dirname "$MANIFEST")"
	python3 - "$1" "$2" "$GAME" "$MANIFEST" <<'EOF'
import os, shutil, sys
src, dst, game, manifest = sys.argv[1:5]

def resolve(base, rel):
    cur = base
    for part in rel.split(os.sep):
        exact = os.path.join(cur, part)
        if not os.path.exists(exact) and os.path.isdir(cur):
            match = next((e for e in os.listdir(cur) if e.lower() == part.lower()), None)
            if match:
                exact = os.path.join(cur, match)
        cur = exact
    return cur

recorded = set()
if os.path.exists(manifest):
    recorded = set(open(manifest).read().splitlines())
added = []
for root, _, files in os.walk(src):
    for name in files:
        rel = os.path.relpath(os.path.join(root, name), src)
        target = resolve(dst, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(os.path.join(root, name), target)
        entry = os.path.relpath(target, game)
        if entry not in recorded:
            recorded.add(entry)
            added.append(entry)
        if os.sep not in rel and name.lower().endswith((".esp", ".esm", ".esl")):
            print(name)
with open(manifest, "a") as out:
    out.writelines(e + "\n" for e in added)
EOF
}

# Newest file in $DOWNLOADS matching any of the given name patterns.
newest_download() {
	local pattern found=() IFS=
	shopt -s nullglob nocaseglob
	for pattern in "$@"; do
		found+=("$DOWNLOADS"/$pattern)
	done
	shopt -u nullglob nocaseglob
	[[ ${#found[@]} -gt 0 ]] || return 1
	ls -1t -- "${found[@]}" | head -n1
}

# Turns a plugin on in Skyrim's Plugins.txt, and remembers it for uninstall.
enable_plugin() {
	local dir=$LOCALAPPDATA/Skyrim\ Special\ Edition
	mkdir -p "$GAME/.skycraft-deck"
	mkdir -p "$dir"
	python3 - "$dir/Plugins.txt" "$1" <<'PY'
import os, sys
path, name = sys.argv[1:3]
text = open(path, encoding="utf-8", errors="surrogateescape", newline="").read() if os.path.exists(path) else ""
eol = "\r\n" if "\r\n" in text else "\n"
lines = text.splitlines()
for i, line in enumerate(lines):
    if line.lstrip("*").strip().lower() == name.lower():
        lines[i] = "*" + name
        break
else:
    lines.append("*" + name)
open(path, "w", encoding="utf-8", errors="surrogateescape", newline="").write(eol.join(lines) + eol)
PY
	grep -qxF "$1" "$GAME/.skycraft-deck/plugins" 2>/dev/null || printf '%s\n' "$1" >>"$GAME/.skycraft-deck/plugins"
}

# ---------------------------------------------------------------------------------------------
# install

# SkyCraft.dll and Prism are built with a current Visual Studio and need its C++ runtime (14.40 or
# newer); with older ones they crash on their first mutex. Windows PCs have it from Windows Update,
# but Skyrim's Steam install only puts the 2015 runtime (14.0) in its Proton prefix. Install
# Microsoft's current one there.
install_vcredist() {
	step "Microsoft Visual C++ runtime"
	local dll=$PFX/drive_c/windows/system32/msvcp140.dll have minor
	have=$(pe_version "$dll" 2>/dev/null || echo 0.0.0)
	minor=$(cut -d. -f2 <<<"$have")
	if [[ ${have%%.*} == 14 && $minor -ge 40 ]]; then
		ok "version $have"
		return
	fi
	need_prefix_idle
	local cache=${XDG_CACHE_HOME:-$HOME/.cache}/skycraft-deck
	mkdir -p "$cache"
	say "  Skyrim's prefix has version $have; SkyCraft needs 14.40 or newer. Downloading Microsoft's..."
	curl -fL --progress-bar -o "$cache/vc_redist.x64.exe" https://aka.ms/vc14/vc_redist.x64.exe ||
		curl -fL --progress-bar -o "$cache/vc_redist.x64.exe" https://aka.ms/vs/17/release/vc_redist.x64.exe ||
		die "couldn't download the Visual C++ runtime from Microsoft"
	say "  installing it into Skyrim's prefix (a minute)"
	run_in_prefix "$cache/vc_redist.x64.exe" /install /quiet /norestart >/dev/null 2>&1 || true
	have=$(pe_version "$dll" 2>/dev/null || echo 0.0.0)
	minor=$(cut -d. -f2 <<<"$have")
	[[ ${have%%.*} == 14 && $minor -ge 40 ]] || die "installing the Visual C++ runtime didn't work (msvcp140 is still $have)"
	ok "version $have"
}

# Wine rewrites user.reg when the prefix's wineserver exits, so nothing may be running in it while
# we change it. Its working folder is /tmp/.wine-<uid>/server-<device>-<inode of the prefix>.
need_prefix_idle() {
	local server pid
	server=$(stat -c '%d %i' "$PFX" | awk '{printf "server-%x-%x", $1, $2}')
	for pid in $(pgrep -x wineserver 2>/dev/null); do
		if [[ $(readlink "/proc/$pid/cwd" 2>/dev/null) == */"$server" ]]; then
			die "Skyrim (or something else in its Proton prefix) is running. Quit it, then run this again."
		fi
	done
}

install_skse() {
	step "SKSE64"
	local archive have=''
	[[ -f $GAME/skse64_loader.exe ]] && have=1
	if ! archive=$(newest_download 'skse64_2_*.7z' '*Skyrim Script Extender*.7z' '*[- ]30379[- ]*.7z' '*[- ]30379[- ]*.zip'); then
		if [[ -n $have ]]; then
			ok "already installed"
			return
		fi
		die "SKSE64 isn't in $DOWNLOADS.
  Download the Anniversary Edition build (for game version $SKYRIM_VERSION) from
    https://www.nexusmods.com/skyrimspecialedition/mods/30379?tab=files
  (Manual Download), leave it in $DOWNLOADS, and run this again."
	fi
	[[ $(basename "$archive") == *gog* ]] && die "$(basename "$archive") is the GOG build of SKSE; Steam's Skyrim needs the Steam (Anniversary Edition) build"
	local tmp
	tmp=$(mktemp -d)
	extract "$archive" "$tmp"
	local loader
	loader=$(find "$tmp" -iname skse64_loader.exe -print -quit)
	[[ -n $loader ]] || die "$(basename "$archive") doesn't look like SKSE64 (no skse64_loader.exe in it)"
	local top
	top=$(dirname "$loader")
	mkdir -p "$tmp/.game"
	find "$top" -maxdepth 1 -type f \( -iname '*.exe' -o -iname '*.dll' \) -exec cp -t "$tmp/.game" {} +
	install_tree "$tmp/.game" "$GAME" >/dev/null
	local data
	data=$(find "$top" -mindepth 1 -maxdepth 1 -type d -iname data -print -quit)
	[[ -n $data ]] && install_tree "$data" "$GAME/Data" >/dev/null
	rm -rf "$tmp"
	ok "installed from $(basename "$archive")"
	local dll="skse64_${SKYRIM_VERSION//./_}.dll"
	if [[ ! -f $GAME/$dll ]]; then
		warn "this SKSE has no $dll, so it doesn't support your Skyrim ($SKYRIM_VERSION). Get the SKSE build for $SKYRIM_VERSION."
	fi
}

install_address_library() {
	step "Address Library for SKSE Plugins"
	local archive
	if ! archive=$(newest_download '*Address Library*' '*All in one (Anniversary Edition)*' '*[- ]32444[- ]*'); then
		if compgen -G "$GAME/Data/SKSE/Plugins/versionlib-*.bin" >/dev/null; then
			ok "already installed"
			return
		fi
		die "Address Library isn't in $DOWNLOADS.
  Download \"All in one (Anniversary Edition)\" from
    https://www.nexusmods.com/skyrimspecialedition/mods/32444?tab=files
  (Manual Download), leave it in $DOWNLOADS, and run this again."
	fi
	local tmp
	tmp=$(mktemp -d)
	extract "$archive" "$tmp"
	install_tree "$(data_root "$tmp")" "$GAME/Data" >/dev/null
	rm -rf "$tmp"
	compgen -G "$GAME/Data/SKSE/Plugins/versionlib-${SKYRIM_VERSION//./-}-*.bin" >/dev/null ||
		warn "it has no versionlib for $SKYRIM_VERSION; make sure it's the Anniversary Edition file, and up to date"
	ok "installed from $(basename "$archive")"
}

install_alternate_start() {
	step "Alternate Start - Live Another Life (optional, recommended)"
	local archive
	if ! archive=$(newest_download '*Alternate Start*' '*-272-*' '* 272 [0-9]*'); then
		warn "not in $DOWNLOADS, skipped. Skyrim's opening (cart ride, Helgen) may leave you stuck with"
		warn "SkyCraft; get it from https://www.nexusmods.com/skyrimspecialedition/mods/272 or play from a save after Helgen."
		return
	fi
	local tmp plugin
	tmp=$(mktemp -d)
	extract "$archive" "$tmp"
	while IFS= read -r plugin; do
		[[ -n $plugin ]] && enable_plugin "$plugin"
	done < <(install_tree "$(data_root "$tmp")" "$GAME/Data")
	rm -rf "$tmp"
	ok "installed and enabled from $(basename "$archive")"
}

install_skycraft() {
	step "SkyCraft"
	local tmp zip
	tmp=$(mktemp -d)
	if [[ -n ${SKYCRAFT_ZIP:-} ]]; then
		zip=$SKYCRAFT_ZIP
		[[ -f $zip ]] || die "SKYCRAFT_ZIP: $zip doesn't exist"
	else
		local url
		url=$(curl -fsSL "https://api.github.com/repos/$SKYCRAFT_REPO/releases/latest" | python3 -c '
import json, re, sys
for asset in json.load(sys.stdin)["assets"]:
    if re.fullmatch(r"SkyCraft-[0-9.]+\.zip", asset["name"]):
        print(asset["browser_download_url"])
        break
') || die "couldn't ask GitHub for SkyCraft's latest release"
		[[ -n $url ]] || die "SkyCraft's latest release has no SkyCraft-<version>.zip"
		zip=$tmp/$(basename "$url")
		say "  downloading $(basename "$url")"
		curl -fL --progress-bar -o "$zip" "$url" || die "couldn't download $url"
	fi
	extract "$zip" "$tmp/mod"
	local root ini existing_ini=''
	root=$(data_root "$tmp/mod")
	[[ -f $root/SKSE/Plugins/SkyCraft.dll ]] || die "$(basename "$zip") doesn't look like SkyCraft (no SKSE/Plugins/SkyCraft.dll)"
	ini=$GAME/Data/SKSE/Plugins/SkyCraft.ini
	# Keep the player's own settings across updates.
	if [[ -f $ini ]]; then
		existing_ini=$tmp/SkyCraft.ini
		cp "$ini" "$existing_ini"
	fi
	install_tree "$root" "$GAME/Data" >/dev/null
	[[ -n $existing_ini ]] && cp "$existing_ini" "$ini"
	SKYCRAFT_VERSION=$(basename "$zip" .zip)
	ok "installed ${SKYCRAFT_VERSION}"

	# SkyCraft unpacks its Minecraft (a portable Prism Launcher) with Windows' tar.exe, which Proton
	# doesn't have. Unpack it here instead, where SkyCraft would, and point SkyCraft.ini straight at
	# that Prism so SkyCraft starts it without unpacking anything.
	step "SkyCraft's Minecraft (Prism Launcher)"
	local bundle dir=$LOCALAPPDATA/SkyCraft
	bundle=$(find "$GAME/Data/SKSE/Plugins" -maxdepth 2 -iname SkyCraft-Minecraft.zip -print -quit)
	[[ -n $bundle ]] || die "SkyCraft-Minecraft.zip is missing from Data/SKSE/Plugins/SkyCraft"
	mkdir -p "$dir"
	find "$dir/Prism/instances/SkyCraft/.minecraft/mods" -maxdepth 1 -type f \
		\( -name 'skycraft-*' -o -name 'fabric-api-*' -o -name 'e4mc-*' \) -delete 2>/dev/null || true
	extract "$bundle" "$dir"
	[[ -f $dir/Prism/prismlauncher.exe ]] || die "unpacking SkyCraft-Minecraft.zip didn't give a Prism Launcher"
	if [[ ! -f $dir/Prism/prismlauncher.cfg ]]; then
		cp "$dir/defaults/prismlauncher.cfg" "$dir/Prism/prismlauncher.cfg"
	elif ! grep -q '^LowMemWarning=' "$dir/Prism/prismlauncher.cfg"; then
		sed -i '0,/^\[General\]/s//[General]\nLowMemWarning=false/' "$dir/Prism/prismlauncher.cfg"
	fi
	python3 - "$ini" <<'EOF'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
value = r"sLauncher = %LOCALAPPDATA%\SkyCraft\Prism\prismlauncher.exe"
if re.search(r"(?m)^\s*sLauncher\s*=.*$", text):
    text = re.sub(r"(?m)^\s*sLauncher\s*=.*$", lambda m: value, text, count=1)
elif "[Minecraft]" in text:
    text = text.replace("[Minecraft]", "[Minecraft]\n" + value, 1)
else:
    text += "\n[Minecraft]\n" + value + "\n"
open(path, "w", encoding="utf-8").write(text)
EOF
	ok "unpacked to the Proton prefix (C:\\users\\steamuser\\AppData\\Local\\SkyCraft)"
	use_wine_vcruntime_for_prism
	if [[ -f $dir/Prism/accounts.json ]] && grep -q '"type"' "$dir/Prism/accounts.json"; then
		ok "a Microsoft account is signed in"
	else
		warn "no Minecraft account signed in yet: run  ./skycraft-deck.sh signin  next"
	fi
	rm -rf "$tmp"
}

# Prism also gets Wine's own C++ runtime (14.42), so it starts even if the prefix's runtime is
# rolled back (Steam re-running Skyrim's 2015 installer, say). Only Prism's programs are affected.
use_wine_vcruntime_for_prism() {
	need_prefix_idle
	python3 - "$PFX/user.reg" <<'PY'
import sys, time
path = sys.argv[1]
text = open(path, encoding="utf-8", errors="surrogateescape", newline="").read()
dlls = ["concrt140", "msvcp140", "msvcp140_1", "msvcp140_2", "msvcp140_atomic_wait", "vcruntime140", "vcruntime140_1"]
body = "".join('"%s"="builtin"\n' % d for d in dlls)
for exe in ["prismlauncher.exe", "prismlauncher_filelink.exe", "prismlauncher_updater.exe"]:
    header = "[Software\\\\Wine\\\\AppDefaults\\\\" + exe + "\\\\DllOverrides]"
    section = header + " %d\n" % time.time() + body
    at = text.find(header)
    if at >= 0:
        end = text.find("\n\n", at)
        end = len(text) if end < 0 else end + 1
        text = text[:at] + section + text[end:]
    else:
        text = text.rstrip("\n") + "\n\n" + section
open(path, "w", encoding="utf-8", errors="surrogateescape", newline="").write(text)
PY
	ok "Prism uses Wine's Visual C++ runtime (Skyrim's 2015 one crashes it)"
}

# Steam starts SkyrimSELauncher.exe; swap SKSE's loader in, so Skyrim starts with SKSE in Game Mode.
install_loader() {
	step "Start Skyrim through SKSE"
	local launcher=$GAME/SkyrimSELauncher.exe backup=$GAME/SkyrimSELauncher.exe.skycraft-backup
	if [[ ! -f $backup ]]; then
		[[ -f $launcher ]] && cp -p "$launcher" "$backup"
	fi
	cp "$GAME/skse64_loader.exe" "$launcher"
	ok "Steam's Play button now starts skse64_loader.exe (Bethesda's launcher saved as SkyrimSELauncher.exe.skycraft-backup)"
	say "  If a Steam update or \"Verify integrity\" puts the launcher back, run this script again."
}

cmd_install() {
	need python3
	need curl
	find_skyrim
	step "Skyrim Special Edition"
	say "  $GAME"
	SKYRIM_VERSION=$(pe_version "$GAME/SkyrimSE.exe") || die "couldn't read SkyrimSE.exe's version"
	case $SKYRIM_VERSION in
		1.6.* | 1.7.*) ok "version $SKYRIM_VERSION" ;;
		*) die "Skyrim $SKYRIM_VERSION isn't supported; SkyCraft needs the Anniversary Edition runtime (1.6.x / 1.7.x)" ;;
	esac
	[[ $SKYRIM_VERSION == "$TESTED_VERSION" ]] ||
		warn "SkyCraft is developed on $TESTED_VERSION; $SKYRIM_VERSION needs matching SKSE and Address Library builds"
	need_prefix
	ok "Proton prefix: $PFX"

	install_vcredist
	install_skse
	install_address_library
	install_alternate_start
	install_skycraft
	install_loader

	step "Done"
	cat <<EOF
  Next:
   1. Sign in to Minecraft once (Desktop Mode):   ./skycraft-deck.sh signin
   2. Set up controls: SkyCraft uses keyboard and mouse. Give Skyrim a keyboard-and-mouse
      Steam Input layout; see https://github.com/chasesfloorboard/SkyCraft-Deck/blob/main/docs/controls.md
   3. Start Skyrim from Steam. The first start, Prism downloads Minecraft 26.3 and Java
      (a few minutes); Skyrim's corner messages say when Minecraft is ready.

  Problems? ./skycraft-deck.sh logs
EOF
}

# ---------------------------------------------------------------------------------------------
# signin: run SkyCraft's Prism in Skyrim's prefix, with the Proton Skyrim uses

find_proton() {
	local want='' lib dir candidates=()
	[[ -f $COMPAT/version ]] && want=$(<"$COMPAT/version")
	while IFS= read -r lib; do
		for dir in "$lib"/steamapps/common/Proton*/; do
			[[ -x $dir/proton ]] && candidates+=("${dir%/}")
		done
	done < <(steam_libraries | awk '!seen[$0]++')
	for dir in "$STEAM_ROOT"/compatibilitytools.d/*/; do
		[[ -x $dir/proton ]] && candidates+=("${dir%/}")
	done
	[[ ${#candidates[@]} -gt 0 ]] || die "no Proton found in Steam. Start Skyrim once from Steam first."
	# The Proton that last ran the prefix, from the version it stamps there: GE-Proton stamps its
	# own name ("GE-Proton11-7"), Valve's Protons their Wine version ("11.0-100").
	local tag
	for dir in "${candidates[@]}"; do
		tag=$(awk '{print $2}' "$dir/version" 2>/dev/null)
		if [[ -n $want && $tag == "$want" ]]; then
			PROTON=$dir
			return
		fi
	done
	local major=${want%%-*}
	for dir in "${candidates[@]}"; do
		tag=$(awk '{print $2}' "$dir/version" 2>/dev/null)
		if [[ $major == [0-9]*.[0-9]* && $(basename "$dir") == "Proton - Experimental" && $tag == *"-$major-"* ]]; then
			PROTON=$dir
			return
		fi
	done
	for dir in "${candidates[@]}"; do
		if [[ $major == [0-9]*.[0-9]* && $(basename "$dir") == "Proton $major"* ]]; then
			PROTON=$dir
			return
		fi
	done
	PROTON=$(printf '%s\n' "${candidates[@]}" | sort -V | tail -n1)
}

# Runs a Windows program in Skyrim's prefix with Skyrim's Proton, the way Steam would, and waits.
run_in_prefix() {
	[[ -n ${PROTON:-} ]] || find_proton
	# Proton runs inside the Steam Linux Runtime its toolmanifest.vdf names, as under Steam: Wine's
	# HTTPS (Prism's sign-in and downloads) uses that runtime's GnuTLS and fails in the wrong one.
	local runtime='' tool lib dir
	tool=$(sed -n 's/^[[:space:]]*"require_tool_appid"[[:space:]]*"\([0-9]*\)".*/\1/p' "$PROTON/toolmanifest.vdf" 2>/dev/null)
	if [[ -n $tool ]]; then
		while IFS= read -r lib; do
			[[ -f $lib/steamapps/appmanifest_$tool.acf ]] || continue
			dir=$(sed -n 's/^[[:space:]]*"installdir"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$lib/steamapps/appmanifest_$tool.acf")
			[[ -x $lib/steamapps/common/$dir/_v2-entry-point ]] && runtime=$lib/steamapps/common/$dir/_v2-entry-point && break
		done < <(steam_libraries | awk '!seen[$0]++')
		[[ -n $runtime ]] || die "$(basename "$PROTON") needs Steam Linux Runtime (app $tool), which isn't installed. Start Skyrim once from Steam (it installs it), then run this again."
	fi
	export STEAM_COMPAT_DATA_PATH=$COMPAT STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM_ROOT \
		STEAM_COMPAT_INSTALL_PATH=$GAME SteamAppId=$APPID SteamGameId=$APPID
	if [[ -n $runtime ]]; then
		"$runtime" --verb=waitforexitandrun -- "$PROTON/proton" waitforexitandrun "$@"
	else
		"$PROTON/proton" waitforexitandrun "$@"
	fi
}

cmd_signin() {
	find_skyrim
	need_prefix
	local prism=$LOCALAPPDATA/SkyCraft/Prism/prismlauncher.exe
	[[ -f $prism ]] || die "SkyCraft's Prism Launcher isn't unpacked yet; run  ./skycraft-deck.sh install  first"
	[[ -n ${PROTON:-} ]] || find_proton
	step "Opening Prism Launcher with $(basename "$PROTON")"
	cat <<EOF
  In Prism: Accounts (top right) > Manage Accounts > Add Microsoft. Prism shows a code and
  a QR code: open the link on your phone (or any browser), enter the code and sign in. Then
  close Prism. Don't launch the SkyCraft instance from here: Skyrim starts it.
EOF
	run_in_prefix "$prism"
	if grep -qs '"type"' "$(dirname "$prism")/accounts.json"; then
		ok "signed in. Start Skyrim from Steam."
	else
		warn "Prism closed without a signed-in account"
	fi
}

# ---------------------------------------------------------------------------------------------
# status, logs, uninstall

cmd_status() {
	find_skyrim
	local v
	say "${B}Skyrim${N}         $GAME"
	v=$(pe_version "$GAME/SkyrimSE.exe" 2>/dev/null || echo '?')
	say "               version $v"
	say "${B}Proton prefix${N}  $PFX $([[ -d $USERDIR ]] || echo '(not created yet)')"
	[[ -f $COMPAT/version ]] && say "               made by Proton $(<"$COMPAT/version")"
	if [[ -f $GAME/skse64_loader.exe ]]; then
		say "${B}SKSE64${N}         $(pe_version "$GAME/skse64_loader.exe" 2>/dev/null || echo installed)$([[ -f $GAME/skse64_${v//./_}.dll ]] || echo "  (no skse64_${v//./_}.dll: wrong SKSE build for this Skyrim)")"
	else
		say "${B}SKSE64${N}         not installed"
	fi
	if cmp -s "$GAME/skse64_loader.exe" "$GAME/SkyrimSELauncher.exe" 2>/dev/null; then
		say "${B}Play button${N}    starts SKSE"
	else
		say "${B}Play button${N}    starts Bethesda's launcher (SKSE not swapped in: run install)"
	fi
	if compgen -G "$GAME/Data/SKSE/Plugins/versionlib-*.bin" >/dev/null; then
		say "${B}Address Lib${N}    installed"
	else
		say "${B}Address Lib${N}    not installed"
	fi
	if [[ -f $GAME/Data/SKSE/Plugins/SkyCraft.dll ]]; then
		say "${B}SkyCraft${N}       $(pe_version "$GAME/Data/SKSE/Plugins/SkyCraft.dll" 2>/dev/null || echo installed)"
	else
		say "${B}SkyCraft${N}       not installed"
	fi
	local prism=$LOCALAPPDATA/SkyCraft/Prism
	if [[ -f $prism/prismlauncher.exe ]]; then
		say "${B}Minecraft${N}      Prism unpacked; account: $(grep -qs '"type"' "$prism/accounts.json" && echo 'signed in' || echo 'not signed in')"
	else
		say "${B}Minecraft${N}      not unpacked"
	fi
}

cmd_logs() {
	find_skyrim
	local log
	for log in "$USERDIR/Documents/My Games/Skyrim Special Edition/SKSE/SkyCraft.log" \
		"$USERDIR/Documents/My Games/Skyrim Special Edition/SKSE/skse64.log" \
		"$LOCALAPPDATA/SkyCraft/Prism/instances/SkyCraft/.minecraft/logs/latest.log" \
		"$LOCALAPPDATA/SkyCraft/Prism/logs/PrismLauncher-0.log"; do
		step "$log"
		if [[ -f $log ]]; then
			tail -n 40 "$log"
		else
			say "  (none yet)"
		fi
	done
}

cmd_uninstall() {
	find_skyrim
	step "Removing SkyCraft, SKSE, Address Library and Alternate Start files installed by this script"
	local plugins=$LOCALAPPDATA/Skyrim\ Special\ Edition/Plugins.txt
	if [[ -f $GAME/.skycraft-deck/plugins && -f $plugins ]]; then
		python3 - "$plugins" "$GAME/.skycraft-deck/plugins" <<'PY'
import sys
path, record = sys.argv[1:3]
names = {l.strip().lower() for l in open(record) if l.strip()}
text = open(path, encoding="utf-8", errors="surrogateescape", newline="").read()
eol = "\r\n" if "\r\n" in text else "\n"
kept = [l for l in text.splitlines() if l.lstrip("*").strip().lower() not in names]
open(path, "w", encoding="utf-8", errors="surrogateescape", newline="").write(eol.join(kept) + (eol if kept else ""))
PY
		ok "plugins turned off in Plugins.txt"
	fi
	if [[ -f $MANIFEST ]]; then
		local rel
		while IFS= read -r rel; do
			[[ -n $rel ]] && rm -f -- "$GAME/$rel"
		done <"$MANIFEST"
		find "$GAME/Data" -mindepth 1 -type d -empty -delete 2>/dev/null || true
		rm -rf "$GAME/.skycraft-deck"
		ok "files removed"
	else
		warn "no record of installed files"
	fi
	if [[ -f $GAME/SkyrimSELauncher.exe.skycraft-backup ]]; then
		mv -f "$GAME/SkyrimSELauncher.exe.skycraft-backup" "$GAME/SkyrimSELauncher.exe"
		ok "Bethesda's launcher restored"
	fi
	if [[ ${1:-} == --purge ]]; then
		rm -rf "$LOCALAPPDATA/SkyCraft"
		ok "removed SkyCraft's Minecraft, its sign-in and its world (AppData/Local/SkyCraft)"
	else
		say "  SkyCraft's Minecraft, sign-in and world are kept in the prefix (AppData/Local/SkyCraft);"
		say "  ./skycraft-deck.sh uninstall --purge removes them too."
	fi
}

case ${1:-install} in
	install | update) cmd_install ;;
	signin) cmd_signin ;;
	status) cmd_status ;;
	logs) cmd_logs ;;
	uninstall) cmd_uninstall "${2:-}" ;;
	-h | --help | help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' ;;
	*) die "unknown command '$1' (install, signin, status, logs, uninstall)" ;;
esac
