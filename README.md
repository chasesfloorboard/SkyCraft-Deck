# SkyCraft for Steam Deck

An installer that puts [SkyCraft](https://github.com/chasmlol/SkyCraft) (play Skyrim as a Minecraft
player) on a **Steam Deck**, or any Linux PC with Steam's Skyrim Special Edition running in Proton.
You don't need a mod manager.

SkyCraft is made for Windows. This script handles what's different on the Deck:

- It installs **SKSE64**, **Address Library**, **SkyCraft** and (optionally) **Alternate Start**
  straight into Skyrim's `Data` folder. Folder names are merged case-insensitively, the way
  Windows would, so Proton doesn't end up seeing two `SKSE` folders.
- It makes Steam's **Play** button start Skyrim through SKSE, so it works from **Game Mode**.
- It **unpacks SkyCraft's Minecraft** (a portable Prism Launcher) into Skyrim's Proton prefix.
  SkyCraft normally does this itself with Windows' `tar.exe`, which Proton doesn't have. The script
  then points `SkyCraft.ini` at that Prism so SkyCraft starts it directly.
- It opens that Prism **inside Skyrim's prefix** once so you can sign in to your Microsoft account.
  The Deck's touchscreen is switched off while Prism is open: a tap crashes Prism under Proton
  (Wine doesn't implement the touch call Qt makes). Use the trackpad and R2.
- It adds **Controlify** (and YetAnotherConfigLib) to SkyCraft's Minecraft, from Modrinth, so the
  Deck's controller plays Minecraft's side without a keyboard-and-mouse layout.

Minecraft runs as a Windows program in the same Proton prefix as Skyrim, because SkyCraft's two
halves talk through Windows shared memory. Skyrim draws everything, and Minecraft stays hidden.

> **Status: experimental.** Tested end to end on desktop Arch Linux with Steam's Skyrim 1.7.104 and
> Proton Experimental (11.0): install, Minecraft sign-in, SkyCraft loading, Minecraft linking to
> Skyrim and in-game play all work. It hasn't been run on Steam Deck hardware yet; please open an
> issue with your results. SkyCraft itself is early too, so back up your saves.

## What you need

- **Skyrim Special Edition** (or Anniversary Edition) on Steam, game version **1.6.x / 1.7.x**.
  SkyCraft is developed on **1.7.104**.
- A Microsoft account that owns **Minecraft: Java Edition**.
- A free **Nexus Mods** account. The installer opens three mod pages for you, and you press
  download on each (Nexus doesn't let installers download them for you).

## Install

Everything here happens in **Desktop Mode** (Steam button > Power > Switch to Desktop).

1. **Download the installer:**
   **[SkyCraft-Installer.desktop](https://github.com/chasesfloorboard/SkyCraft-Deck/releases/latest/download/SkyCraft-Installer.desktop)**
2. **Open your Downloads folder and double-click `SkyCraft-Installer.desktop`.** If it asks
   whether to run or execute it, choose **Execute** / **Continue**.
3. **Follow the window that opens.** It does everything in order and tells you when it needs you:
   - If Skyrim isn't installed yet, it opens Steam to install it. If Skyrim has never been
     started, it starts it once: wait for the main menu, then quit.
   - It opens the three Nexus Mods pages. On each, log in, press **Manual Download** on the file
     it names, then **Slow download**. Leave the files in Downloads. The window ticks each one
     off as it arrives:

     | Mod | File |
     |---|---|
     | [SKSE64](https://www.nexusmods.com/skyrimspecialedition/mods/30379?tab=files) | **Skyrim Script Extender (SKSE64) Steam** (not GOG) |
     | [Address Library for SKSE Plugins](https://www.nexusmods.com/skyrimspecialedition/mods/32444?tab=files) | **All in one (Anniversary Edition)** |
     | [Alternate Start - Live Another Life](https://www.nexusmods.com/skyrimspecialedition/mods/272?tab=files) | main file. Optional, but strongly recommended: Skyrim's scripted opening can leave you stuck with SkyCraft |

   - It installs everything (it downloads SkyCraft itself).
   - It opens Prism Launcher so you can **sign in to Minecraft**: **Accounts > Manage Accounts >
     Add Microsoft**, then open the link on your phone (or scan the QR code), enter the code and
     sign in. Close Prism when your name shows up. (Don't press Launch. Skyrim does that.)
   - It adds **SkyCraft** to your app menu (under Games). Open it later to update, sign in
     again, or uninstall (right-click it for those options).
4. **Set up controls.** The installer adds [Controlify](https://modrinth.com/mod/controlify), a
   controller mod, to SkyCraft's Minecraft, so Skyrim keeps its Gamepad layout. Change just two
   things in it: the **right stick** to **Joystick Mouse** and the **right trackpad** to **Mouse**
   (click = left mouse button). See **[docs/controls.md](docs/controls.md)**.
5. **Play.** Go back to Game Mode and start Skyrim. The first start, Prism downloads Minecraft 26.3,
   Fabric and Java in the background (a few minutes). Skyrim's corner messages tell you when
   Minecraft is ready. After that, Minecraft starts and quits with Skyrim.

### From a terminal instead

```sh
cd ~
curl -fsSLO https://raw.githubusercontent.com/chasesfloorboard/SkyCraft-Deck/main/skycraft-deck.sh
chmod +x skycraft-deck.sh
./skycraft-deck.sh            # the same guided install
./skycraft-deck.sh install    # or just install, if the Nexus files are already in ~/Downloads
./skycraft-deck.sh signin     # then sign in to Minecraft
```

## Commands

| | |
|---|---|
| `./skycraft-deck.sh` | Guided install or update: waits for Steam, Skyrim and the Nexus downloads, installs, signs in, adds the app menu entry. |
| `./skycraft-deck.sh install` | Install, or update to the newest SkyCraft. Safe to run again. New Nexus files in `~/Downloads` are picked up too. |
| `./skycraft-deck.sh signin` | Open SkyCraft's Prism Launcher in Skyrim's prefix (sign in, or switch accounts). |
| `./skycraft-deck.sh status` | Show what's installed and whether Minecraft is signed in. |
| `./skycraft-deck.sh logs` | The end of SkyCraft's, SKSE's, Minecraft's and Prism's logs. |
| `./skycraft-deck.sh uninstall` | Remove everything it installed and restore Bethesda's launcher. `--purge` also deletes SkyCraft's Minecraft, sign-in and world. |

Overrides: `DOWNLOADS=/path` (where to look for the Nexus files), `STEAM_ROOT=/path` (Steam's
folder) and `SKYCRAFT_ZIP=/path/SkyCraft-x.y.z.zip` (a local SkyCraft release instead of the
latest one), `SKYCRAFT_MC_MEMORY=<MB>` (Minecraft's memory limit) and `SKYCRAFT_CONTROLLER=0`
(leave Controlify out).

## Good to know

- **Skyrim updates break SKSE.** After a Skyrim update, Skyrim won't start through SKSE until there's
  an SKSE build (and Address Library) for the new version. Download the new files and run `install`
  again. A Skyrim update or **Verify integrity of game files** also puts Bethesda's launcher back.
  Opening **SkyCraft** from the app menu (or running `install` again) fixes that.
- **Memory:** on a Steam Deck the installer limits Minecraft to 3 GB (it's 4 GB elsewhere); in
  testing, Minecraft used about 3.3 GB and Skyrim about 2.2 GB. Set your own limit with
  `SKYCRAFT_MC_MEMORY=<MB> ./skycraft-deck.sh install`. Keep other Skyrim mods light.
- **Frame rate:** both games share the CPU. On the Deck, cap the frame rate at 30 (Quick Access
  menu > Performance) for even frame times.
- **Where things are** (inside `steamapps/compatdata/489830/pfx/drive_c/users/steamuser/`):
  - SkyCraft's log: `Documents/My Games/Skyrim Special Edition/SKSE/SkyCraft.log`
  - Minecraft, Prism, the sign-in and your SkyCraft world: `AppData/Local/SkyCraft/`
  - For detailed logs, set `bDiagnostics = 1` in
    `steamapps/common/Skyrim Special Edition/Data/SKSE/Plugins/SkyCraft.ini`
- **Stuck on "SkyCraft: starting Minecraft..."?** Run `./skycraft-deck.sh logs`. If Prism needs
  you (sign-in expired, a download error), run `./skycraft-deck.sh signin` in Desktop Mode.
- SkyCraft's own [known limitations](https://github.com/chasmlol/SkyCraft#known-limitations) apply.

## How the Minecraft side works under Proton

SkyCraft's SKSE plugin starts Minecraft from inside Skyrim: `SkyCraft.ini`'s `sLauncher` points at
`%LOCALAPPDATA%\SkyCraft\Prism\prismlauncher.exe`, which in the prefix is
`C:\users\steamuser\AppData\Local\SkyCraft`. Prism then starts Minecraft with a Windows Java it
downloads itself. Because Skyrim, Prism and Minecraft all run in one Wine session, the Fabric mod
can open the plugin's `Local\SkyCraft_v1` shared memory exactly as on Windows. Everything crosses
through that memory, including overlay pixels and block geometry. There's no GPU interop between
the two processes, which is why this can work in Proton at all.

## License

[MIT](LICENSE). SkyCraft, SKSE, Address Library, Alternate Start, Prism Launcher and Minecraft
belong to their own authors. This repo only contains the installer. You need to own Skyrim and
Minecraft: Java Edition.
