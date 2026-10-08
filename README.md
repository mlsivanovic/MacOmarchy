# macOS sa Omarchy načinom rada

Native macOS Spaces i Mission Control ostaju osnova. Postojeći Hammerspoon
sada vodi i tiling, centralni meni i prečice. Ghostty ostaje terminal.
Amethyst je zaustavljen i uklonjen iz automatskog pokretanja.

## Prečice

Modifier je **Command (Cmd)**.

| Prečica | Akcija |
|---|---|
| Cmd + Return | Ghostty |
| Cmd + Shift + Return | Google Chrome |
| Cmd + Space / K | Pretraživi centralni meni |
| Cmd + strelice | Fokus susednog prozora na trenutnom monitoru |
| Cmd + L / Shift + L | Sledeći / prethodni layout |
| Cmd + A / W | Tall / Wide |
| Cmd + F | Prozor preko cele radne površine |
| Cmd + Shift + F | Floating layout za ručno raspoređivanje |
| Cmd + T | Floating toggle aktivnog prozora |
| Cmd + Shift + T | Globalni tiling uključi / isključi |
| Cmd + I / R | Prikaži layout / ponovo rasporedi |
| Cmd + Shift + ← / → | Zameni sa prethodnim / sledećim prozorom u rasporedu |
| Cmd + Shift + ↑ / ↓ | Premesti na prethodni / sledeći monitor |
| Cmd + M | Zameni sa glavnim prozorom u Tall/Wide layoutu |
| Cmd + − / = | Smanji / povećaj glavni panel |
| Cmd + 1–9 | Pređi na taj desktop **na monitoru fokusiranog prozora** |
| Cmd + Shift + 1–9 | Pošalji aktivni prozor na taj desktop istog monitora |
| Cmd + scroll | Kruženje kroz postojeće desktopove **monitora ispod miša** |
| Cmd + middle click | Mission Control |
| Cmd + Ctrl + scroll | Rotiranje prozora na monitoru |
| Cmd + Ctrl + V | Clipboard istorija |
| F12 | Ghostty quick terminal |
| Spotlight | Dostupan kroz macOS meni / Launchpad |
| Screenshot u centralnom meniju | Native screenshot / snimanje |

Cmd kombinacije za tiling preuzimaju istoimene prečice aplikacija (npr. Cmd+W,
Cmd+F, Cmd+T). Cmd+Space otvara centralni meni, a Cmd+Shift+1–9 služi za
slanje prozora i preuzima i kombinacije native screenshot prečica. Screenshot
je i dalje dostupan u centralnom meniju i kroz macOS Screenshot aplikaciju.
Native Move left/right a space koriste Ctrl+strelice, odvojeno od Cmd+strelica
za fokus prozora. Mission Control pregled koristi Ctrl+↑.

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
