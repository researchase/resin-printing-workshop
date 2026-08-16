# Resin Printing Workshop

A Godot 4.7 teaching deck for a hands-on 3D resin printing workshop, built for
**Researchase** by Ashwin Venkat. Four screens, navigated with the tabs across the top
or the number keys.

| # | Screen | What it does |
|---|---|---|
| 1 | **Welcome** | Title card with a slowly rotating voxel-built print |
| 2 | **The chemistry** | Live 3D photopolymerisation: monomers, UV, radicals, chains, cross-links |
| 3 | **The printer** | A working MSLA machine printing layer by layer, with the live LCD mask |
| 4 | **Safety** | Why resin needs gloves, ventilation and proper disposal |

## Run it in a browser

**https://researchase.github.io/resin-printing-workshop/**

No install, works on any machine including a Mac with no Godot on it. It is a ~37 MB
download on first load, so open it once before the session and let it cache.

## Running it locally

    godot --path /path/to/ResinPrinterSim

or open the project in the Godot editor and press F5. Runs on Godot 4.6 and 4.7.

### Rebuilding the web version

The web build is a single-threaded export, which is what lets it run on GitHub Pages
without cross-origin isolation headers. Godot 4.6 export templates must be installed.

    godot --headless --path . --export-release "Web" build/web/index.html
    touch build/web/.nojekyll

Then publish the contents of `build/web/` to the `gh-pages` branch. Note the web build
uses Godot's **Compatibility** renderer, which does not tonemap the environment
background and lights the scene more flatly than Forward+ on the desktop — hence the very
dark background colours in the three 3D screens. Check any lighting change in both:

    godot --path . --rendering-method gl_compatibility

Launch flags (handy for jumping straight to a setup mid-class):

    -- --screen=0|1|2|3        start on a given screen
    -- --model=0|1|2           printer: vase / rook / twisted star
    -- --preset=0|1|2          printer: 0.10 mm / 0.05 mm / 0.025 mm layers
    -- --autoplay              printer: start printing immediately

## Controls

| Input | Action |
|---|---|
| 1 – 4, ◀ ▶ | switch screen |
| left-drag / wheel | orbit / zoom any 3D view |
| Space | chemistry: UV on/off · printer: play/pause |
| S | printer: print exactly one more layer, then pause |
| R | reset the current screen's simulation |
| Esc | quit |

---

## Screen 2 — the chemistry

A magnified drop of resin: ~130 monomer molecules, each drawn with the **two parallel
rods of a C=C double bond**, plus a dozen photoinitiators. Switch the UV on and the
mechanism plays out for real, one bond at a time:

1. **Absorption** — a 405 nm photon hits a photoinitiator, which splits into two free
   radicals.
2. **Initiation** — a radical attacks a monomer's double bond. One of the two rods
   disappears: the double bond has opened into a single bond, and the unpaired electron
   has moved to the far end.
3. **Propagation** — that new radical grabs the next monomer, and the next.
4. **Cross-linking** — chains bond to each other into one 3-D network. This is the step
   that makes cured resin a thermoset: it cannot be melted or dissolved back.
5. **Termination** — two radicals meet and pair up.

The panel tracks conversion, free monomers, live radicals, chains and cross-links, and
the state readout moves LIQUID → GEL → SOLID as the network forms. Worth saying out
loud: only 70–90 % of double bonds react during a print, which is exactly why parts need
post-curing.

### Why some resins are flexible and others snap

Pick a resin type and the network genuinely builds differently, then press **Pull it** to
load the cured network:

| Resin | Cross-link density | Under load |
|---|---|---|
| Rigid / standard | ~45 per 100 units | stretches ~7 %, then **snaps** |
| Tough / ABS-like | ~15 per 100 units | stretches ~22 % and springs back |
| Flexible / elastomeric | ~2 per 100 units | stretches ~45 % and springs back |

The single lever is **cross-link density** — how much loose chain sits between two
junctions. Short stiff monomers with two or three acrylate ends make almost every unit a
junction: the segments between them are a few atoms long, there is nothing to uncoil, and
the part is glassy and brittle. Long aliphatic chains with a reactive group at each end
give a loose network of coiled segments that can stretch and spring back — a rubber.
Tough resins blend the two.

This is also the honest answer to "why did my print get brittle after post-curing?":
more of the leftover double bonds react, and the network tightens.

## Screen 3 — the printer

Left is the machine, right is the live LCD mask — the black and white bitmap the screen
shows for the layer being cured. White = UV gets through = resin hardens there.

Talking points it is built to support:

1. **The four-step layer cycle** is highlighted live: lower → expose → cure → peel. The
   peel move is why resin prints are slow and why big flat cross-sections fail.
2. **The whole layer cures at once.** Twenty parts on the plate take the same time as
   one — watch "exposed area" change while the layer time does not.
3. **Prints hang upside-down.** The first layer cured ends up on top. Press *View part
   upright* at the end to show it.
4. **XY resolution is LCD pixels.** The mask runs at a deliberately coarse 144 × 96 px
   so the staircase edges are visible; a real 12K screen is about 0.02 mm per pixel.
5. **Z resolution costs time.** Switching layer height changes the demo layers, the real
   slice count (500 / 1000 / 2000) and the estimated machine time together.

Machine timings assume ~2.5 s exposure plus ~6 s of lift, peel and settle per layer,
typical for a consumer MSLA printer. The animation runs faster than real time; the speed
slider is the multiplier.

## Screen 4 — safety

Nine cards covering skin, eyes and UV, ventilation, IPA and fire, waste, spills, part
handling, and people, each with the reason behind the rule. Plus a tickable pre-flight
checklist and a first-aid panel. The framing ties back to screen 2: the acrylate groups
that bond to each other under UV react with skin proteins just as happily, which is why
uncured resin is a sensitiser.

---

## Layout

| File | Role |
|---|---|
| `scripts/app.gd` | screen manager and the top nav bar |
| `scripts/ui_kit.gd` | shared colours, labels, cards and buttons |
| `scripts/screen_home.gd` | title screen (edit the constants at the top to rebrand) |
| `scripts/screen_chem.gd` | the photopolymerisation simulation |
| `scripts/screen_printer.gd` | printer UI, readouts and the layer-cycle state machine |
| `scripts/printer.gd` | the 3D machine and the cured-layer geometry |
| `scripts/slicer.gd` | the "slicer": turns a shape into one bitmap per layer |
| `scripts/screen_safety.gd` | safety cards, checklist and first aid |

Printable models are defined procedurally in `slicer.gd` (`is_solid()`), so adding a
shape is a few lines of maths — no mesh assets to import.

Title, subtitle, presenter and company name are constants at the top of
`scripts/screen_home.gd`.
