# Wordwander

A calm, offline letter-wheel crossword game for iPhone and iPad, built with SwiftUI.
Swipe across the letters on the wheel to spell words and fill the crossword, travelling through
24 hand-tuned, procedurally drawn landscapes.

- **English and Czech.** The UI and the puzzles follow the device language: Czech on Czech
  devices, English everywhere else. Players can switch the puzzle language in Settings; each
  language keeps its own journey, daily puzzle and lexicon, while the daily reward and the streak
  count each day once, whichever language it was solved in.
- **Fully offline.** Every puzzle and word list ships inside the app. No network, accounts,
  analytics, ads or purchases. Sounds are synthesised on the device, so there are no audio assets.

## Features

| | |
|---|---|
| Journey | 1,200 levels per language in 100 chapters of 12. Difficulty ramps from 3-letter to 7-letter wheels in a saw-tooth curve: each chapter ends with its finale, the chapter's largest wheel with as many words as any of its levels, and from the seventh chapter on it also opens gently. |
| Daily puzzle | A new puzzle every day (400-puzzle rotation), streaks, a calendar of solved days and a coin bonus every 7 days in a row. |
| Bonus words | Every real word the wheel can spell counts. Ten bonus words open a gift worth coins. Replaying a finished level is just for fun: no coins, gifts or statistics, though solving it without hints still earns its crown. |
| Hints | Light Bulb (next letter), Spotlight (any chosen square) and Starburst (five scattered letters), unlocked progressively with free uses to try them. |
| Achievements | 12 achievements × 4 tiers (bronze → platinum) with coin rewards, plus lifetime statistics. |
| Lexicon | Every word ever found, searchable, with definitions from the on-device system dictionaries (for Czech, the Czech–English one: iOS has no Czech dictionary of its own). |
| Reminders | Optional local notification for the daily puzzle, scheduled eight weeks ahead and skipped on days already solved; tapping it opens the puzzle. |
| Accessibility | Letters tapped one by one with submit/clear controls instead of swiped (with VoiceOver and Switch Control, or turned on in Settings for Voice Control or an unsteady hand), a spoken summary of the grid, VoiceOver-selectable squares for Spotlight, Reduce Motion throughout, Dynamic Type in menus (rows stack at the accessibility sizes), and colours that keep white text readable (WCAG contrast). |

## Project layout

```
crosswords/                 App target (folder is synchronised with the Xcode project)
  App/                      Entry point, AppModel (shared state), debug launch arguments
  Core/                     Pure game model: puzzles, board, level rules, player data,
                            economy, achievements, daily schedule, landscapes
  Services/                 Persistence, synthesised sound, haptics, reminders
  UI/                       SwiftUI screens: Home, Game, Journey, Daily, Lexicon, Trophies, Settings
  Resources/Puzzles/        Generated puzzle packs (puzzles-en.json, puzzles-cs.json)
  Resources/Localizable.xcstrings   English + Czech strings (with Czech plural forms)
crosswordsTests/            Swift Testing unit tests, incl. validation of every bundled puzzle
crosswordsUITests/          XCTest UI tests of the menu navigation and of spelling by tapping
Config/                     Info.plist additions (single window on iPad)
Tools/PuzzleGenerator/      Python generator for the puzzle packs
Tools/IconGenerator/        Renders the app icon variants (light, dark, tinted)
Tools/AppStoreMedia/        Shoots the App Store screenshots and App Preview from the simulators
AppStore/                   App Store listing texts, research, review notes and privacy policy
```

Key types:

- `LevelSession` – the rules of one puzzle (found words, hint reveals, completion, save snapshot).
- `GameController` – connects a session to rewards, sounds, haptics and saving.
- `PlayerStore` – loads and debounces writes of `PlayerData` to Application Support.
- `SceneryView` – draws a landscape (sky, sun/moon, aurora, terrain, trees, particles) in a `Canvas`.

## Building and testing

Open `crosswords.xcodeproj` in Xcode 27 and run the `crosswords` scheme (iOS 26 or later), or:

