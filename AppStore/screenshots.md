# Screenshots and App Preview

The media is **not made by hand and is not in git** — the scripts below produce
it. Uploading is manual: in App Store Connect drag the files into the *App
Preview and Screenshots* section (language switch at the top, one locale at a
time).

```bash
Tools/AppStoreMedia/media.sh screenshots iphone   # iPhone screenshots, both languages (~4 min)
Tools/AppStoreMedia/media.sh screenshots ipad     # iPad screenshots (~4 min)
Tools/AppStoreMedia/media.sh screenshots duo      # iPhone Duo — needs you once per language, see below
Tools/AppStoreMedia/media.sh video iphone         # iPhone previews (~4 min)
Tools/AppStoreMedia/media.sh video ipad           # iPad previews (~4 min)
Tools/AppStoreMedia/media.sh                      # everything, the Duo included
Tools/AppStoreMedia/compose.sh                    # the colour, the heading and the device frame (~5 min)
```

Run them from the repository root. `media.sh` needs Xcode, the *iPhone 18 Pro*,
*iPhone 18 Pro Max*, *iPad Pro 13-inch (M5)* and *iPhone Duo* simulators (each is
created when missing) and ImageMagick (`brew install imagemagick`); `compose.sh` needs only ImageMagick; Python 3 for the
preview's music comes with macOS. `OUT_ROOT=…` stands in for `AppStore/` in
both scripts — `media.sh` writes its `screenshots/` and `preview/` there, and
`compose.sh` reads that `screenshots/` and writes `screenshots-composed/` beside
it — which is how to try a change without touching the set you are about to
upload. `IN_ROOT=…` points `compose.sh` at plain shots kept anywhere else.

The tools are the Sudoku project's (github.com/RobertLib/sudoku), with this
game's poses, demo, captions and colours. Everything that file describes about
looking after the simulators holds here unchanged: each locale is shot in a
simulator switched to that language (the status bar is the system's), an
installed Wordwander is copied aside to `~/Library/Application Support/wordwander-appstore/`
and put back afterwards with its data, the simulators' languages and running
state are restored, nothing is replaced until its replacement is whole, and a
failed run keeps its working folder and says where. The `swift` tools print a
page of AVFoundation deprecation warnings every run; the line that matters is
the last one, which reports what the finished file actually holds.

## What the scripts produce

| What | Where | Resolution | Count |
|---|---|---|---|
| iPhone 6.3" screenshots | `screenshots/<locale>/iphone-6.3/` | 1206 × 2622 | 10 |
| iPhone 6.9" screenshots | `screenshots/<locale>/iphone-6.9/` | 1320 × 2868 | 10 |
| iPad 13" screenshots | `screenshots/<locale>/ipad-13/` | 2064 × 2752 | 10 |
| iPhone Duo screenshots | `screenshots/<locale>/iphone-duo/` | 2007 × 2853 | 10 |
| The same, composed for the store | `screenshots-composed/<locale>/<device>/` | same | 10 per device |
| iPhone 6.3" App Preview | `preview/<locale>/iphone-6.3.mp4` | 886 × 1920, a constant 30 fps, AAC | 1 |
| iPhone 6.9" App Preview | `preview/<locale>/iphone-6.9.mp4` | the same file as the 6.3" one | 1 |
| iPhone Duo App Preview | `preview/<locale>/iphone-duo.mp4` | the same file as the 6.3" one | 1 |
| iPad 13" App Preview | `preview/<locale>/ipad-13.mp4` | 1200 × 1600, a constant 30 fps, AAC | 1 |

**One slot in App Store Connect, one folder and one preview file**, named after
it: `iphone-6.3` goes into *iPhone 6.1" or 6.3" displays* (the one iPhone slot
Connect requires), `iphone-6.9` into *iPhone 6.9" display* (Apple's rules
contradict each other on whether it is required, so it is filled; see
README.md), `ipad-13` into *iPad 13" display* (required, because the app is
universal), `iphone-duo` into *iPhone Duo*.

**Upload the composed set, not the plain one** — same file names, same order,
they differ only in the wrapper. The plain set is what the game actually looks
like and is worth keeping to diff against; the composed set is where "no ads, no
Wi-Fi" gets said out loud.

