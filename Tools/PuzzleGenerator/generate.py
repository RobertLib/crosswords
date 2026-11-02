#!/usr/bin/env python3
"""
Puzzle pack generator for the Crosswords app.

Builds a curated lexicon for a language, then generates:
  * a difficulty-ramped sequence of letter-wheel crossword levels, and
  * a pool of daily puzzles,
and writes them as a single JSON pack consumed by the app.

Usage:
    ./fetch_sources.sh
    python3.9 -m venv .venv && .venv/bin/pip install -r requirements.txt   # see PYTHON_VERSION
    .venv/bin/python generate.py --lang en --out ../../crosswords/Resources/Puzzles
    .venv/bin/python generate.py --lang cs --out ../../crosswords/Resources/Puzzles

The output is deterministic for a given --seed and source data: nothing depends on the
iteration order of sets, which Python randomises per process.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import multiprocessing as mp
import random
import re
import sys
import time
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from spylls.hunspell import Dictionary
from wordfreq import iter_wordlist, zipf_frequency

import curation

# The packs are reproducible only with the interpreter they were made with: `random` and the
# pinned packages are what decide every puzzle (see requirements.txt).
PYTHON_VERSION = (3, 9)

FORMAT_VERSION = 1
LEVELS_PER_CHAPTER = 12
MIN_LEN, MAX_LEN = 3, 7

ALPHABETS = {
    "en": "abcdefghijklmnopqrstuvwxyz",
    "cs": "aábcčdďeéěfghiíjklmnňoópqrřsštťuúůvwxyýzž",
}

# ---------------------------------------------------------------------------
# Lexicon
# ---------------------------------------------------------------------------

@dataclass
class Lexicon:
    lang: str
    valid: set[str]                 # every accepted word (bonus words)
    targets: dict[str, float]       # grid-worthy words -> zipf frequency
    # Czech: grid word -> the dictionary entries it reads as a form of, itself included ("pilota"
    # -> {"pilota", "pilot"}, being an entry and the genitive of "pilot").
    entries: dict[str, frozenset] = field(default_factory=dict)

    def same_word(self, a: str, b: str) -> bool:
        """Whether two grid words read as forms of one word ("pilot" and "pilota", "šál" and
        "šála", "maso" and "masa"): a grid that had both would look like it offers an inflection."""
        return a != b and bool(self.entries.get(a, frozenset((a,))) & self.entries.get(b, frozenset((b,))))


def nfc(s: str) -> str:
    return unicodedata.normalize("NFC", s)


# The hand-made lists, in the normal form of the words they are compared with: an entry typed
# or pasted decomposed ("a" + combining acute, as macOS file names are) would match nothing.
def _nfc_sets(lists):
    return {lang: {nfc(w) for w in words} for lang, words in lists.items()}


EXTRA_BLOCKED = _nfc_sets(curation.EXTRA_BLOCKED)
NOT_BLOCKED = _nfc_sets(curation.NOT_BLOCKED)
NOT_TARGET = _nfc_sets(curation.NOT_TARGET)
NOT_WORDS = _nfc_sets(curation.NOT_WORDS)
BLOCKED_PREFIXES = {lang: tuple(nfc(p) for p in prefixes) for lang, prefixes in curation.BLOCKED_PREFIXES.items()}
CS_BLOCKED_FORMS = re.compile(nfc(curation.CS_BLOCKED_FORMS.pattern), curation.CS_BLOCKED_FORMS.flags)
CS_FLAGLESS_KEEP = {nfc(w) for w in curation.CS_FLAGLESS_KEEP}
EN_INFORMAL = set(curation.EN_INFORMAL)
EN_MODERN = set(curation.EN_MODERN)
EN_NOT_INFLECTIONS = set(curation.EN_NOT_INFLECTIONS)


def load_blocklist(path: Path, lang: str) -> set[str]:
    words = {nfc(line.strip().lower()) for line in path.read_text(encoding="utf-8").splitlines()}
    words = {w for w in words if w and " " not in w}
    return words | EXTRA_BLOCKED[lang]


def en_stems(word: str, deep: bool = True):
    """The base forms an English word could be inflected or derived from. A y-form is followed one
    step further, since it is usually derived itself ("pornier" → "porny" → "porn")."""
    for suffix in ("s", "es", "ed", "ing", "er", "ers", "est", "y", "ly", "ish", "ism", "ist", "ful"):
        if word.endswith(suffix):
            stem = word[: -len(suffix)]
            yield stem
            if suffix[0] in "aeiouy":
                yield stem + "e"                    # rape → raping, nude → nudism
                if len(stem) > 2 and stem[-1] == stem[-2]:
                    yield stem[:-1]                 # crap → crappy, slut → slutty
    for suffix in ("d", "r", "rs", "st"):
        if word.endswith("e" + suffix):
            yield word[: -len(suffix)]              # rape → raper, nude → nuder
    for suffix in ("ies", "ied", "ier", "iest", "ily"):
        if word.endswith(suffix):
            stem = word[: -len(suffix)] + "y"
            yield stem                              # orgy → orgies, sexy → sexier
            if deep:
                yield from en_stems(stem, deep=False)


# Prefixes and derivational suffixes that make a word of a blocked English word ("unsexy",
# "antisex", "enslave", "bedamn", "deboner"; "sexless", "anality"). They are taken off only where
# what is left is a word of the list itself, so that "entity" is not read as "en-" + "tity".
EN_PREFIXES = ("anti", "be", "de", "dis", "em", "en", "mis", "non", "over", "pre", "re", "un", "under")
EN_DERIVATIONS = ("less", "ity", "ness")


def is_blocked(word: str, blocked: set[str], lang: str, plural: bool = False, known: frozenset = frozenset()) -> bool:
    """Whether a word is blocked. `known` is the English word list, which the prefixes and
    derivational suffixes of a blocked word are traced through."""
    if word in NOT_BLOCKED[lang]:
        return False
    if word in blocked:
        return True
    if lang == "en" and word not in EN_NOT_INFLECTIONS:
        stems = set(en_stems(word))
        # An allowed look-alike's own inflections are allowed too ("cockers" of "cocker").
        if not stems & EN_NOT_INFLECTIONS and stems & blocked:
            return True
        # The plural of a word blocked as a derivative, which the stems above don't reach:
        # "nudists" of "nudist" of "nude", "sexisms" of "sexism" of "sex", "enslaves" of "enslave".
        if not plural and word.endswith("s") and not word.endswith("ss"):
            if any(is_blocked(word[: -len(ending)], blocked, lang, plural=True, known=known)
                   for ending in ("s", "es") if word.endswith(ending)):
                return True
        if known:
            parts = [word[len(prefix):] for prefix in EN_PREFIXES if word.startswith(prefix)]
            parts += [word[: -len(suffix)] for suffix in EN_DERIVATIONS if word.endswith(suffix)]
            if any(len(part) >= 3 and part in known and is_blocked(part, blocked, lang) for part in parts):
                return True
    if lang == "cs" and CS_BLOCKED_FORMS.fullmatch(word):
        return True
    return word.startswith(BLOCKED_PREFIXES[lang]) if BLOCKED_PREFIXES[lang] else False


def en_not_target(word: str) -> bool:
    """An excluded English word, or a plain plural of one ("pics", "gypsies"), but not a longer
    word that merely ends like one ("pass" is not a plural of "pas", nor "doses" of "dos"). Other
    forms are listed by hand ("fatter", "ugliest"): the excluded words include many short ones
    ("hap", "pap", "lad"), and a rule that traced every inflection to them would take "happy",
    "paper" and "lady" out of the grid too. Nor does the dictionary tell them apart: it reads
    "morning" as a form of "morn", and "booth" as one of "boo"."""
    excluded = NOT_TARGET["en"]
    if word in excluded:
        return True
    if word.endswith("s") and not word.endswith("ss") and word[:-1] in excluded:
        return True
    return word.endswith("ies") and word[:-3] + "y" in excluded


# Irregular verbs, short adjectives and pronouns are listed in cs_CZ form by form ("bojíme",
# "odejdu", "navedl", "schopen", "svého"), flagged only for the "ne-" prefix (N), present-tense
# endings (B), past-tense endings (O) or the transgressive's adjective (X, on "sleduje", "jsa",
# "chtě"). Of those, only infinitives are lemmas; they never carry O, which tells them apart
# from passive forms such as "vzat" or "přijat".
CS_FORM_FLAGS = set("NBOX")


def is_cs_lemma(stem: str, flags: str) -> bool:
    if not set(flags) <= CS_FORM_FLAGS:
        return True
    return "O" not in flags and stem.endswith(("t", "ci"))


def vulgar_entries(hun: Dictionary) -> set[str]:
    """The entries the dictionary itself flags as vulgar (NOSUGGEST): it accepts them in a text
    but never suggests them ("shit", "srát", "cikán")."""
    flag = hun.aff.NOSUGGEST
    return {nfc(w.stem.lower()) for w in hun.dic.words if flag and flag in w.flags}


def cs_traced_to_blocked(word: str, hun: Dictionary, blocked: set[str]) -> bool:
    """Whether the Czech dictionary reads the word as a form of a blocked entry: a word above, one
    with a blocked prefix or a blocked form of "srát" or "čumět". It reaches every inflected form,
    those whose consonants change too ("blbče" of "blbec", "šlapce" of "šlapka", "otročtí" of
    "otrocký")."""
    if word in NOT_BLOCKED["cs"]:
        return False
    for form in hun.lookuper.good_forms(word):
        entry = form.in_dictionary
        if entry is None:
            continue
        stem = nfc(entry.stem.lower())
        if stem not in NOT_BLOCKED["cs"] and (stem in blocked or stem.startswith(BLOCKED_PREFIXES["cs"])
                                              or CS_BLOCKED_FORMS.fullmatch(stem)):
            return True
    return False


def cs_entries(word: str, hun: Dictionary) -> frozenset:
    """The dictionary entries a Czech word reads as a form of, itself included. An adjective made of
    a passive participle ("skrytý", "daný", "placený") and a verbal noun ("dožití", "přání",
    "čtení") are listed as entries of their own, so they are traced through the participle's short
    form ("skryt", "dán", "placen"; "dožit", "přán", "čten") to the verb it is a form of ("skrýt",
    "dát", "platit"; "dožít", "přát", "číst"). Only to a verb that form is a form of, not to a word
    spelled like it: "byt" (a flat) is no form of "bytí" (being), nor "list" (a leaf) of "listí"."""
    def lookup(w: str) -> set[str]:
        return {nfc(form.in_dictionary.stem.lower()) for form in hun.lookuper.good_forms(w)
                if form.in_dictionary is not None}

    entries = {word} | lookup(word)
    short = []
    if word.endswith(("ný", "tý", "ní", "tí")):
        short.append(word[:-1])                     # skrytý → skryt, dožití → dožit
        if word.endswith(("aný", "ání")):
            short.append(word[:-3] + "án")          # daný → dán, přání → přán
    entries |= {entry for w in short for entry in lookup(w) if entry != w and entry.endswith(("t", "ci"))}
    return frozenset(entries)


def check_sources(sources: Path):
    """Stops unless every source file is the one `sources.sha256` pins (what fetch_sources.sh
    downloads): the packs are reproducible only from those, and a folder fetched before a source was
    pinned would otherwise build different ones without a word."""
    manifest = Path(__file__).parent / "sources.sha256"
    problems = []
    for line in manifest.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        sha, name = line.split(maxsplit=1)
        path = sources / name
        if not path.is_file():
            problems.append(f"{name} is missing")
        elif hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            problems.append(f"{name} is not the pinned version")
    if problems:
        raise SystemExit(f"Word sources in {sources}: {'; '.join(problems)}. Run ./fetch_sources.sh.")


def build_lexicon(lang: str, sources: Path) -> Lexicon:
    alphabet = ALPHABETS[lang]
    word_re = re.compile(r"^[%s]{%d,%d}$" % (alphabet, MIN_LEN, MAX_LEN))
    blocked = load_blocklist(sources / "blocklist" / lang, lang)

    if lang == "en":
        hun = Dictionary.from_files(str(sources / "hunspell_en" / "en_US"))
        blocked |= vulgar_entries(hun)
        enable = {line.strip() for line in (sources / "enable" / "enable1.txt").read_text(encoding="ascii").splitlines()}
        enable = {w for w in enable if word_re.match(w)}
        known = frozenset(enable | EN_MODERN)
        # ENABLE predates the smartphone; add curated everyday words it lacks.
        valid = {w for w in enable | EN_MODERN
                 if word_re.match(w) and not is_blocked(w, blocked, lang, known=known) and w not in NOT_WORDS[lang]}
        targets = {}
        for w in sorted(valid):
            if not re.search(r"[aeiouy]", w) or w in EN_INFORMAL or en_not_target(w):
                continue  # "hmm", "brr", "tsk", "tho"…
            z = zipf_frequency(w, "en")
            if z >= 2.9 and hun.lookup(w):
                targets[w] = z
    elif lang == "cs":
        hun = Dictionary.from_files(str(sources / "hunspell_cs" / "cs_CZ"))
        blocked |= vulgar_entries(hun)
        # Dictionary entries with inflection flags are lemmas; flagless entries mix
        # indeclinables with stray inflected forms, so those come from a curated list.
        lemmas = set()
        for line in (sources / "hunspell_cs" / "cs_CZ.dic").read_text(encoding="utf-8").splitlines()[1:]:
            stem, _, flags = line.strip().partition("/")
            stem = nfc(stem)
            if word_re.match(stem) and flags and is_cs_lemma(stem, flags):
                lemmas.add(stem)
        # Only words attested in running text are shipped; Hunspell is used purely as a
        # spelling oracle so that typos, names and foreign tokens are dropped.
        valid = set()
        for w in iter_wordlist("cs", "large"):
            w = nfc(w)
            if (word_re.match(w) and not is_blocked(w, blocked, lang) and w not in NOT_WORDS[lang]
                    and hun.lookup(w) and not cs_traced_to_blocked(w, hun, blocked)):
                valid.add(w)
        targets = {}
        for w in sorted(valid):
            z = zipf_frequency(w, "cs")
            if ((w in lemmas and z >= 2.8) or w in CS_FLAGLESS_KEEP) and w not in NOT_TARGET["cs"]:
                targets[w] = z
        # Many entries are also a form of another ("pilota", a pile, is the genitive of "pilot";
        # "šál" is the genitive plural of "šála"), so that two of them in one grid read as a word
        # and its inflection. The planner keeps such pairs apart.
        entries = {w: cs_entries(w, hun) for w in sorted(targets)}
        return Lexicon(lang=lang, valid=valid, targets=targets, entries=entries)
    else:
        raise SystemExit(f"Unsupported language {lang}")

    return Lexicon(lang=lang, valid=valid, targets=targets)


# ---------------------------------------------------------------------------
# Formable-word index
# ---------------------------------------------------------------------------

class WordIndex:
    """Finds every word that can be spelled from a multiset of wheel letters."""

    def __init__(self, words, alphabet: str):
        self.bit = {ch: 1 << i for i, ch in enumerate(alphabet)}
        self.by_mask: dict[int, list[tuple[str, Counter]]] = defaultdict(list)
        for w in sorted(words):
            self.by_mask[self.mask(w)].append((w, Counter(w)))

    def mask(self, word: str) -> int:
        m = 0
        for ch in word:
            m |= self.bit[ch]
        return m

    def formable(self, letters: str) -> list[str]:
        have = Counter(letters)
        full = self.mask(letters)
        out = []
        sub = full
        while sub:
            for w, need in self.by_mask.get(sub, ()):
                if all(have[ch] >= n for ch, n in need.items()):
                    out.append(w)
            sub = (sub - 1) & full
        return out


# ---------------------------------------------------------------------------
# Crossword layout
# ---------------------------------------------------------------------------

ACROSS, DOWN = "a", "d"
STEP = {ACROSS: (0, 1), DOWN: (1, 0)}


class Layout:
    def __init__(self):
        self.cells: dict[tuple[int, int], str] = {}
        self.dirs: dict[tuple[int, int], set[str]] = defaultdict(set)
        self.words: list[tuple[str, int, int, str]] = []
        self.by_letter: dict[str, list[tuple[int, int]]] = defaultdict(list)
        self.crossings = 0
        self.min_r = self.min_c = 0
        self.max_r = self.max_c = -1

    def copy_bbox_with(self, word, r, c, d):
        dr, dc = STEP[d]
        er, ec = r + dr * (len(word) - 1), c + dc * (len(word) - 1)
        return min(self.min_r, r), min(self.min_c, c), max(self.max_r, er), max(self.max_c, ec)

    def crossings_for(self, word: str, r: int, c: int, d: str) -> int:
        """Returns the number of crossings, or -1 when the placement is illegal."""
        dr, dc = STEP[d]
        if (r - dr, c - dc) in self.cells:
            return -1
        if (r + dr * len(word), c + dc * len(word)) in self.cells:
            return -1
        crossings = 0
        for k, ch in enumerate(word):
            cell = (r + dr * k, c + dc * k)
            existing = self.cells.get(cell)
            if existing is not None:
                if existing != ch or d in self.dirs[cell]:
                    return -1
                crossings += 1
            else:
                # A fresh cell must not touch anything sideways, or it would spell a stray word.
                if (cell[0] + dc, cell[1] + dr) in self.cells or (cell[0] - dc, cell[1] - dr) in self.cells:
                    return -1
        return crossings if crossings else -1

    def candidates(self, word: str):
        seen = set()
        for k, ch in enumerate(word):
            for cell in self.by_letter.get(ch, ()):
                used = self.dirs[cell]
                if len(used) != 1:
                    continue
                d = DOWN if ACROSS in used else ACROSS
                dr, dc = STEP[d]
                start = (cell[0] - dr * k, cell[1] - dc * k, d)
                if start in seen:
                    continue
                seen.add(start)
                n = self.crossings_for(word, *start)
                if n > 0:
                    yield start[0], start[1], d, n

    def place(self, word: str, r: int, c: int, d: str):
        dr, dc = STEP[d]
        for k, ch in enumerate(word):
            cell = (r + dr * k, c + dc * k)
            if cell in self.cells:
                self.crossings += 1
            else:
                self.cells[cell] = ch
                self.by_letter[ch].append(cell)
            self.dirs[cell].add(d)
        self.words.append((word, r, c, d))
        self.min_r, self.min_c, self.max_r, self.max_c = self.copy_bbox_with(word, r, c, d)

    @property
    def rows(self):
        return self.max_r - self.min_r + 1

    @property
    def cols(self):
        return self.max_c - self.min_c + 1

    def normalized(self):
        return [(w, r - self.min_r, c - self.min_c, d) for (w, r, c, d) in self.words]


def layout_words(words: list[str], seed_word: str, rng: random.Random,
                 max_rows: int, max_cols: int, attempts: int) -> Layout | None:
    """Randomised greedy search; returns the best layout found (may omit some words)."""
    best, best_score = None, None
    for _ in range(attempts):
        layout = Layout()
        layout.place(seed_word, 0, 0, rng.choice((ACROSS, ACROSS, DOWN)))
        pending = [w for w in words if w != seed_word]
        rng.shuffle(pending)
        pending.sort(key=len, reverse=True)
        while pending:
            move, move_score = None, None
            for w in pending:
                for r, c, d, n in layout.candidates(w):
                    r0, c0, r1, c1 = layout.copy_bbox_with(w, r, c, d)
                    rows, cols = r1 - r0 + 1, c1 - c0 + 1
                    if rows > max_rows or cols > max_cols:
                        continue
                    area = rows * cols
                    aspect = abs(cols - rows * 1.15)
                    score = n * 5.0 - area * 0.35 - aspect * 0.8 + len(w) * 0.9 + rng.random() * 2.5
                    if move_score is None or score > move_score:
                        move, move_score = (w, r, c, d), score
            if move is None:
                break
            layout.place(*move)
            pending.remove(move[0])
        area = layout.rows * layout.cols
        density = sum(len(w) for w, *_ in layout.words) / area
        score = (len(layout.words) * 100 + layout.crossings * 8 + density * 90
                 - abs(layout.cols - layout.rows * 1.15) * 4)
        if best_score is None or score > best_score:
            best, best_score = layout, score
    return best


# ---------------------------------------------------------------------------
# Difficulty curve
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Spec:
    letters: int
    min_words: int
    max_words: int
    min_zipf: float
    max_rows: int
    max_cols: int


# The thresholds differ per language: Czech spreads frequency over many inflected forms,
# so a lemma's own zipf value is lower than an equally familiar English word's.
ZIPF_EASY = {"en": 4.4, "cs": 3.9}
ZIPF_HARD = {"en": 3.15, "cs": 3.0}


def level_spec(i: int, lang: str) -> Spec:
    chapter, pos = divmod(i, LEVELS_PER_CHAPTER)
    # Saw-tooth: each chapter opens gently and builds to a bigger finale.
    breather = pos in (0, 1)
    finale = pos == LEVELS_PER_CHAPTER - 1

    if i < 3:
        letters, lo, hi = 3, 2, 3
    elif i < 20:
        letters, lo, hi = 4, 3, 5
    elif i < 66:
        letters, lo, hi = 5, 4, 7
    elif i < 220:
        letters = 5 if breather else 6
        lo, hi = (4, 7) if letters == 5 else (5, 8 + min(2, (i - 66) // 60))
    else:
        long_slots = {3, 6, 9, 11} if i < 500 else {2, 4, 6, 8, 9, 11}
        letters = 7 if pos in long_slots else 6
        lo, hi = (7, 11 + min(2, (i - 220) // 200)) if letters == 7 else (6, 10)
    if finale and i >= 20:
        hi += 2
    if breather and i >= 20:
        hi = max(lo, hi - 2)

    progress = min(1.0, i / 700)
    min_zipf = ZIPF_EASY[lang] - (ZIPF_EASY[lang] - ZIPF_HARD[lang]) * progress
    if breather:
        min_zipf += 0.25

    size = {3: (5, 5), 4: (6, 7), 5: (8, 8), 6: (9, 10), 7: (10, 11)}[letters]
    return Spec(letters, lo, hi, round(min_zipf, 2), *size)


def max_short_words(spec: Spec) -> int:
    """Three-letter words repeat a lot across levels, so bigger wheels use only a few."""
    return {3: 3, 4: 4, 5: 4}.get(spec.letters, 3)


def daily_spec(i: int, lang: str) -> Spec:
    if lang == "cs":
        # A six-letter wheel spells few Czech base forms, and the journey, planned first, takes
        # the six-letter wheels that spell enough; the daily ones left would have five words.
        # Seven-letter wheels are plentiful and give a daily the size of an English one.
        letters = 7
    else:
        letters = 7 if i % 7 in (5, 6) else 6  # bigger wheel twice a week
    lo, hi = (7, 12) if letters == 7 else (6, 10)
    min_zipf = (ZIPF_EASY[lang] + ZIPF_HARD[lang]) / 2
    if lang == "cs":
        # Czech lemmas are rarer than English words of the same familiarity, and the journey has
        # used the commonest by now: at the midpoint most dailies would make only their minimum.
        # The late journey's vocabulary gives them eight or more words, and fresher ones.
        lo, min_zipf = 8, ZIPF_HARD[lang]
    size = (10, 11) if letters == 7 else (9, 10)
    return Spec(letters, lo, hi, round(min_zipf, 2), *size)


# ---------------------------------------------------------------------------
# Level assembly
# ---------------------------------------------------------------------------

@dataclass
class Job:
    key: tuple[str, int]
    seed_word: str
    words: list[str]
    spec: Spec
    rng_seed: int
    planned: list[str] = field(default_factory=list)
    # Words that only make up the grid's minimum (worn out, a recent three-letter word, or one more
    # of an echoed puzzle's), and words a nearby puzzle has: the layout gives these up first.
    fill_only: frozenset = frozenset()
    recent: frozenset = frozenset()


@dataclass
class Selection:
    words: list[str]
    fill_only: frozenset
    recent: frozenset
    # Fill-only words that bring back a third word or more of an echoed earlier puzzle.
    forced_echoes: int


# A grid word should not come back within this many puzzles of the same series, either side.
RECENT = 10
# How much a seed loses for each of its wheel's words that a nearby puzzle already has.
RECENT_PENALTY = 20
# A word already in this many puzzles is worn out, and only makes up a grid's minimum.
WORN = 12
# A word in this many puzzles is spent and not used again: a wheel that needs it to reach its
# minimum makes way for another. It binds on the commonest short Czech words.
SPENT = 30
# An earlier puzzle, however far back, that a wheel's grid would mostly repeat reads as the same
# puzzle again ("NOW, OWN, WON" of the first level making up most of the thirteenth). A seed
# loses this much times the overlap (shared words over all the words of the two grids) with the
# most similar earlier puzzle, when they would share at least `ECHO_WORDS` words and the overlap
# is at least `ECHO_OVERLAP`.
ECHO_PENALTY = 12
ECHO_OVERLAP, ECHO_WORDS = 0.5, 3
# Of an earlier puzzle whose grid the wheel spells at least this share of (and `ECHO_WORDS`
# words), a grid takes at most `ECHO_WORDS` - 1 words unless it needs more to reach its minimum;
# a seed loses `ECHO_FORCED_PENALTY` for each word it would need so, which passes such a wheel
# over whenever the sample has another.
ECHO_RETURN = 0.5
ECHO_FORCED_PENALTY = 25
# A grid that would need more such words than this to reach its minimum (five or more words of an
# earlier puzzle: in Czech, late daily puzzles sharing seven of their eight words) is taken only when
# rarer vocabulary and a smaller grid can't do without them either.
MAX_FORCED_ECHOES = 2
# A grid that would need more such words than this looks for rarer vocabulary that needs fewer
# first: it takes up to `MAX_FORCED_ECHOES` of them only before it is made smaller.
PREFERRED_FORCED_ECHOES = 1
# How many windows of 40 seeds a plan looks at, at most, for one that needs no such word.
SEED_WINDOWS = 4
# A seed word that is worn out itself (every grid has its seed word).
WORN_SEED_PENALTY = 15


@dataclass
class Generator:
    lex: Lexicon
    seed: int
    target_index: WordIndex = field(init=False)
    valid_index: WordIndex = field(init=False)
    used_seeds: set[str] = field(default_factory=set)
    used_wheels: set[str] = field(default_factory=set)
    word_uses: Counter = field(default_factory=Counter)
    word_puzzles: defaultdict = field(default_factory=lambda: defaultdict(set))
    # The grid words of every puzzle planned or laid out so far, by key.
    puzzle_words: defaultdict = field(default_factory=lambda: defaultdict(set))
    # Series that repeat as a cycle (the daily rotation), by label → length.
    cycles: dict = field(default_factory=dict)
    # The spare words of puzzles planned but not laid out yet, which the layout may still place: a
    # nearby puzzle planned meanwhile keeps clear of them too. Not counted as uses.
    spare_puzzles: defaultdict = field(default_factory=lambda: defaultdict(set))
    puzzle_spares: defaultdict = field(default_factory=lambda: defaultdict(set))

    def __post_init__(self):
        alphabet = ALPHABETS[self.lex.lang]
        self.target_index = WordIndex(self.lex.targets, alphabet)
        self.valid_index = WordIndex(self.lex.valid, alphabet)
        self.rng = random.Random(self.seed)
        self.seeds_by_len: dict[int, list[str]] = defaultdict(list)
        for w, z in self.lex.targets.items():
            self.seeds_by_len[len(w)].append(w)
        for n in self.seeds_by_len:
            self.seeds_by_len[n].sort(key=lambda w: (-self.lex.targets[w], w))
        self.formable_cache: dict[str, list[str]] = {}

    def formable_targets(self, letters: str) -> list[str]:
        key = "".join(sorted(letters))
        if key not in self.formable_cache:
            self.formable_cache[key] = self.target_index.formable(letters)
        return self.formable_cache[key]

    def record(self, words, key, sign: int = 1):
        """Counts the grid words of a puzzle (`sign` -1 takes back a plan the layout replaced)."""
        for w in words:
            self.word_uses[w] += sign
            if sign > 0:
                self.word_puzzles[w].add(key)
                self.puzzle_words[key].add(w)
            else:
                self.word_puzzles[w].discard(key)
                self.puzzle_words[key].discard(w)

    def echo(self, words, size: int, key) -> float:
        """How much a grid of `size` words drawn from `words` would repeat the most similar earlier
        puzzle: the words they would share over all the words of the two (0 when that is below
        `ECHO_OVERLAP` or fewer than `ECHO_WORDS` words are shared)."""
        shared = Counter(other for w in words for other in self.word_puzzles[w] if other != key)
        echo = 0.0
        for other, count in shared.items():
            count = min(count, size)
            overlap = count / (len(self.puzzle_words[other]) + size - count)
            if count >= ECHO_WORDS and overlap >= ECHO_OVERLAP:
                echo = max(echo, overlap)
        return echo

    def echoed(self, subs, seed_word: str, key, size: int) -> list[set[str]]:
        """The grids of the earlier puzzles that a grid of `size` words of the wheel could mostly
        repeat: the wheel spells at least `ECHO_WORDS` of their words, and `ECHO_RETURN` of the
        smaller of the two grids (of the earlier one, or of the one being made: a small grid drawn
        from a big one's words repeats it too)."""
        words = set(subs) | {seed_word}
        # A puzzle not laid out yet may still place its spare words.
        shared = Counter(other for w in words for keys in (self.word_puzzles[w], self.spare_puzzles[w])
                         for other in keys if other != key)
        return [self.puzzle_words[other] | self.puzzle_spares[other] for other, count in sorted(shared.items())
                if count >= ECHO_WORDS and count >= ECHO_RETURN * min(len(self.puzzle_words[other]), size)]

    def is_recent(self, word: str, key) -> bool:
        """Whether a nearby puzzle of the same series already has the word. The daily rotation
        starts over after its last puzzle, so there the last puzzles are next to the first."""
        label, i = key
        cycle = self.cycles.get(label)

        def distance(j):
            d = abs(i - j)
            return min(d, cycle - d) if cycle else d

        return any(other == label and 0 < distance(j) <= RECENT
                   for keys in (self.word_puzzles[word], self.spare_puzzles[word]) for other, j in keys)

    def is_worn(self, word: str) -> bool:
        return self.word_uses[word] >= WORN

    def is_spent(self, word: str) -> bool:
        return self.word_uses[word] >= SPENT

    def plan(self, spec: Spec, key, exclude: set[str] = frozenset(), mode: str = "strict",
             max_forced: int = MAX_FORCED_ECHOES) -> Job | None:
        """Picks a seed word and grid words for a level, favouring fresh vocabulary. `exclude` holds
        wheels (sorted letters) whose grids could not be laid out. The `mode` says what becomes of a
        grid that would need more than `max_forced` words of an earlier puzzle:
          * "strict" turns the plan down when the best seed's would (`generate_series` then asks
            for rarer words, then a smaller grid),
          * "compliant" takes the best seed whose grid would not, scoring worse as it may (most
            often for words of nearby puzzles), and
          * "any" takes the best seed whatever its grid needs."""
        z = self.lex.targets
        # A spent word is not used again, as a seed word neither.
        pool = [w for w in self.seeds_by_len[spec.letters]
                if z[w] >= spec.min_zipf and w not in self.used_seeds and not self.is_spent(w)
                and "".join(sorted(w)) not in self.used_wheels and "".join(sorted(w)) not in exclude]
        if not pool:
            return None
        recent_memo: dict[str, bool] = {}

        def is_recent(w: str) -> bool:
            if w not in recent_memo:
                recent_memo[w] = self.is_recent(w, key)
            return recent_memo[w]

        # Look at a random window of reasonably common seeds and keep the best. When every seed of
        # the window would bring back an earlier puzzle to make up its minimum, or put a word of a
        # nearby puzzle in its grid, look at more.
        max_short = max_short_words(spec)
        limit = max_forced if mode == "compliant" else None
        best, best_score, best_forced, best_recent = None, None, 0, 0
        for _ in range(SEED_WINDOWS):
            if not pool or (best is not None and best_forced == 0 and best_recent == 0):
                break
            sample = self.rng.sample(pool, min(len(pool), 40))
            looked = set(sample)
            pool = [w for w in pool if w not in looked]
            for seed_word in sample:
                best, best_score, best_forced, best_recent = self.consider(
                    seed_word, spec, key, is_recent, max_short, (best, best_score, best_forced, best_recent),
                    limit)
        if best is None or (mode == "strict" and best_forced > max_forced):
            return None
        seed_word, selection = best
        return Job(key, seed_word, selection.words, spec, self.rng.randrange(1 << 30),
                   fill_only=selection.fill_only, recent=selection.recent)

    def consider(self, seed_word: str, spec: Spec, key, is_recent, max_short: int, current,
                 max_forced: int | None = None):
        """Scores a seed word, returning it with its selection when it beats `current` (and needs at
        most `max_forced` words of an earlier puzzle to make up its minimum, when given)."""
        z = self.lex.targets
        subs = [w for w in self.formable_targets(seed_word)
                if w != seed_word and z[w] >= spec.min_zipf and not self.is_spent(w)]
        usable = sum(1 for w in subs if len(w) > 3) + min(max_short, sum(1 for w in subs if len(w) == 3))
        if usable + 1 < spec.min_words:
            return current
        fresh = sum(1 for w in subs if self.word_uses[w] == 0)
        # Average earlier uses of the wheel's words. Levels usually take every word a wheel
        # offers, so variety has to come from choosing wheels whose words are less worn.
        worn = sum(self.word_uses[w] for w in subs) / max(1, len(subs))
        # Words a nearby puzzle already has are the repetition a player actually notices…
        recent = sum(1 for w in subs + [seed_word] if is_recent(w))
        selection = self.select(seed_word, subs, spec, key, is_recent)
        # `usable` is only an estimate: it can't tell which words `select` turns down as forms of
        # one word. A grid that falls short of its minimum would only fail its layout, and until
        # then keep its words from the puzzles planned around it.
        if len(selection.words) + 1 < spec.min_words:
            return current
        grid = {seed_word, *selection.words[: spec.max_words - 1]}
        echo = self.echo(grid, len(grid), key)
        # …and most of all those that would end up in this grid.
        grid_recent = sum(1 for w in grid if is_recent(w))
        recent += grid_recent
        score = (len(grid) * 3 + fresh * 0.8 - self.word_uses[seed_word] * 4
                 - (WORN_SEED_PENALTY if self.is_worn(seed_word) else 0)
                 - worn - recent * RECENT_PENALTY - echo * ECHO_PENALTY
                 - selection.forced_echoes * ECHO_FORCED_PENALTY
                 + (z[seed_word] - spec.min_zipf) * 1.5 + self.rng.random() * 3)
        if max_forced is not None and selection.forced_echoes > max_forced:
            return current
        if current[1] is None or score > current[1]:
            return (seed_word, selection), score, selection.forced_echoes, grid_recent
        return current

    def select(self, seed_word: str, subs: list[str], spec: Spec, key, is_recent) -> Selection:
        """The grid words a wheel would get, best first. Common, rarely used words come first, with a
        healthy spread of lengths. A word from a nearby puzzle comes last: a three-letter one only
        makes up the minimum, a longer one only fills the grid, never as a spare. A worn-out word, and
        one that would be the `ECHO_WORDS`th or later of an echoed earlier puzzle, only make up the
        minimum: they are taken in a second pass, once the first has run out of other words (with one
        spare, should the layout drop a word; `run_layout` takes it out again if it didn't)."""
        z = self.lex.targets
        echoed = self.echoed(subs, seed_word, key, min(len(subs) + 1, spec.max_words))
        ranked = sorted(subs, key=lambda w: (is_recent(w), self.is_worn(w),
                                             -(z[w] + len(w) * 0.35 - self.word_uses[w] * 0.9
                                               + self.rng.random() * 0.9)))
        max_short = max_short_words(spec)
        chosen: list[str] = []
        short = 0

        def echoes(w: str) -> bool:
            grid = set(chosen) | {seed_word}
            return any(w in other and len(other & grid) >= ECHO_WORDS - 1 for other in echoed)

        def same_word(w: str) -> bool:
            return any(self.lex.same_word(w, other) for other in [seed_word, *chosen])

        # `chosen` doesn't count the seed word: the grid has len(chosen) + 1 words.
        held = []
        for w in ranked:
            if len(chosen) >= spec.max_words + 3:  # a few spares; the layout may drop some
                break
            if same_word(w):
                continue
            if self.is_worn(w) or (is_recent(w) and len(w) == 3) or echoes(w):
                held.append(w)
                continue
            if is_recent(w) and len(chosen) + 1 >= spec.max_words:
                continue
            if len(w) == 3:
                if short >= max_short:
                    continue
                short += 1
            chosen.append(w)
        fill_only, forced_echoes = [], 0
        for w in held:
            if len(chosen) + 1 > spec.min_words:
                break
            if same_word(w):
                continue
            if len(w) == 3:
                if short >= max_short:
                    continue
                short += 1
            # The word that takes the grid past its minimum is the spare, which the layout takes
            # out again when it can: it isn't needed, so it isn't counted as a word the grid must
            # take from an earlier puzzle.
            if len(chosen) + 1 < spec.min_words:
                forced_echoes += echoes(w)
            chosen.append(w)
            fill_only.append(w)
        return Selection(chosen, frozenset(fill_only), frozenset(w for w in chosen if is_recent(w)), forced_echoes)


def run_layout(job: Job):
    rng = random.Random(job.rng_seed)
    spec = job.spec
    attempts = 48 if spec.letters >= 6 else 24
    layout = layout_words(job.words + [job.seed_word], job.seed_word, rng,
                          spec.max_rows, spec.max_cols, attempts)
    placed = layout.normalized()
    # A word that only makes up the minimum goes again when the grid has its minimum without it.
    while len(placed) > spec.min_words:
        trimmed = trim_one(placed, job.seed_word, only=job.fill_only)
        if trimmed is None:
            break
        placed = trimmed
    # Trim to the target size, never removing the seed word or disconnecting the grid: words that
    # only made up numbers first, then words a nearby puzzle has, then the shortest.
    value = lambda w: (w not in job.fill_only, w not in job.recent, len(w))
    while len(placed) > spec.max_words:
        trimmed = trim_one(placed, job.seed_word, value=value)
        if trimmed is None:
            break
        placed = trimmed
    return job.key, placed


def trim_one(placed, seed_word, value=len, only=None):
    """Removes the least valuable word (by `value`; of `only`, when given) whose removal keeps the
    grid connected."""
    order = sorted(range(len(placed)), key=lambda k: value(placed[k][0]))
    for k in order:
        if placed[k][0] == seed_word or (only is not None and placed[k][0] not in only):
            continue
        rest = placed[:k] + placed[k + 1:]
        if is_connected(rest) and not stray_runs(rest):
            return normalize(rest)
    return None


def relayout(placed, seed_word, spec: Spec, size: int, value, rng: random.Random):
    """Lays out again the `size` most valuable words of a grid (by `value`, the seed word always
    among them), for when every word it could give up holds it together. None when the new grid
    would have fewer than `smallest_grid` words."""
    words = sorted((w for w, *_ in placed if w != seed_word), key=lambda w: (value(w), w), reverse=True)
    layout = layout_words(sorted(words[: size - 1]), seed_word, rng, spec.max_rows, spec.max_cols, 48)
    candidate = layout.normalized() if layout is not None else []
    return candidate if len(candidate) >= smallest_grid(spec) else None


def word_cells(w, r, c, d):
    dr, dc = STEP[d]
    return [(r + dr * k, c + dc * k) for k in range(len(w))]


def is_connected(placed) -> bool:
    cell_sets = [set(word_cells(*p)) for p in placed]
    seen, stack = {0}, [0]
    while stack:
        a = stack.pop()
        for b in range(len(placed)):
            if b not in seen and cell_sets[a] & cell_sets[b]:
                seen.add(b)
                stack.append(b)
    return len(seen) == len(placed)


def normalize(placed):
    min_r = min(r for _, r, _, _ in placed)
    min_c = min(c for _, _, c, _ in placed)
    return [(w, r - min_r, c - min_c, d) for (w, r, c, d) in placed]


def stray_runs(placed) -> list[tuple[str, int, int, str]]:
    """Every maximal run of 2+ letters must be one of the placed words; returns the others."""
    grid = {}
    for w, r, c, d in placed:
        for cell, ch in zip(word_cells(w, r, c, d), w):
            grid[cell] = ch
    words = {(w, r, c, d) for w, r, c, d in placed}
    strays = []
    for (r, c) in grid:
        for d, (dr, dc) in STEP.items():
            if (r - dr, c - dc) in grid:
                continue
            run, k = "", 0
            while (r + dr * k, c + dc * k) in grid:
                run += grid[(r + dr * k, c + dc * k)]
                k += 1
            if len(run) > 1 and (run, r, c, d) not in words:
                strays.append((run, r, c, d))
    return strays


# The largest grid the game lays out on the smallest iPhone (`PuzzlePackTests.maxRows/maxCols`).
MAX_ROWS, MAX_COLS = 10, 11


def validate(placed, letters: str, lex: Lexicon, bonus: list[str]):
    """Checks the invariants the app relies on (and `PuzzlePackTests` checks again), so that a
    regression stops the build of a pack instead of shipping. Not `assert`, which `python -O` skips."""
    problems = []
    grid: dict[tuple[int, int], str] = {}
    for w, r, c, d in placed:
        if Counter(w) - Counter(letters):
            problems.append(f"{w} not formable from {letters}")
        if w not in lex.targets or w not in lex.valid:
            problems.append(f"{w} is not a grid word")
        if not MIN_LEN <= len(w) <= MAX_LEN:
            problems.append(f"{w} has {len(w)} letters")
        for (cell, ch) in zip(word_cells(w, r, c, d), w):
            if grid.get(cell, ch) != ch:
                problems.append(f"conflict at {cell}")
            grid[cell] = ch
    # A word never sits inside a longer run of letters (CAT within CATS).
    for w, r, c, d in placed:
        dr, dc = STEP[d]
        if (r - dr, c - dc) in grid or (r + dr * len(w), c + dc * len(w)) in grid:
            problems.append(f"{w} is part of a longer run")
    if len({w for w, *_ in placed}) != len(placed):
        problems.append("duplicate grid word")
    words = sorted(w for w, *_ in placed)
    problems += [f"{a} and {b} read as one word" for i, a in enumerate(words) for b in words[i + 1:]
                 if lex.same_word(a, b)]
    if stray_runs(placed):
        problems.append(f"stray runs {stray_runs(placed)}")
    if not is_connected(list(placed)):
        problems.append("grid not connected")
    if placed and (min(r for r, _ in grid) != 0 or min(c for _, c in grid) != 0):
        problems.append("grid not normalized")
    rows = max(r for r, _ in grid) + 1 if grid else 0
    cols = max(c for _, c in grid) + 1 if grid else 0
    if rows > MAX_ROWS or cols > MAX_COLS:
        problems.append(f"grid {rows}×{cols}")
    if not any(Counter(w) == Counter(letters) for w, *_ in placed):
        problems.append("no word uses the whole wheel")
    grid_words = {w for w, *_ in placed}
    for w in bonus:
        if w in grid_words:
            problems.append(f"{w} is both grid and bonus")
        if w not in lex.valid or Counter(w) - Counter(letters):
            problems.append(f"bonus {w} is not a valid word of the wheel")
    if problems:
        raise SystemExit(f"Invalid puzzle {letters}: {'; '.join(problems)}")


def validate_pack(levels, daily, lang: str):
    """Checks what spans puzzles (and `PuzzlePackTests` checks again): every chapter ends with its
    largest wheel and largest grid, the daily wheels have their size, and no wheel is one letter."""
    problems = []
    for start in range(0, len(levels) - LEVELS_PER_CHAPTER + 1, LEVELS_PER_CHAPTER):
        chapter = levels[start:start + LEVELS_PER_CHAPTER]
        seed_word, placed = chapter[-1]
        if len(seed_word) < max(len(s) for s, _ in chapter) or len(placed) < max(len(p) for _, p in chapter):
            problems.append(f"chapter {start // LEVELS_PER_CHAPTER + 1} doesn't end with its largest puzzle")
    for i, (seed_word, _) in enumerate(daily):
        if len(seed_word) != daily_spec(i, lang).letters:
            problems.append(f"daily #{i} has {len(seed_word)} letters")
    problems += [f"wheel {seed_word} has one letter" for seed_word, _ in levels + daily if len(set(seed_word)) < 2]
    if problems:
        raise SystemExit(f"Invalid pack: {'; '.join(problems[:10])}")


def scramble(word: str, rng: random.Random) -> str:
    letters = list(word)
    for _ in range(20):
        rng.shuffle(letters)
        if "".join(letters) != word:
            break
    return "".join(letters)


def bonus_words(placed, seed_word, gen: Generator) -> list[str]:
    """Every other valid word the wheel spells."""
    grid_words = {w for w, *_ in placed}
    return sorted(w for w in gen.valid_index.formable(seed_word) if w not in grid_words)


def to_json(placed, seed_word, bonus: list[str], rng: random.Random):
    letters = scramble(seed_word, rng)
    up = lambda s: nfc(s.upper())
    placed = sorted(placed, key=lambda p: (len(p[0]), p[0]))
    return {
        "letters": up(letters),
        "words": [{"w": up(w), "r": r, "c": c, "d": d} for (w, r, c, d) in placed],
        "bonus": [up(w) for w in bonus],
    }


# Relaxing a spec never asks for rarer words than the lexicon's own grid threshold.
ZIPF_FLOOR = 2.8


def smallest_grid(spec: Spec) -> int:
    """The fewest words a grid of the spec may end up with: relaxing goes no lower."""
    return min(4, spec.min_words)


# Relaxing a spec takes up to `RELAX_STEPS` steps; the first `VOCABULARY_STEPS` keep its grid size.
RELAX_STEPS, VOCABULARY_STEPS = 7, 4
# The order a plan relaxes in, as (the most words of an earlier puzzle its grid may need to make up
# its minimum, relaxing step): rarer vocabulary that needs at most `PREFERRED_FORCED_ECHOES` such
# words before `MAX_FORCED_ECHOES` of them, and those before a smaller grid.
STRICT_ORDER = ([(PREFERRED_FORCED_ECHOES, step) for step in range(VOCABULARY_STEPS)]
                + [(MAX_FORCED_ECHOES, step) for step in range(RELAX_STEPS)])


def relaxed(spec: Spec, step: int) -> Spec:
    """The spec after `step` rounds of relaxing: rarer vocabulary first, and only from the fourth
    step on a smaller grid (never below four words)."""
    min_words = max(smallest_grid(spec), spec.min_words - max(0, step - VOCABULARY_STEPS + 1))
    min_zipf = max(ZIPF_FLOOR, round(spec.min_zipf - 0.15 * step, 2))
    return Spec(spec.letters, min_words, spec.max_words, min_zipf, spec.max_rows, spec.max_cols)


def generate_series(gen: Generator, specs, label: str, pool: mp.Pool, cycle: bool = False):
    """Plans levels sequentially (vocabulary freshness), lays them out in parallel."""
    if cycle:
        gen.cycles[label] = len(specs)
    results: dict[int, tuple[str, list]] = {}
    pending = list(range(len(specs)))
    rejected: dict[int, set[str]] = defaultdict(set)
    round_no = 0
    while pending:
        round_no += 1
        jobs = []
        for i in pending:
            # Every round starts from the level's own spec: a retry shouldn't inherit the
            # relaxing an earlier round needed. When the pool of fresh seeds is exhausted, it
            # gradually admits rarer vocabulary, and only then accepts a smaller grid. A grid that
            # would need words of an earlier puzzle to make up its minimum first tries rarer
            # vocabulary that needs at most `PREFERRED_FORCED_ECHOES` of them, then takes up to
            # `MAX_FORCED_ECHOES` before it is made smaller. When none of those does without
            # bringing back most of an earlier puzzle, it takes the best seed looked at whose grid
            # wouldn't, and only then any.
            job = None
            for mode in ("strict", "compliant", "any"):
                order = STRICT_ORDER if mode == "strict" else [(MAX_FORCED_ECHOES, s) for s in range(RELAX_STEPS)]
                for max_forced, step in order:
                    spec = relaxed(specs[i], step) if step else specs[i]
                    job = gen.plan(spec, (label, i), rejected[i], mode, max_forced)
                    if job is not None:
                        break
                if job is not None:
                    break
            if job is None:
                raise SystemExit(f"Ran out of seed words for {label} #{i} ({spec})")
            # Reserve the seed immediately so later plans in this round can't reuse it, and count
            # the words it will probably place until the layout says which it did.
            gen.used_seeds.add(job.seed_word)
            gen.used_wheels.add("".join(sorted(job.seed_word)))
            job.planned = [job.seed_word] + job.words[: spec.max_words - 1]
            gen.record(job.planned, job.key)
            for w in job.words[spec.max_words - 1:]:
                gen.spare_puzzles[w].add(job.key)
                gen.puzzle_spares[job.key].add(w)
            jobs.append(job)
        retry = []
        by_key = {job.key: job for job in jobs}
        for key, placed in pool.imap_unordered(run_layout, jobs, chunksize=4):
            job = by_key[key]
            i = key[1]
            gen.record(job.planned, key, -1)
            for w in job.words:
                gen.spare_puzzles[w].discard(key)
            gen.puzzle_spares.pop(key, None)
            if len(placed) >= job.spec.min_words:
                results[i] = (job.seed_word, placed)
                gen.record([w for w, *_ in placed], key)
            else:
                # The wheel stays out of this level's retries (an anagram of the seed would make the
                # same grid), but other levels may still use it.
                rejected[i].add("".join(sorted(job.seed_word)))
                gen.used_seeds.discard(job.seed_word)
                gen.used_wheels.discard("".join(sorted(job.seed_word)))
                retry.append(i)
        print(f"  {label}: round {round_no} placed {len(jobs) - len(retry)}/{len(jobs)}", file=sys.stderr)
        pending = sorted(retry)
    return [results[i] for i in range(len(specs))]


def promote_finales(levels, gen: Generator):
    """Makes each chapter's finale the chapter's largest grid, so that it is bigger by word count
    as well as by wheel. First it swaps places with the largest grid among the levels with the
    same wheel size that the move brings no word next to a level that has it: a swap within a
    chapter keeps the wheel sizes of every position (the two gentle openers are left alone, as their
    vocabulary is easier). Any other level that still has more words (one with a smaller wheel, an
    opener, or one whose swap would have brought a word next to a level that has it) then gives up
    its least valuable ones (they stay bonus words), down to no fewer than `smallest_grid`; when
    every word it could give up holds its grid together, its most valuable words are laid out
    again."""
    levels = list(levels)
    # The key each level's words are recorded under in `gen`, which moves with the level.
    keys = [("levels", i) for i in range(len(levels))]
    words = lambda k: {w for w, *_ in levels[k][1]}

    def neighbours(at: int, skip) -> set[str]:
        """The words of the levels within `RECENT` of position `at`, but those at `skip`."""
        return set().union(*(words(j) for j in range(max(0, at - RECENT), min(len(levels), at + RECENT + 1))
                             if j != at and j not in skip))

    def repeats(placements) -> set[tuple[int, str]]:
        """The (level, word) pairs of words that a level within `RECENT` of its position already has,
        for (level, position) pairs."""
        skip = {at for _, at in placements} | {k for k, _ in placements}
        return {(k, w) for k, at in placements for w in words(k) & neighbours(at, skip)}

    for start in range(0, len(levels) - LEVELS_PER_CHAPTER + 1, LEVELS_PER_CHAPTER):
        last = start + LEVELS_PER_CHAPTER - 1
        size = len(levels[last][0])
        # Moving a level up to the finale's place gives it new neighbours, which were planned
        # against its old ones: a swap that would bring a word next to a level that has it is
        # passed over for the next largest grid.
        same = sorted((k for k in range(start + 2, last) if len(levels[k][0]) == size
                       and len(levels[k][1]) > len(levels[last][1])),
                      key=lambda k: (-len(levels[k][1]), k))
        for best in same:
            # Every repeat after the move was there before it (most often there is none either way).
            if repeats([(best, last), (last, best)]) <= repeats([(best, best), (last, last)]):
                levels[best], levels[last] = levels[last], levels[best]
                keys[best], keys[last] = keys[last], keys[best]
                break
        most = len(levels[last][1])
        for k in range(start, last):
            seed_word, placed = levels[k]
            if len(placed) <= most:
                continue
            spec = level_spec(k, gen.lex.lang)
            if most < smallest_grid(spec):
                raise SystemExit(f"Level {k} would have to shrink to its finale's {most} words, "
                                 f"below the {smallest_grid(spec)} a grid may have")
            # The words its neighbours have go first, then the shortest (they stay bonus words).
            near = neighbours(k, {k})
            value = lambda w: (w not in near, len(w))
            while len(placed) > most:
                trimmed = trim_one(placed, seed_word, value=value)
                if trimmed is None:
                    trimmed = relayout(placed, seed_word, spec, most, value, random.Random(gen.seed * 7919 + k))
                if trimmed is None:
                    raise SystemExit(f"Level {k} can't be trimmed to its finale's {most} words")
                gen.record({w for w, *_ in placed} - {w for w, *_ in trimmed}, keys[k], -1)
                placed = trimmed
            levels[k] = (seed_word, placed)
    return levels, keys


def settle_in_pack_order(series, specs, keys, gen: Generator, history: list[set[str]], chapters: bool = False):
    """Holds every grid to the two rules on words of earlier puzzles, counted the way a player
    meets them: in pack order (the journey, then the daily rotation), with the grids as they were
    laid out. The plans can't quite: a round plans every puzzle before any is laid out, and a
    layout may place a spare word, or keep a word it can't take out, in place of a planned one.
    A grid above its minimum gives up
      * a word already in `WORN` earlier puzzles, and
      * a third or later word of an earlier puzzle whose grid the wheel spells `ECHO_RETURN` of
        (of the smaller of the two grids, at their final sizes) and `ECHO_WORDS` words of,
    as long as its grid stays connected; when every such word holds the grid together, the rest is
    laid out again without one of them, if that still makes the minimum. A finale keeps as many
    words as its chapter's largest other level. `history` holds the grids of the series before this
    one, and is extended."""
    series = list(series)
    uses = Counter(w for grid in history for w in grid)
    puzzles_with = defaultdict(list)
    for j, grid in enumerate(history):
        for w in grid:
            puzzles_with[w].append(j)
    for i, (seed_word, placed) in enumerate(series):
        floor = specs[i].min_words
        if chapters and i % LEVELS_PER_CHAPTER == LEVELS_PER_CHAPTER - 1:
            start = i - LEVELS_PER_CHAPTER + 1
            floor = max(floor, max(len(series[k][1]) for k in range(start, i)))
        wheel = set(gen.formable_targets(seed_word))
        while len(placed) > floor:
            grid = {w for w, *_ in placed}
            give_up = {w for w in grid if uses[w] >= WORN}
            shared = Counter(j for w in grid for j in puzzles_with[w])
            for j, count in shared.items():
                spelled = len(wheel & history[j])
                if (count >= ECHO_WORDS and spelled >= ECHO_WORDS
                        and spelled >= ECHO_RETURN * min(len(history[j]), len(grid))):
                    give_up |= grid & history[j]
            give_up.discard(seed_word)
            if not give_up:
                break
            # The most worn first, then the shortest.
            order = lambda w: (-uses[w], len(w), w)
            trimmed = trim_one(placed, seed_word, value=order, only=give_up)
            if trimmed is None:
                # Every such word holds the grid together: lay the rest out again without one of
                # them, in the same order, as long as that still makes the minimum.
                spec = specs[i]
                rng = random.Random(gen.seed * 7919 + len(history))
                for w in sorted(give_up, key=order):
                    layout = layout_words(sorted(grid - {w}), seed_word, rng, spec.max_rows, spec.max_cols, 48)
                    candidate = layout.normalized() if layout is not None else []
                    if len(candidate) >= floor:
                        trimmed = candidate
                        break
                if trimmed is None:
                    break
            gen.record(grid - {w for w, *_ in trimmed}, keys[i], -1)
            placed = trimmed
        series[i] = (seed_word, placed)
        grid = {w for w, *_ in placed}
        for w in grid:
            uses[w] += 1
            puzzles_with[w].append(len(history))
        history.append(grid)
    return series


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lang", required=True, choices=sorted(ALPHABETS))
    ap.add_argument("--levels", type=int, default=1200)
    ap.add_argument("--daily", type=int, default=400)
    ap.add_argument("--seed", type=int, default=20261102)
    ap.add_argument("--sources", type=Path, default=Path(__file__).parent / ".sources")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--any-python", action="store_true",
                    help=f"run on another Python than {PYTHON_VERSION[0]}.{PYTHON_VERSION[1]} (the packs may differ)")
    args = ap.parse_args()
    if sys.version_info[:2] != PYTHON_VERSION and not args.any_python:
        raise SystemExit(f"The packs are made with Python {PYTHON_VERSION[0]}.{PYTHON_VERSION[1]}, which keeps them "
                         f"reproducible; this is {sys.version.split()[0]}. Pass --any-python to run anyway.")

    check_sources(args.sources)
    t0 = time.time()
    print(f"[{args.lang}] building lexicon…", file=sys.stderr)
    lex = build_lexicon(args.lang, args.sources)
    print(f"[{args.lang}] valid={len(lex.valid)} targets={len(lex.targets)} ({time.time() - t0:.0f}s)",
          file=sys.stderr)

    gen = Generator(lex, args.seed)
    rng = random.Random(args.seed ^ 0x5EED)
    level_specs = [level_spec(i, args.lang) for i in range(args.levels)]
    daily_specs = [daily_spec(i, args.lang) for i in range(args.daily)]
    history: list[set[str]] = []
    with mp.Pool() as pool:
        levels = generate_series(gen, level_specs, "levels", pool)
        levels, keys = promote_finales(levels, gen)
        levels = settle_in_pack_order(levels, level_specs, keys, gen, history, chapters=True)
        daily = generate_series(gen, daily_specs, "daily", pool, cycle=True)
        daily = settle_in_pack_order(daily, daily_specs, [("daily", i) for i in range(args.daily)], gen, history)

    validate_pack(levels, daily, args.lang)
    pack = {"format": FORMAT_VERSION, "language": args.lang, "levels": [], "daily": []}
    for name, series in (("levels", levels), ("daily", daily)):
        for seed_word, placed in series:
            bonus = bonus_words(placed, seed_word, gen)
            validate(placed, seed_word, lex, bonus)
            pack[name].append(to_json(placed, seed_word, bonus, rng))

    args.out.mkdir(parents=True, exist_ok=True)
    out = args.out / f"puzzles-{args.lang}.json"
    # Written aside and moved into place, so that a run stopped halfway never leaves the app a
    # truncated pack.
    partial = out.with_name(out.name + ".partial")
    partial.write_text(json.dumps(pack, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    partial.replace(out)

    sizes = Counter(len(l["letters"]) for l in pack["levels"])
    counts = [len(l["words"]) for l in pack["levels"]]
    distinct = len({w["w"] for l in pack["levels"] for w in l["words"]})
    print(f"[{args.lang}] wrote {out} ({out.stat().st_size // 1024} KB) in {time.time() - t0:.0f}s", file=sys.stderr)
    print(f"[{args.lang}] wheel sizes {dict(sorted(sizes.items()))}; words/level avg "
          f"{sum(counts) / max(1, len(counts)):.1f}; distinct grid words {distinct}", file=sys.stderr)


if __name__ == "__main__":
    main()