```sh
xcodebuild test -scheme crosswords -destination 'platform=iOS Simulator,name=iPhone 17'
```

The shared `crosswords` scheme runs both the unit tests and the UI tests. The project builds in
the Swift 6 language mode with main-actor default isolation.

Debug builds understand a few launch arguments for QA and screenshots:

```
-debugProgress 30        replace the player with one who has completed 30 levels (and six weeks of daily puzzles)
-debugRoute level        open the next level (also: daily, journey, chapter, dailyHub, lexicon, trophies, settings)
-debugSolve 3            solve the first 3 words of the opened puzzle
-debugLeave 3            solve all but the last 3 words
-debugSelect 4           pre-select 4 letters on the wheel
-debugSpell longest      spell a word mid-swipe (also: next, or a word); -debugFinger 1 draws the finger
-debugBonusLive WORD     find a bonus word as a player would (-debugBonusTip 1 shows the gift's tip)
-debugDemo 5             play the last 5 words by itself, then the next level's first (the App Preview)
-debugLanguage cs        force the puzzle language
-debugMute 1             turn the sound effects off
```

The full list, and how the App Store screenshots and previews are made from them, is in
[AppStore/screenshots.md](AppStore/screenshots.md).

## App Store

[AppStore/](AppStore/) holds the listing: name, subtitle, keywords, promotional text and
description in English and Czech, the reasoning and competitor research behind them
([alternatives.md](AppStore/alternatives.md)), the notes for App Review and the privacy policy.
The screenshots and App Preview videos are generated, not drawn:

```sh
Tools/AppStoreMedia/media.sh screenshots iphone   # also: ipad, duo; or `video`
Tools/AppStoreMedia/compose.sh                    # captions and device frames
```

## Regenerating the puzzles

The packs are deterministic for a given seed and source data: `fetch_sources.sh` pins every word
list to a commit and checks its SHA-256 against `sources.sha256`, which `generate.py` checks again
before it starts (a `.sources` folder fetched before a list was pinned would otherwise build other
packs without a word), `requirements.txt` pins every Python package (wordfreq,
whose data decides which words exist, among them) to a version and its hashes, and the generator
never depends on the (randomised) iteration order of Python sets.

```sh
cd Tools/PuzzleGenerator
./fetch_sources.sh
python3.9 -m venv .venv && .venv/bin/pip install -r requirements.txt   # the packs are made with Python 3.9
.venv/bin/python generate.py --lang en --out ../../crosswords/Resources/Puzzles
.venv/bin/python generate.py --lang cs --out ../../crosswords/Resources/Puzzles
.venv/bin/python preview.py ../../crosswords/Resources/Puzzles/puzzles-cs.json 0 100 d0   # ASCII preview
```

How it works:

