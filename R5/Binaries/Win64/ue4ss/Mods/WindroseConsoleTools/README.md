# Windrose Console Tools

**Repository:** https://github.com/dgomiller/Windrose-Console-Tools — latest releases, source,
and issue tracker.

A small, standalone set of `rf`-prefixed console commands for Windrose — spawning something for a
quick look, inspecting whatever you're aiming at, basic utility toggles (no-clip, freeze AI), a
repositionable photo camera, and weather/time control.

This is a lightweight, commands-only tool. It does not add any on-screen menu or UI — everything
is typed into the console. If you want a full in-game menu with hundreds of placeable items, a
persistent base that survives reloads, NPC customization, photo mode with lights, and all the rest
of it, that's what [**Living Base Enhanced**](https://www.nexusmods.com/windrose/mods/535) is for. Windrose Console Tools is deliberately just the
bare debug/testing commands, for people who just want quick console-driven tools without the rest.

**Independent of Living Base / Living Base Enhanced.** You can run this mod with LBE installed, or
entirely on its own — it shares no files, no state, and no dependency with it. Confirmed working
with LBE and its companion disabled entirely.

**Nothing is saved.** Everything this mod spawns, moves, or changes (spawned actors, decor, the
photo camera, no-clip state) is session-only. Closing the game — or just running `rfdespawn` /
`rfcamera off` yourself — removes it. This mod never writes to any save file or persistence
ledger.

**Visual feedback on every command.** Running a command — whether typed into the console or
triggered from a keybind — shows an on-screen confirmation, not just a console/log line. That
matters most for keybinds, since there's no console open to read when one fires: you'll still see
it worked. Verbose commands (a full property dump, the full command list) show one summary toast
instead of flooding the screen with one per line, and async commands (`rfsetweather`, `rfsettime`,
`rfnudge`) confirm again once the change has actually finished applying, not just that it was
accepted.

## Installation

Install UE4SS (latest experimental / RE-UE4SS build) into Windrose first, same as any other UE4SS
mod for this game.

**Automatic:** This mod is designed to be installed using Vortex Mod Manager.

