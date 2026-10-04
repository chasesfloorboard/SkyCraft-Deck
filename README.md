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

Minecraft runs as a Windows program in the same Proton prefix as Skyrim, because SkyCraft's two
halves talk through Windows shared memory. Skyrim draws everything, and Minecraft stays hidden.

> **Status: experimental.** The installer has been tested against a simulated Steam library, and
> SkyCraft's Prism Launcher has been run under Proton 9 and Proton 11 (its sign-in reaches
> Microsoft). Full gameplay on real Deck hardware hasn't been confirmed yet. Please open an issue
> with your results. SkyCraft itself is early too, so back up your saves.

## What you need

- **Skyrim Special Edition** (or Anniversary Edition) on Steam, game version **1.6.x / 1.7.x**.
  SkyCraft is developed on **1.7.104**.
- A Microsoft account that owns **Minecraft: Java Edition**.
- These downloads from Nexus Mods (a free account works; use **Manual Download**). Leave them in
  `~/Downloads`:

  | Mod | File |
  |---|---|
  | [SKSE64](https://www.nexusmods.com/skyrimspecialedition/mods/30379?tab=files) | the build for **your** game version (not GOG) |
  | [Address Library for SKSE Plugins](https://www.nexusmods.com/skyrimspecialedition/mods/32444?tab=files) | **All in one (Anniversary Edition)** |
  | [Alternate Start - Live Another Life](https://www.nexusmods.com/skyrimspecialedition/mods/272?tab=files) | main file. Optional, but strongly recommended: Skyrim's scripted opening can leave you stuck with SkyCraft |

The script downloads SkyCraft itself (its latest GitHub release).

## Install

Everything here happens in **Desktop Mode** (Steam button > Power > Switch to Desktop).

1. **Start Skyrim once from Steam** and get to its main menu, then quit. That creates its Proton
   prefix.
2. **Download the Nexus files above** into `~/Downloads`.
3. **Open Konsole** and run:

   ```sh
   cd ~
   curl -fsSLO https://raw.githubusercontent.com/chasesfloorboard/SkyCraft-Deck/main/skycraft-deck.sh
   chmod +x skycraft-deck.sh
   ./skycraft-deck.sh install
   ```

4. **Sign in to Minecraft:**

   ```sh
   ./skycraft-deck.sh signin
   ```

   Prism Launcher opens. Go to **Accounts > Manage Accounts > Add Microsoft**. It shows a code and
   a QR code: open the link on your phone, enter the code and sign in. Then close Prism. (Don't
   launch the instance from Prism. Skyrim does that.)
5. **Set up controls.** SkyCraft is played with keyboard and mouse, so give Skyrim a keyboard and
   mouse Steam Input layout. See **[docs/controls.md](docs/controls.md)**.
6. **Play.** Go back to Game Mode and start Skyrim. The first start, Prism downloads Minecraft 26.3,
   Fabric and Java in the background (a few minutes). Skyrim's corner messages tell you when
   Minecraft is ready. After that, Minecraft starts and quits with Skyrim.

## Commands

| | |
|---|---|
| `./skycraft-deck.sh install` | Install, or update to the newest SkyCraft. Safe to run again. New Nexus files in `~/Downloads` are picked up too. |
| `./skycraft-deck.sh signin` | Open SkyCraft's Prism Launcher in Skyrim's prefix (sign in, or switch accounts). |
| `./skycraft-deck.sh status` | Show what's installed and whether Minecraft is signed in. |
| `./skycraft-deck.sh logs` | The end of SkyCraft's, SKSE's, Minecraft's and Prism's logs. |
| `./skycraft-deck.sh uninstall` | Remove everything it installed and restore Bethesda's launcher. `--purge` also deletes SkyCraft's Minecraft, sign-in and world. |

Overrides: `DOWNLOADS=/path` (where to look for the Nexus files), `STEAM_ROOT=/path` (Steam's
folder) and `SKYCRAFT_ZIP=/path/SkyCraft-x.y.z.zip` (a local SkyCraft release instead of the
latest one).

## Good to know

- **Skyrim updates break SKSE.** After a Skyrim update, Skyrim won't start through SKSE until there's
  an SKSE build (and Address Library) for the new version. Download the new files and run `install`
  again. A Skyrim update or **Verify integrity of game files** also puts Bethesda's launcher back.
  Running `install` again fixes that.
- **Memory:** Minecraft takes up to 4 GB on top of Skyrim. Keep other Skyrim mods light.
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