1. **Lexicon.** *Valid* words (accepted as bonus words) and *target* words (allowed in the grid)
   are built per language. English uses ENABLE plus a curated list of modern words, ranked by
   `wordfreq`. Czech uses words attested in `wordfreq`, spell-checked with Hunspell; grid words are
   restricted to dictionary base forms so that stray inflections do not appear as answers (the
   forms Hunspell lists one by one, such as "bojíme", "navedl" or the transgressive "sleduje", are
   told apart by their flags, and entries that read as a form of a commoner word, such as "řad"
   of "řada", are excluded by hand, as are comparatives such as "menší", "líp" or "dál", present
   participles such as "ležící", the feminine, neuter and plural forms of pronouns and numerals
   such as "tato", "ona" or "dvě", and archaic forms such as "msta"). Five irregular plurals a
   player expects as words of their own are kept on purpose ("lidé", "děti", "ruce", "oči",
   "uši"), and where Czech has two forms of a word ("archiv", "archív"; "brzy", "brzo") only the
   standard or commoner one is a grid word, so a grid never offers both. Nor does a grid hold two
   words that the dictionary reads as forms of one word, as many entries are also a form of
   another ("pilota", a pile, and the genitive of "pilot"; "masa" and "maso"; "šál" and "šála"),
   nor a verb and the adjective of its passive participle or its verbal noun, which the dictionary
   lists as entries of their own ("skrýt" and "skrytý", "dát" and "daný", "dožít" and "dožití",
   "číst" and "čtení": each is traced through the participle's short form, "skryt", "dán", "dožit"
   or "čten").
   `curation.py` holds the hand-made block and exclusion lists; Czech vulgar stems are blocked as
   prefixes, including their verb prefixes and the consonant changes of their inflections ("negr",
   "negři"), and so is every word the Czech dictionary reads as a form of a blocked entry, of an
   entry with a blocked prefix ("otročtí" of "otrocký") or of one it flags as vulgar itself
   ("blbče" of "blbec", "šlapce" of "šlapka", any form of "srát");
   the English dictionary's vulgar entries are blocked too, and English blocked words with their
   inflections (a dropped e, a doubled consonant,
   y → i, two steps deep: "porny", "pornier"), the plurals of those ("nudists"), and the words
   that a prefix or a suffix makes of them ("unsexy", "enslave", "bedamn", "sexless"), where what
   is left is a word of the list itself (so that "entity" is not read as "en-" + "tity"). Slurs and
   obscenities are not accepted at all; that is a list, so a new pack is worth reading through
   for any it missed. Insults, nudity, crude words and grim subjects (death and burial, killing,
   weapons, poisons and explosives, drugs, tobacco and spirits, gambling, grave illness) never
   appear in the grid in either language, though they still count as bonus words (but for the
   gravest, such as "murder", "suicide", "rape" or "heroin", which are blocked); nor do names,
   places and nationalities, abbreviations and prefixes, interjections, contractions without
   their apostrophe, and British or archaic words in the American English list. Every grid word
   of both lists was read through for these (November 2026, and again for the words each change
   of the lists brought in), and so was every word of the shipped packs, bonus words included; a
   change to the sources, the lists or the thresholds brings in words nobody has read yet.
   Abbreviations and symbols the Czech dictionary accepts in running text ("cca", "dkg", "zool")
   are not accepted at all (`NOT_WORDS`). The hand-made lists are normalised to NFC as they are
   read, so an entry pasted in decomposed form still matches. `PuzzlePackTests` re-checks the
   shipped packs.
2. **Planning.** For each level a seed word sets the wheel letters; grid words are chosen by
   frequency while penalising words already used. Words in one of the ten puzzles either side come
   last: a three-letter one only fills a grid that would otherwise fall short, a longer one only
   when the wheel has nothing fresher (the spare words of the puzzles planned but not laid out yet
   count too, as the layout may still place them). A word already in twelve puzzles only fills a
   grid that would otherwise fall short, and one in thirty is not used again, as a seed word
   neither (that binds on the commonest short Czech words), so vocabulary stays fresh across
   levels. Such words are taken only once the wheel's other words have run out, and the layout
   gives them up first. A puzzle doesn't come back either, however far back it was: of an earlier
   puzzle whose words a wheel still spells half of or more, a grid takes at most two unless it
   needs more to reach its minimum ("NOW, OWN, WON" of the first level no longer return
   together), and a wheel that would need more is passed over whenever another of the seeds
   looked at doesn't. Only the words a grid needs count: a plan takes one word more than its
   minimum, should the layout drop one, and the layout gives that spare up again when it can. A
   wheel that would need a fourth such word (four of eight shared, say) is passed over for rarer
   words that do with three, and taken before a grid is made smaller. That binds on the Czech
   daily puzzles, whose eight-word minimum the late wheels reach only just. A round plans every
   puzzle before any is laid out, and a layout may place a spare word in place of a planned one,
   so once the grids are laid out the two rules are
   applied again in pack order (the journey, then the daily rotation), at the grids' final sizes:
   a grid above its minimum gives up a word already in twelve earlier puzzles, and a third word of
   an earlier puzzle it would mostly repeat (when such a word holds the grid together, the rest is
   laid out again without it, if that still makes the minimum). A plan also looks at more seeds,
   as it does for an echo, while its best one would put a word of a nearby puzzle in the grid, and
   a wheel that would need more than two such words of an earlier puzzle to reach its minimum
   (five of eight, say) is passed over for rarer words and then a smaller grid, then for the best
   wheel looked at that does without, even one that puts words of nearby puzzles in its grid, and
   is taken only when none does: three Czech daily puzzles have seven words rather than
   repeat most of one. The daily rotation counts as a circle, its last puzzles next to its first.
   Czech daily puzzles use seven-letter wheels: the journey, planned first, takes the six-letter
   wheels that spell enough Czech base forms.
   Each chapter's finale then gets the chapter's largest grid of its wheel size, unless the move
   would bring a word next to a level that has it (a repeat it only keeps is allowed), and any other
   level that still has more words (one with a smaller wheel, one of the two gentle openers, or one
   whose move was passed over) gives up its least valuable ones, which stay bonus words, or has its
   most valuable ones laid out again when every word it could give up holds its grid together: the
   finale is the chapter's largest wheel and has the most words (others may have as many). So that
   it stays that way, a finale keeps as many words as the largest other level of its chapter when
   the rules are applied again in pack order, even a word already in twelve earlier puzzles.
