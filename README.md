# macOS sa Omarchy načinom rada

Native macOS Spaces i Mission Control ostaju osnova. Amethyst automatski
raspoređuje prozore, a Hammerspoon daje centralni meni i prečice.

## Prečice

Osnovni modifier je **Control + Option**. Command ostaje za macOS i aplikacije.

| Prečica | Akcija |
|---|---|
| Ctrl + Option + Return | Ghostty |
| Ctrl + Option + Shift + Return | Google Chrome |
| Ctrl + Option + Space | Pretraživi centralni meni |
| Ctrl + Option + K | Isti meni sa svim komandama i prečicama |
| Ctrl + Option + strelice | Fokus susednog prozora na trenutnom monitoru |
| Ctrl + Option + L | Sledeći layout |
| Ctrl + Option + Shift + L | Prethodni layout |
| Ctrl + Option + B / A / W | BSP / Tall / Wide |
| Ctrl + Option + F | Jedan prozor popunjava radnu površinu |
| Ctrl + Option + Shift + F | Floating layout za ručno raspoređivanje |
| Ctrl + Option + T | Floating toggle aktivnog prozora |
| Ctrl + Option + Shift + T | Globalni tiling uključi / isključi |
| Ctrl + Option + I | Prikaži stvarni trenutni Amethyst layout |
| Ctrl + Option + R | Ponovo rasporedi prozore |
| Ctrl + Option + Shift + ← / → | Zameni sa prethodnim / sledećim prozorom |
| Ctrl + Option + Shift + ↑ / ↓ | Premesti na prethodni / sledeći monitor |
| Ctrl + Option + M | Zameni sa glavnim prozorom u Tall/Wide layoutu |
| Ctrl + Option + − / = | Smanji / povećaj glavni panel u Tall/Wide layoutu |
| Ctrl + Option + Shift + 1–9 | Premesti prozor na odgovarajući native Space |
| Cmd + scroll | Postojeća promena native Space-a na monitoru ispod miša |
| Cmd + middle click | Postojeći Mission Control |
| Cmd + Ctrl + scroll | Postojeće rotiranje prozora na monitoru |
| Cmd + Ctrl + V | Postojeća clipboard istorija |
| F12 | Postojeći Ghostty quick terminal |
| Cmd + Space | Native Spotlight |
| Cmd + Shift + 3 / 4 / 5 | Native screenshot / screenshot i snimanje |

Amethyst zamene levo/desno prate redosled prozora u layoutu; nisu geometrijska
zamena baš sa susedom u tom smeru. Fokus strelicama jeste geometrijski.

## Rasporedi i izgled

- Layout ciklus: BSP → Tall → Wide → Fullscreen → Floating.
- Unutrašnji razmak je 8 px; margina 4 px plus padding 4 px na ivicama.
- Mali prozori, System Settings, Hammerspoon i KeePassXC ostaju floating.
- Teme u meniju: Catppuccin Mocha i Latte. Menjaju sistemski dark/light mode i
  wallpaper na povezanim ekranima. Ghostty, Zed i VS Code prate sistemsku temu.
- Monospace font: postojeći JetBrainsMono Nerd Font Mono.
- Hammerspoon menubar prikazuje broj native Space-a fokusiranog ekrana.
  Stvarni layout prikazuje Amethyst HUD na Ctrl + Option + I.
- Native Shortcuts za poslednja 2–4 prozora dostupni su u meniju; pre njihove
  primene bira se Floating layout, da automatski tiling ne poništi rezultat.
- Tiles nije potreban uz Amethyst. Nemoj istovremeno koristiti oba za isti prozor.
- Automatsko preslaganje redosleda Spaces je isključeno.

Ghostty, Amethyst i Hammerspoon imaju lokalne LaunchAgent unose za pokretanje
pri prijavi. To ne zahteva gašenje SIP-a.

## Fajlovi

| Fajl | Aktivna lokacija |
|---|---|
| config/omarchy.lua | ~/.hammerspoon/omarchy.lua |
| config/amethyst.yml | ~/.amethyst.yml |
| config/ghostty.config | ~/.config/ghostty/config.ghostty (postojeća konfiguracija) |
| config/catppuccin-zed.json | ~/.config/zed/themes/catppuccin.json |
| config/editor-appearance.json | Samo izgled dodat u postojeća Zed/VS Code podešavanja |
| config/mocha.png, config/latte.png | ~/.hammerspoon/omarchy-assets/ |
| config/local.mac-omarchy.*.plist | ~/Library/LaunchAgents/ |

Postojeći init.lua je proširen sa `omarchy = require("omarchy")`.
Postojeći privatni macOS Spaces helper nije menjan. Potrebno ga je proveriti
posle macOS nadogradnji.

## Rezervna kopija i povratak

Lokacija rezervne kopije nalazi se u `backup-location.txt` i nije u Git istoriji.
Kopija sadrži originalni Hammerspoon init, Ghostty config, editor settings i
izvezena sistemska podešavanja pre ove promene. Clipboard istorija nije kopirana
u ovaj projekat.

Za povratak prethodnog ponašanja: ugasi Amethyst, ukloni njegova tri
`local.mac-omarchy.*` LaunchAgent fajla iz `~/Library/LaunchAgents`, vrati
`hammerspoon-init.lua` iz kopije na `~/.hammerspoon/init.lua`, pa Reload Config.
Vrati Zed/VS Code settings iz kopije ako želiš prethodni izgled. Sistemski izgled
i wallpaper možeš promeniti u System Settings. Postojeće aplikacije nisu brisane.

## Izvori

- https://github.com/ianyh/Amethyst — konfiguracija za instaliranu verziju 0.24.3.
- https://github.com/catppuccin/zed — Catppuccin tema (MIT, vidi LICENSE.catppuccin).
- https://ghostty.org/docs/config — postojeći Ghostty config je sačuvan.
- https://www.hammerspoon.org/docs/ — Hammerspoon modul.