Every simulator shoots its slot size natively, so no screenshot is scaled or
cropped, and the script fails rather than continuing if a size is off. The
status bar reads 9:41 with full signal and a full battery that is not charging;
the Czech set reads 09:41, as a Czech iPhone writes it.

## iPhone Duo

Optional until April 2027, required after that for apps built with the iOS 27.1
SDK or later — this one is. The slot takes the inner display upright, 2007 ×
2853, and a listing that has it gets the *Made for iPhone Duo* badge.

**The run needs you once per language.** The Duo boots folded and nothing on
the command line unfolds it (simctl has no hinge — checked again for this
project). Run `Tools/AppStoreMedia/media.sh screenshots duo`; it asks you to
*Unfold the iPhone Duo in DeviceHub and turn it upright*, waits until the inner
display is lit and upright, and goes on by itself — twice, because the language
switch is a reboot and folds it again. Then run `compose.sh`, which frames the
Duo set without a Dynamic Island. The Duo's preview needs nothing: the 886 ×
1920 iPhone file is the only upright size Connect takes for it (Apple's [App
preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications),
checked in November 2026), so it is copied under the Duo's name.

The Duo set was first shot on 5 November 2026 and every pose holds on the inner
display: the game lays itself out from the space it has, never from the device
(the board and the wheel side by side once the screen is wider than it is
tall). The menus (02-journey, 03-daily, 08-trophies) keep to their reading
width and leave the lower part of the tall canvas empty; that is the app as it
is on the device, but look at the ten shots again before uploading them.

## How the poses work

Nothing here is mocked up. Every shot is the game reaching a screen through its
own code, driven by `#if DEBUG` launch arguments read in
[`DebugLaunch.swift`](../crosswords/App/DebugLaunch.swift) and
`GameController.applyDebugArguments` (plus small hooks in HomeView, GameView,
DailyView, TrophiesView and the wheel). None of it reaches an App Store build.
The words on the boards are the puzzles' own, in each language.

- **`-debugProgress N`** replaces the player's data with a believable history —
  the words of the first N levels, a crown on two levels in three, six weeks of
  daily puzzles ending in a 12-day streak with a missed day every week or so,
  and the achievements all that earned, claimed except the latest tier of two
  (so the Trophies badge and a Claim button have something to show). It is
  seeded from the puzzles themselves, so every launch writes the same history,
  and because it replaces rather than adds, the order of the poses does not
  matter. N also picks the landscape: level N + 1 is in chapter N / 12, whose
  landscape is (N / 12) mod 24.