3. **Layout.** A randomised greedy search places the words as a connected crossword with no
   accidental adjacent letters, scoring crossings, compactness and aspect ratio.
4. **Validation.** Every level is checked before writing, and again by the unit tests.

## Word data and licences

The word sources are credited in the app (Settings › Acknowledgements):

- ENABLE word list – public domain.
- wordfreq – frequency data under CC BY-SA 4.0 (attribution in the app, which names its author
  as Robyn Speer: wordfreq's NOTICE.md asks for that name and no other). Its terms also ask
  everything derived from it to credit the SUBTLEX word lists (Marc Brysbaert et al., freely
  available data) and OpenSubtitles, which the app does next to wordfreq.
- Hunspell dictionaries (en_US / SCOWL, cs_CZ) – used only at build time as a spelling check;
  the shipped Czech word lists come from wordfreq. The Czech dictionary is GPL-licensed, but
  nothing of it ships: the generator only asks it whether a word is spelled correctly and whether
  it is a base form, as a spell checker run over a text would, and the GPL does not reach the
  output of such a check.
- List of Dirty, Naughty, Obscene and Otherwise Bad Words – CC BY 4.0, used to keep puzzles family friendly.

The puzzle packs (`crosswords/Resources/Puzzles/puzzles-*.json`) are adapted from wordfreq's data
(filtered and combined with the sources above), so under wordfreq's ShareAlike term they are
licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/), as
[LICENSE.md](LICENSE.md) states with their sources and changes. The in-app acknowledgement says
the same. That licence covers the packs only, not the app's code.

CC BY-SA 4.0 also forbids applying technological measures that restrict the licensed rights
(section 2(a)(5)(C)), and the App Store delivers every app under FairPlay DRM. The packs are
published without DRM in this public repository, so nobody's use of them is restricted; that is
the usual way to meet the term, and the way other apps with CC BY-SA content (Wikipedia's, for
one) ship on the App Store.

The same section forbids imposing additional terms that restrict the licensed rights, and
Apple's standard licence agreement (EULA), which every App Store app comes with unless it has
its own, forbids copying or modifying the app. So the app gets a licence agreement of its own:
Apple's standard text with a clause stating that the puzzle packs stay under CC BY-SA 4.0 and
that nothing in the agreement restricts them. The clause, and where it goes in App Store
Connect, are in [AppStore/licence-agreement.md](AppStore/licence-agreement.md).

So every term of the sources is met, and it stays that way as long as:

- **the repository stays public**, with the packs and `LICENSE.md` in it;
- **the credits stay in the app** (Settings › Acknowledgements) and in `LICENSE.md`, updated if a
  source is added;
- **the packs stay under CC BY-SA 4.0** whenever they are changed or regenerated;
- **the app's licence agreement keeps the clause** in App Store Connect.

None of this depends on the app being free: the licences ask the same of a paid app.
