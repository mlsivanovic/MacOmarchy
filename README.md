# macOS sa Omarchy načinom rada

Native macOS Spaces i Mission Control ostaju osnova. Postojeći Hammerspoon
sada vodi i tiling, centralni meni i prečice. Ghostty ostaje terminal.
Amethyst je zaustavljen i uklonjen iz automatskog pokretanja.

## Prečice

Za prečice koje se kose sa standardnim macOS ili aplikacijskim komandama
koristi se **Control + Option**. Cmd+Space, Cmd+W, standardne komande za tekst,
tabove, zoom i screenshot ostaju native. Cmd ostaje za launchere i gestove mišem.

| Prečica | Akcija |
|---|---|
| Cmd + Return | Ghostty |
| Cmd + Shift + Return | Google Chrome |
| Ctrl + Option + Space / K | Pretraživi centralni meni |
| Ctrl + Option + strelice | Fokus susednog prozora na trenutnom monitoru |
| Ctrl + Option + L / Shift + L | Sledeći / prethodni layout |
| Ctrl + Option + A / W | Tall / Wide |
| Ctrl + Option + F | Prozor preko cele radne površine |
| Ctrl + Option + Shift + F | Floating layout za ručno raspoređivanje |
| Ctrl + Option + T | Floating toggle aktivnog prozora |
| Ctrl + Option + Shift + T | Globalni tiling uključi / isključi |
| Ctrl + Option + I / R | Prikaži layout / ponovo rasporedi |
| Ctrl + Option + Shift + ← / → | Zameni sa prethodnim / sledećim prozorom |
| Ctrl + Option + Shift + ↑ / ↓ | Premesti na prethodni / sledeći monitor |
| Ctrl + Option + M | Zameni sa glavnim prozorom |
| Ctrl + Option + − / = | Smanji / povećaj glavni panel |
| Ctrl + Option + 1–9 | Desktop na monitoru fokusiranog prozora |
| Ctrl + Option + Shift + 1–9 | Pošalji prozor na desktop istog monitora |
| Cmd + scroll | Kruženje kroz desktopove monitora ispod miša |
| Cmd + middle click | Mission Control |
| Cmd + Ctrl + scroll | Rotiranje prozora na monitoru |
| Cmd + Ctrl + V | Clipboard istorija |
| F12 | Ghostty quick terminal |
| Cmd + Space | Native Spotlight |
| Cmd + W | Native zatvaranje prozora / taba |
| Cmd + Shift + 3 / 4 / 5 | Native screenshot / snimanje |

Brojevi su prebačeni na Ctrl+Option da Cmd+broj ostane za native tabove,
a Cmd+Shift+3/4/5 za screenshot. Native Mission Control i Space prečice
vraćene su na podešavanja pre Cmd migracije.

Brojevi desktopova su lokalni za monitor i preskaču fullscreen Spaces.
Na monitoru sa dva desktopa rade 1 i 2. Nepostojeći broj prikazuje obaveštenje;
dodatne desktopove napravi kroz Mission Control. Slanje prozora ne menja desktop.
Premesti se aktivni prozor aplikacije, ne svi njeni prozori.

## Automatski raspored

- Jedan običan prozor popunjava radnu površinu uz marginu 8 px.
- Dva prozora dele ekran 50/50; dodatni prozori se slažu u sekundarni panel.
- Svaki monitor i svaki native desktop imaju zaseban raspored.
- Posle prelaska na drugi monitor prozor se pridružuje njegovom aktivnom
  desktopu i raspoređuje zajedno sa tamošnjim prozorima.
- Tiling miruje dok se drži levi taster miša, pa se primeni po završetku drag-a.
- Provera prozora na 0,5 s pokriva otvaranje, zatvaranje i promene desktopa.
- Ciklus rasporeda: Tall → Wide → Fullscreen → Floating.
- Dijalozi, fullscreen/minimizovani prozori, System Settings, Hammerspoon,
  KeePassXC i eksplicitno floating prozori ne zauzimaju pločicu.
- Native Shortcuts za poslednja 2–4 prozora dostupni su iz menija uz Floating layout.

