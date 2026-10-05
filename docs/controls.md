# Controls on the Steam Deck

The installer adds [Controlify](https://modrinth.com/mod/controlify), a controller mod, to
SkyCraft's Minecraft. Minecraft reads the Deck's controller as a gamepad, so Skyrim keeps Steam's
**Gamepad** layout. Looking around and clicking still go through SkyCraft as mouse input, so the
right stick and right trackpad have to send mouse movement.

## Set it up

1. In Game Mode, select Skyrim, then the **controller icon** (Controller Settings) > **Edit Layout**.
   (Or in Desktop Mode: Steam > Skyrim > Manage > Controller Layout.) Leave the layout on
   **Gamepad**; don't switch templates.
2. **Joysticks** > **Right Joystick**: set its behavior to **Joystick Mouse**. That's how you look
   around.
3. **Trackpads** > **Right Trackpad**: set its behavior to **Mouse**, and set its **Click** to
   **Left Mouse Click**. That's for fine aiming and the cursor in Minecraft screens (inventory,
   crafting, chests).
4. Leave everything else as it is, and play.

Tested on a Steam Deck LCD (SteamOS 3.7) with SkyCraft 0.1.2 and Controlify 3.5.3.

## Keyboard and mouse layout (without Controlify)

If you install with `SKYCRAFT_CONTROLLER=0`, or Controlify doesn't work for you, SkyCraft reads
**keyboard and mouse** only, because Minecraft does. The controller then has to send keys and mouse
movement to Skyrim, which Steam Input does:

1. In Game Mode, select Skyrim, then the **controller icon** (Controller Settings).
2. **Edit Layout** > **Templates** > **Keyboard (WASD) and Mouse**. Apply it.
3. Change the buttons below to match SkyCraft's keys (**Edit Layout** > *Buttons*, *Triggers*, ...).

### Suggested keyboard and mouse layout

| Deck control | Key / mouse | In SkyCraft |
|---|---|---|
| Left stick | W A S D | Move |
| Left stick click | Left Ctrl | Sprint |
| Right trackpad (or right stick as *Joystick Mouse*) | Mouse | Look |
| Gyro (optional, *As Mouse*, while touching the right pad) | Mouse | Fine aim |
| R2 | Left mouse button | Attack / break block |
| L2 | Right mouse button | Use / place block / block with shield |
| A | Space | Jump / swim up |
| B | Left Shift | Crouch (Skyrim sneak) |
| X | G | Skyrim activate: doors, talk, containers, furniture |
| Y | E | Minecraft inventory |
| R1 / L1 | Mouse wheel down / up | Next / previous hotbar slot |
| Menu (☰) | Esc | Skyrim menu (save, load, settings), or close a Minecraft screen |
| View (⧉) | O | Minecraft pause / options menu (Open to LAN, Skyrim destruction toggle) |
| D-pad up | M | Skyrim map |
| D-pad down | J | Skyrim journal |
| D-pad left | Q | Drop item |
| D-pad right | F5 | Camera (first / third person) |
| R4 | F | Swap item to offhand |
| L4 | H | Skyrim wait |
| R5 | T | Chat (`/join`, `/leave`) |
| L5 | F9 | Skyrim quickload |
| Left trackpad, as a **Touch Menu** with 9 items | 1 – 9 | Pick a hotbar slot directly |

The on-screen keyboard (**Steam + X**) types into Minecraft chat and commands.

## SkyCraft's keys, for reference

From [SkyCraft's README](https://github.com/chasmlol/SkyCraft#controls). Minecraft gets every key
except these, which still go to Skyrim:

| Key | Does |
|---|---|
| G | Skyrim activate |
| Esc | Skyrim menu (or closes an open Minecraft screen) |
| J / M | Skyrim journal / map |
| H | Skyrim wait |
| F9 | Skyrim quickload |
| ~ | Skyrim console |
| O | Minecraft pause / options menu |