- **`-debugRoute`** opens a screen: `level` (the next level of the journey),
  `daily` (today's puzzle), or one of the menus — `journey`, `chapter` (the
  current chapter's levels), `dailyHub`, `lexicon`, `trophies` or `settings`.
  Without it the title screen stays. **`-debugLanguage en`** (or `cs`) sets the
  puzzle language, and **`-debugSelect N`** connects the wheel's first N letters.
- **`-debugLeave N`** finds all but N of the crossword's words, whatever the
  puzzle's size, which differs between the languages; `-debugSolve 99` finds all
  of them, and the level-complete card comes up the way it does in play.
- **`-debugSpell longest`** (or `next`, or a word) puts a word on the wheel
  mid-swipe, and **`-debugFinger`** draws the finger on its last letter.
- **`-debugBonusLive WORD`** finds a bonus word the way a player does — the gift
  fills, and with **`-debugBonusTip`** (which, like the gift, coins and streak
  below, changes the history `-debugProgress` writes, and does nothing without
  it) the game's own one-time tip about the gift comes up.
- **`-debugSpotlight`** arms Spotlight, so the hidden squares glow.
- **`-debugElapsed`** puts a believable time on the level-complete card.
- **`-debugCalendarBack 1`** turns the daily calendar back a month: the script
  passes it before the 7th, when most of the seeded streak sits on the
  previous month's page.
- **`-debugMute`** keeps the run from playing every letter through the Mac's
  speakers.
- **`-debugGift N`** fills the bonus gift with N words (the poses use 5, and the
  App Preview 9, so its bonus word opens the gift), and **`-debugCoins N`** sets
  the coin balance (485 otherwise). Both, like `-debugStreak` and
  `-debugBonusTip`, only work together with `-debugProgress`.
- **`-debugStreak N`** sets the seeded daily streak that ends yesterday (12
  otherwise; 0 for none).
- **`-debugHints N`** reveals N letters with the Light Bulb, without paying, and
  **`-debugBonusWords A,B`** finds those bonus words in the puzzle only: the gift
  does not fill, and no toast or tip comes up.
- **`-debugDemo N`** plays the last N words by itself, then the next level's
  first: the App Preview (see below). **`-debugDemoBonus WORD`** swipes a bonus
  word on the way, **`-debugDemoLead S`** waits S seconds before the first swipe
  (1.5 otherwise) and **`-debugDemoHold S`** keeps the level-complete card up for
  S seconds (3.4 otherwise).

Every pose drops a marker file when it is set up (`Documents/shot-ready`): a game
once its board is, a menu once its screen has appeared and the push or sheet that
brought it has had time to finish. The script waits for it rather than for a
guessed number of seconds; what follows is a short fixed settle per shot, for the
card's entrance and the like.
The wheel's letter order is shuffled on every launch, as in the game, so two
runs differ in that alone.

## The ten shots, in order

The order matters more than the count: search results show the first three, and
most people never scroll past them — so those three carry the three reasons to
pick this word game over the others: nothing in the way (ads are the complaint
in 64–72 % of the bad reviews of the genre's biggest games), a whole journey of
content, and a reason to come back tomorrow. The research behind the captions is
in [alternatives.md](alternatives.md).

| # | Shot | Caption (EN / CS) | What it shows |
|---|---|---|---|
| 1 | `01-play` | No ads. No Wi-Fi. Just words. / Česká slova. Žádné reklamy. | The hero. Level 102 in the Northern Lights, half the crossword found, the longest word (SAMPLE / NAJÍST) spelled across the wheel with the finger on its last letter. In Czech it leads with what no big competitor has — Czech words; *offline* is in the subtitle. |
| 2 | `02-journey` | 1,200 levels through 24 landscapes / 1 200 úrovní ve 24 krajinách | The journey: a column of chapter cards, each its own drawn landscape, the finished ones crowned and the ones ahead locked. |
| 3 | `03-daily` | A new crossword every day / Každý den nová křížovka | The daily puzzle: today's card, a 12-day streak, and a month of solved days in the calendar. |
| 4 | `04-calm` | Nothing to buy. No rush. / Nic ke koupi, nikam nespěcháš | A bright daytime level (Coral Lagoon) with nothing on screen but the game. Answers the second complaint after ads — coin shops — and the timed modes reviewers ask to switch off. |
| 5 | `05-hints` | Hints you earn, never buy / Nápovědy za hraní, ne za peníze | Spotlight armed in the Frozen Fjord: the hidden squares glow, "Tap an empty square to reveal it". |
| 6 | `06-win` | Finish a chapter, travel on / Dokonči kapitolu, putuj dál | The last level of a chapter just solved without hints: the crown, "Chapter complete! A new landscape awaits.", the coins counted up. |
| 7 | `07-bonus` | Every real word counts / Počítá se každé skutečné slovo | A night level in the Firefly Forest (its first visit, level 136): a bonus word just found (END / MLOK) with the game's own tip "Bonus word! Collect 10 to open a gift.", and another (FINDER / KOZLEM) on the wheel — in both languages one that uses every letter of the wheel and still isn't in the crossword (beside the crossword's FRIEND / ZLOMEK). Answers "valid words not accepted", the dictionary complaint. |
| 8 | `08-trophies` | 12 achievements, bronze to platinum / 12 úspěchů od bronzu po platinu | The achievements, with tiers, progress bars and two to claim. |
| 9 | `09-chapter` | Solve without hints, earn a crown / Bez nápověd získáš korunku | A chapter's twelve levels over its landscape (Autumn Valley): crowns, checks, the current level and the locked ones. |
| 10 | `10-home` | A journey through words / Putování krajinou slov | The title screen, with the game's own tagline as the caption. |

Poses that exist and are not in the set: the Lexicon (`-debugRoute lexicon` — a
plain list, and definitions come from dictionaries a simulator does not have),
Statistics (`-debugRoute trophies -debugTab statistics`), Settings, a chapter
start on any landscape (`-debugProgress` with any N) and the bonus words sheet
(`-debugSheet bonus`), which is translucent glass over the landscape and reads
poorly in a thumbnail.

On the iPad the menus sit in a 560-point column in the middle of a lot of space —
the app's own layout at that size — which is why the game shots lead the set
there too.

## Composition

`Tools/AppStoreMedia/compose.sh` builds the shot that actually goes up: a flat
saturated colour, a heading in white across the top, and the screenshot in a
device frame below it running off the bottom edge — but only as far as the strip
under the game's last row, so on the iPad and the Duo, whose canvases are
squarer, the device is drawn a little narrower rather than losing the gift and
the hints. The layout and every other proportion are J-Notes' and Sudoku's, so
the developer's listings read as one family; the colours are this game's — each shot gets the accent of the landscape
inside it, a shade deeper where white type needs it, and the menu shots the
colour that leads on them (the daily streak's flame, the trophies' gold). No two
neighbours share a hue, and the first three — aurora green, indigo, flame orange
— are the three most unlike.

The heading is SF Pro Rounded, which is what the game itself is set in,
thickened with a stroke of its own colour (ImageMagick instantiates the variable
font at Regular); it shrinks itself to fit the width and the band above the
device, which the longer Czech lines need. The Dynamic Island is painted on,
because simulator screenshots do not have one — on the shots that already show
it, the painted one sits exactly over it. The captions live in `en_caption` and
`cs_caption` in that script, two lines each, broken by hand, and the colours in
`colour_for` beside them.

## App Preview

**One continuous take of a game being played**, cut from a simulator recording:
the last level of the Cherry Blossom chapter, part of it already found; the rest
swiped word by word at a person's pace by a finger drawn on the wheel; a bonus
word on the way (SLIM / KOUPAT) that opens the bonus gift (+25); the last and
longest word (SIMPLE / POKUTA); the level-complete card with the crown, "Chapter
complete!", the chapter reward and the confetti; then "Next level", the Northern
Lights sliding in, and one more word found under the aurora. That is the whole
game in twenty seconds: swiping, the crossword filling in, bonus words, rewards
and the journey from one landscape to the next. The game is `-debugDemo`
(`GameController.playDemo`), and it plays through the same moves a player makes —
`connect`, `submitSelection`, `advance`.

A preview plays in search results in place of the first screenshot, muted, so the
take is built to read without sound: the finger shows what the hands are doing,
and the words appear in the bubble above the wheel as they are spelled.

Measured on the 6.3-inch iPhone previews (the 6.9-inch and Duo slots take the
same file) of the run of 5 November 2026, in seconds into the preview, from
frames half a second apart (the iPad's take, not measured this time, has run
half a second to a second ahead):

| | English | Czech |
|---|---|---|
| Cut, from the recording (moved back by the recorder's delay) | 2.0 → 20.5 s, 18.5 s long | 2.0 → 20.5 s, 18.5 s long |
| First swipe | 0.5 | 1 |
| Bonus word, gift opens (+25) | 6 | 6 |
| Level-complete card | 12 | 10.5 |
| Next landscape slides in | 15.5 | 14 |
| Its first word found | 17 | 15.5 |

The English take swipes SLIP MILES SLIM SMILE SIMPLE, 24 letters with the bonus
word; the Czech one VEN LANO NALEVO VLNA NOVELA, 23, and ends three seconds after
its last word. The packs regenerated after the generator fixes of 5 November
2026 kept the English puzzle but gave the Czech one new words: TAK AUTO KOUPAT
KOPAT POKUTA, 24 letters as in English, so its take should keep the English
timing. It has not been shot yet: the Czech preview, and the Czech screenshots,
whose puzzles changed too, need a new run of `media.sh` before the next upload,
and the cut a check against the new take. Each cut ends a
second and a half to two after the last word on purpose: a take drifts by up to a
second from run to run (the first English cut, with one word more, once ended
with its last word half-spelled), so the cut does not end on the action. Both
are inside Apple's 15–30 s.

How the timing is kept honest, because most of it does not fail loudly when it
drifts:

- **The take is measured from the ready marker.** The app drops it the moment the
  board is up and starts playing `-debugDemoLead` (2.5) seconds later; recording
  starts as soon as the script sees the marker. The recorder usually comes up
  0.1 s later, and the script sees the marker up to 0.2 s after it is written;
  on a busy Mac the recorder has taken anything up to 1.5 s. So the script
  measures, on every take, how long after the marker's own file time the
  recorder came up (0.2 s on average) and moves the cut back by the difference:
  the preview opens on the same moment either way, and only a start slower than
  2.0 s is refused.
- **A take can stall, and the gap check catches it.** `assemble` runs
  [`gaps.swift`](../Tools/AppStoreMedia/gaps.swift) over every take before
  cutting it, with a limit of 0.5 s: the landscapes never stop drifting, so a good
  take is never still for long (0.06–0.40 s measured across the takes so far).
- **The rehearsal.** The first iPad take stood still for a second as the last
  word went in: SwiftUI compiled the level-complete card's Metal pipelines (its
  blurred material, the confetti) on the main thread, the first time they were
  drawn — profiled with `sample` — and a clean install starts with an empty shader
  cache. So `record` plays the demo through once, unrecorded, before the take;
  the pipelines are in the app's Caches by the time the camera rolls. It happens
  once per install, and the simulator runs Metal through the Mac's GPU, which
  makes it far slower than on a device — but whether the first level-complete
  card hitches on a real iPad has not been checked, and is worth a look.
- **Debug, but optimised.** The build is Debug, because the poses are `#if
  DEBUG` code, and `SWIFT_OPTIMIZATION_LEVEL=-O`, because an unoptimised build is
  not the game anyone plays.
- **The rest is Sudoku's.** [`video.swift`](../Tools/AppStoreMedia/video.swift)
  cuts to ProRes at 30 fps and holds the last frame if a take ends early;
  [`conform.swift`](../Tools/AppStoreMedia/conform.swift) encodes H.264 High 4.0
  at 11.5 Mbit/s, all-intra, puts every frame on an exact 30 fps grid and fails
  unless the written file holds exactly that; `assemble` fails if a preview is
  not as long as its cut. Nothing may reach into the last two seconds of a
  recording — the tail of a simulator recording is not reliably decodable.

Check it after any change to the demo, its pacing or the animations:

```bash
swift Tools/AppStoreMedia/frames.swift AppStore/preview/en-US/iphone-6.3.mp4 \
    /tmp/frames 0.2 1.5 4.5 7.5 11.5 13 15.5 16.8
magick /tmp/frames/*.png -resize 240x +append /tmp/sheet.png
```

What the last run produced:

```
886×1920   18.50s  555 frames at 30 fps  H.264 High 4.0 11.6 Mbit/s  AAC 48 kHz stereo 254 kbit/s  26.1 MB  (en-US, still at most 0.24 s)
886×1920   18.50s  555 frames at 30 fps  H.264 High 4.0 11.5 Mbit/s  AAC 48 kHz stereo 254 kbit/s  25.9 MB  (cs, 0.34 s)
1200×1600  18.50s  555 frames at 30 fps  H.264 High 4.0 11.5 Mbit/s  AAC 48 kHz stereo 254 kbit/s  26.0 MB  (en-US, 0.26 s)
1200×1600  18.50s  555 frames at 30 fps  H.264 High 4.0 11.5 Mbit/s  AAC 48 kHz stereo 254 kbit/s  26.0 MB  (cs, 0.07 s)
```

**The music is synthesised, because it has to be.** App Store Connect requires
stereo AAC at 256 kbps on a preview, and silence does not satisfy it. The game
ships no audio files — its sounds are made on the device — so
[`music.py`](../Tools/AppStoreMedia/music.py) writes the bed: the felt piano of
the chess and Sudoku previews, over IV–V–iii–vi in F major at 72 BPM, a
progression that never lands on its home chord — travelling rather than
arriving — with a few pentatonic notes wandering above it. `PREVIEW_GAIN=…`
changes how loud it sits, `PREVIEW_MUSIC=path.wav` replaces it. Check that the
last line `conform.swift` prints says about 255 kbit/s of audio, because a
preview without usable audio is otherwise only reported a whole upload later.