Cmd + scroll šalje stvarne Dock prečice, sa tačnim keycode/flags iz postojećih
macOS podešavanja. Pointer se kratko postavi na ciljani monitor pa vrati ako ga
korisnik nije pomerio. Move left/right a space moraju biti uključeni u
System Settings → Keyboard → Keyboard Shortcuts → Mission Control.
Automatsko preslaganje redosleda Spaces je isključeno.

Za slanje prozora na ovoj verziji macOS-a mali lokalni modul koristi noviji
SkyLight bridged API unutar Hammerspoon procesa, uz postojeću Accessibility
dozvolu. Rezultat se proverava preko stvarne pripadnosti prozora Space-u.
Nema Dock injection-a ili promene SIP-a. Ovo je privatni macOS API i potrebno
je ponoviti proveru posle većih macOS nadogradnji. Amethyst i Tiles ne treba
pokretati paralelno sa ovim tilingom.

## Izgled i pokretanje

Catppuccin Mocha/Latte u meniju menjaju sistemski dark/light i wallpaper.
Ghostty, Zed i VS Code prate sistemsku temu. Ostaje JetBrainsMono Nerd Font Mono.
Ghostty i Hammerspoon se pokreću pri prijavi preko lokalnih LaunchAgent fajlova.

## Fajlovi

| Izvor | Aktivna lokacija |
|---|---|
| config/hammerspoon/init.lua | ~/.hammerspoon/init.lua |
| config/omarchy.lua, desktops.lua, tiler.lua | ~/.hammerspoon/ |
| config/hammerspoon/space-move.m | Izvor lokalnog native modula |
| bin/build-space-move | Kompajlira ~/.hammerspoon/bin/space-move.so |
| config/ghostty.config | ~/.config/ghostty/config.ghostty |
| config/catppuccin-zed.json | ~/.config/zed/themes/catppuccin.json |
| config/editor-appearance.json | Izgled dodat u postojeća editor podešavanja |
| config/mocha.png, config/latte.png | ~/.hammerspoon/omarchy-assets/ |
| config/local.mac-omarchy.*.plist | ~/Library/LaunchAgents/ |

`config/legacy/` čuva neaktivnu Amethyst konfiguraciju i stari Spaces helper.
Native modul možeš ponovo kompajlirati sa `./bin/build-space-move`, a konfiguraciju
učitati preko Hammerspoon Reload Config. Behavioral testovi: `lua tests/tiler.lua` i `lua tests/desktops.lua`.

## Rezervna kopija i povratak

Početna kopija navedena je u `backup-location.txt` i nije u Git istoriji.
Kopija pre ove popravke: `~/.config/mac-omarchy/backups/20261008-201327-fixes/`.
Clipboard istorija nije kopirana u projekat.

Za povratak prethodnog Hammerspoon ponašanja vrati `hammerspoon-init.lua` iz
početne kopije na `~/.hammerspoon/init.lua`, pa Reload Config. Za povratak celog
izgleda vrati i editor settings iz kopije i izaberi sistemski izgled/wallpaper.
LaunchAgent fajlove možeš premestiti van `~/Library/LaunchAgents` i odjaviti se.
Postojeće aplikacije nisu brisane. Neaktivni Amethyst LaunchAgent sačuvan je u
`~/.config/mac-omarchy/local.mac-omarchy.amethyst.disabled.plist`.

## Izvori

- [Hammerspoon](https://www.hammerspoon.org/docs/) — window, screen, Space i event API.
- [Hammerspoon issue 3636](https://github.com/Hammerspoon/hammerspoon/issues/3636) — legacy moveWindowToSpace prijavljuje uspeh bez pomeranja.
- [yabai Space manager](https://github.com/asmvik/yabai/blob/master/src/space_manager.c) — noviji bridged Space API, referenca za lokalni adapter.
- [Catppuccin za Zed](https://github.com/catppuccin/zed) — tema, MIT licenca.
- [Ghostty dokumentacija](https://ghostty.org/docs/config) — postojeća konfiguracija.