**Manual:** Extract the download to the root of the Windrose game folder — it will place the mod
folder at `...\Windrose\R5\Binaries\Win64\ue4ss\Mods\WindroseConsoleTools\`. Then open
`ue4ss/Mods/mods.txt` and add the line `WindroseConsoleTools : 1`.

## Uninstallation

**Automatic:** If installed with Vortex, uninstall may be completed using it.

**Manual:** Remove the `WindroseConsoleTools` folder from `ue4ss/Mods/`, and remove its line from
`mods.txt`. Nothing this mod does is saved, so there's nothing else to clean up.

## General usage

Every command starts with `rf`. Type commands directly into the in-game console.

**Start with `rfhelp`.** On its own it lists every command this mod registers, by name. Run
`rfhelp <command>` (e.g. `rfhelp rfnoclip`) for that one command's exact syntax and a full
description. Run `rfhelp find <word>` to search by keyword across every command's name and
description.

**Most commands act on a "current target."** Aim your camera at something and run `rftarget` —
it remembers the nearest thing in front of you as your current target. A handful of commands
(`rftargetdata`, `rfgettargetfuncs`, `rfnoai`, `rfmeshsolid`, `rftargetmove`) then act on whatever
that target currently is, so the usual pattern is: `rftarget`, then whichever follow-up command you
need, as many times as you like, until you `rftarget` something else.

**Commands you spawn are tracked separately.** `rfentityspawn` and `rfmeshspawn` both track what
they spawn in their own list; `rfdespawn` removes the nearest one. This is a different, smaller
list than the "current target" above — spawning something also sets it as your current target
automatically, but despawning only ever touches things this mod itself spawned, never anything
that already existed in the world.

**Most values are typed, not clicked.** Several commands (`rftargetmove`, camera commands) take
exact numbers so a result is reproducible — you can paste the same command again later and get the
same result back.

**Finding a class/asset path for `rfentityspawn`/`rfmeshspawn`.** Both commands need the exact
full `/Game/...` path of whatever you want to spawn, which isn't something you'd normally know off
the top of your head. `pakcontents.xlsx` (included in this repo) is a full listing of every asset
in the game's own pak files — search it for a name you recognize (a Blueprint for `rfentityspawn`,
a `SM_...` static mesh for `rfmeshspawn`) to find its real path.

## Keybinds (optional)

Everything in this mod is console-only by default — nothing is bound to a key out of the box. If
you have **R5ModSettings** installed, open Settings > Mods in-game and you'll find a row for each
of the actions below (in this same order), each settable to any key you like (starting at "None").
This list is **not** a 1:1 mirror of every console command — commands that need a real argument
with no sensible default (a class/mesh path, a camera axis, etc.) aren't offered as a keybind at
all, since a key bound to one could only ever replay its usage reminder. Every row's own detail
pane in Settings > Mods repeats its full description plus "(Restart required to take effect.)" —
**a key you pick or change there only takes effect after restarting the game, not live.** Without
R5ModSettings installed, this section doesn't apply — every command still works from the console
exactly as documented below.

| # | Panel title | What it does |
| --- | --- | --- |
| 1 | `rftarget` | Aims via your camera and sets the nearest actor in front of you as the current target. |
| 2 | `rftargetdata` | Prints every property of the current target. |
| 3 | `rfgettargetfuncs` | Lists every function name on the current target's class. |
| 4 | `rfdespawn` | Despawns the nearest actor you spawned with `rfentityspawn`/`rfmeshspawn`. |
| 5 | `rfnoai on (freeze)` | Freezes the current target's AI. ("on" refers to the no-AI state being turned on — i.e. the target's AI gets disabled.) |
| 6 | `rfnoai off (resume)` | Resumes the current target's AI. ("off" turns the no-AI state back off — i.e. the target's AI is re-enabled.) |
| 7 | Cycle weather | Steps to the next weather preset in the list each press, looping back to the first after the last. |
| 8 | Cycle camera: tripod -> selfie -> off | Steps the `rfcamera` photo camera through tripod → selfie → off → tripod each press. |
| 9 | Reset Camera | A separate action from the cycle above — re-anchors the tripod camera to your current position/facing (does nothing in selfie mode or while the camera is off). |
| 10 | `rfnoclip (toggle)` | Toggles no-clip on your own character on/off with a single key. |
| 11 | `rfnudge up` | Moves you straight up 100 units (for use while `rfnoclip` is on). |
| 12 | `rfnudge down` | Moves you straight down 100 units (for use while `rfnoclip` is on). |
| 13 | `rfhelp` | Lists every console command this mod registers. |
| 14 | `rfver` | Prints version, credits, license summary, and repository URL. |

## Commands

### Help

#### `rfhelp` / `rfhelp <command>` / `rfhelp find <word> [more words]`
Lists every console command this mod registers, by name. Run `rfhelp <command>` for that one
command's exact syntax and a full description. Run `rfhelp find <word> [more words]` to search —
it lists every command whose name, usage, or description contains all the given words.

#### `rfver`
Prints this mod's version number, credits, a short license summary, and its GitHub repository
URL (for updates/issues). Useful for checking exactly which version you have installed.

### Targeting and inspection

#### `rftarget` / `rftarget player` / `rftarget child <propertyName>`
Aims using your camera's look direction and remembers the nearest actor in front of you (within
400 units) as the "current target" for `rftargetdata`/`rfgettargetfuncs`/`rfnoai`. `rftarget
player` targets your own character instead. `rftarget child <propertyName>` re-points the target
at a named object-reference property found on whatever is currently targeted, so you can drill one
step deeper (e.g. from an actor into one of its components) — run `rftargetdata` first to see what
property names are available to drill into.

#### `rftargetdata`
Prints every property (name and current value) declared on your current target (set by
`rftarget`), walking up its entire class hierarchy from the most specific class to the base Object
class. This is how you find out what an object actually is — its stats, its component references,
its settings. Run `rftarget` first to set a target.

#### `rfgettargetfuncs`
Lists the name of every function declared on your current target's class (and every parent class
above it), without calling any of them — purely a read-only listing. Useful when `rftargetdata`
shows an object with few or no readable properties, since some game objects expose their real data
only through getter functions instead of plain properties.

### Spawning

#### `rfentityspawn </Game/Path/To/BP_Something.BP_Something_C> [yaw]`
Spawns one instance of the given class about 200 units in front of you, optionally facing the
given yaw in degrees (default 0 = facing the same direction you are). The class path must be the
full `/Game/...` path including the trailing `_C`. This is for quick testing/visual checks only —
nothing spawned this way is saved: it exists only for the current play session (closing the game,
or running `rfdespawn`, removes it). Not every class is spawnable this way — some require extra
setup the engine can't provide generically and will fail with a "spawn failed" message.

#### `rfmeshspawn </Game/Path/To/SM_Something.SM_Something> [zOffset]`
Spawns a raw static mesh asset as plain inert decoration (no pickup glow, no physics toss) 200
units in front of you, raised by zOffset units (default 20). Useful for previewing an asset without
needing to add it to any kind of item list first. The path must be the full `/Game/...` path and
must repeat the asset name after the final dot, e.g. `/Game/.../SM_Foo.SM_Foo`. Tracked the same
way as `rfentityspawn` — `rfdespawn` removes it.

#### `rfdespawn`
Removes the nearest actor that you previously spawned with `rfentityspawn` or `rfmeshspawn`
(distance measured from your own character, regardless of which way you're facing). Only ever
affects actors this mod itself spawned and is still tracking — it will never remove anything that
already existed in the world. If you've spawned several things, run it repeatedly, nearest first.

#### `rftargetmove [x=amount] [y=amount] [z=amount] [yaw=amount] [pitch=amount] [roll=amount] [scale=amount]`
Nudges your current target (set by `rftarget`) by the given amounts — position in world units
(x/y/z), rotation in degrees (yaw/pitch/roll), and uniform scale (scale). Every value is a **delta**
added to whatever the target already has, not an absolute value, and any parameter you don't
include is left completely untouched — so `rftargetmove x=5` moves it 5 units on X only, without
needing to also specify `y=0 z=0` etc. Combine as many as you like in one call, e.g. `rftargetmove
x=10 z=-5 yaw=45 scale=0.2`. Negative amounts work the same way, e.g. `rftargetmove scale=-0.1`
shrinks it slightly.

#### `rfmeshsolid <on|off>`
Makes your current target (set by `rftarget`) a real physical blocker you can't walk through
("on"), or removes its collision entirely ("off"). Most raw decor meshes default to
pass-through/overlap-only collision (you can walk right through them) — this is how you make one
actually solid, or undo that.

### Movement / utility

#### `rfnoai [on|off]`
Freezes (default, or "on") or resumes ("off") the AI of your current target (set by `rftarget`) —
it stops moving/acting, which is useful for inspecting an NPC or creature up close without it
wandering off or attacking. This stops its AI "brain" and zeroes its current movement; it does not
make it invulnerable or otherwise change its stats.

#### `rfnoclip` / `rfnoclip <on|off>`
Toggles no-clip (fly freely through walls/terrain, no gravity) on your own character, by writing
directly to its movement component (the game's built-in Ghost()/Fly() cheat functions are
confirmed non-functional in this build, which is why this writes the underlying properties directly
instead). Run with no argument (or from a keybind) to flip it based on its current state;
`on`/`off` force a specific state. While active, looking up/down and moving forward actually
climbs/descends like a normal free-fly camera — your existing movement keys work, you don't need a
separate up/down key. Prints a readback of the values it just set, so you can confirm it actually
took effect. `rfnudge` is still available as a precise alternative if you want exact vertical
control.

#### `rfnudge <up|down> [amount]`
Moves your own character straight up or down by `amount` world units (default 100). This is
specifically for vertical movement while `rfnoclip` is on, as an exact/repeatable alternative to
just looking up/down and moving forward. Run it repeatedly to keep climbing or descending, e.g.
`rfnudge up 50` several times in a row.

### Camera

#### `rfcamera <tripod|selfie|off|reset>`
Spawns (or repositions) a standalone camera for taking screenshots. `tripod` places it where
you're standing, facing the same direction you are, and leaves it there even as you walk away —
good for a fixed-composition shot. `selfie` places it in front of your face, facing back at you,
and keeps following your look direction every frame — good for a selfie-style shot. `off` removes
the camera and returns your view to normal. `reset` re-anchors tripod mode to your current position
(selfie has nothing to reset, since it always follows you). Only one camera is active at a time —
switching modes replaces whichever one was active. This is a plain engine camera, not a custom
asset, so it works with just this mod installed.

#### `rfcammove <x|y|z> <amount>`
Nudges the active `rfcamera` camera along one world axis by a signed amount (positive or
negative), for exact/repeatable positioning. Does nothing (with a message) if no camera is
currently active.

#### `rfcamrotate <pitch|yaw|roll> <amount>`
Rotates the active `rfcamera` camera on one axis by a signed number of degrees, for
exact/repeatable framing. Does nothing (with a message) if no camera is currently active.

#### `rfcamfov <value>`
Sets the field of view (in degrees, e.g. 90) on the active `rfcamera` camera's lens. Does nothing
(with a message) if no camera is currently active.

#### `rfcamcoords` / `rfcamcoords <X,Y,Z>` / `rfcamcoords <X,Y,Z> <Pitch,Yaw,Roll>`
Reads or sets the active `rfcamera` camera's exact position and rotation (each as three
comma-separated numbers, no spaces). With no arguments, prints the current pose **and** a
ready-to-paste command that reproduces it — useful for saving/restoring a specific shot. With one
argument, sets position only. With both, sets position and rotation.

### Weather and time

#### `rfsetweather [name]`
Forces the current weather immediately (no argument = Sunny). Valid names: Windy, TortugaMist,
TestSunny, TestCloudy, Sunny, Storm, RainHeavy, Rainbow, Rain, Overcast, Mist, LobbySunny,
HighPressure, Fog, Default, Cloudy, AshlandsFog. These are the preset's own in-engine names, not
necessarily in an order that means anything — just try the one you want. Safe to re-run any time
weather changes mid-session.

#### `rfsettime [realHour] [speedInv]`
Sets the day/night cycle to a specific hour on a real 24-hour clock (e.g. 14 for 2pm) and freezes
it there exactly, for consistent lighting across several screenshots. Takes up to about 20 seconds
to arrive, since it works by fast-forwarding the clock rather than teleporting it. `speedInv`
(default 0.0125) controls how fast it fast-forwards — a smaller number is faster. Safe to re-run
any number of times, including right after a previous one finished.

## Known limitations

**You cannot spawn a dropped inventory item (a real, lootable weapon/resource/etc. as if it had
been dropped from someone's inventory) with this mod.** `rfentityspawn`/`rfmeshspawn` can spawn a
class or a raw mesh for a visual preview, but a real dropped-item pickup's actual identity (what
item it is, its stack count, its stats) is not exposed anywhere this mod can read it — the game's
own internal "drop view" object for a loot pickup has zero properties and zero usable functions
visible to UE4SS's reflection at all, and the pickup's interaction-prompt data is just generic,
shared UI configuration, not per-item data. This was investigated directly (probing a real
world-dropped item) rather than assumed. `rfmeshspawn` is the closest substitute if you just want
the right static mesh sitting in the world — it just won't behave as a real, inventory-backed
pickup.

## Credits

Built by RedFalcon, reusing proven techniques originally developed for [*Living Base Enhanced*](https://www.nexusmods.com/windrose/mods/535).
