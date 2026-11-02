import Foundation
import Testing
@testable import crosswords

/// Validates every bundled puzzle against the invariants the game relies on.
struct PuzzlePackTests {
    /// The figures the App Store listing and the README promise.
    @Test(arguments: PuzzleLanguage.allCases)
    func packHasTheAdvertisedContent(language: PuzzleLanguage) throws {
        let pack = try PuzzlePack.load(language)
        #expect(pack.language == language.rawValue)
        #expect(pack.levels.count == 1_200)
        #expect(pack.levels.count % Chapter.size == 0, "the last chapter would be short")
        #expect(pack.daily.count == 400)
    }

    @Test(arguments: PuzzleLanguage.allCases)
    func everyPuzzleIsWellFormed(language: PuzzleLanguage) throws {
        let pack = try PuzzlePack.load(language)
        let series = pack.levels.enumerated().map { ("level \($0.offset)", $0.element) }
            + pack.daily.enumerated().map { ("daily \($0.offset)", $0.element) }
        let issues = series.compactMap { name, puzzle in
            let problems = Self.problems(in: puzzle, language: language)
            return problems.isEmpty ? nil : "\(name): \(problems)"
        }
        #expect(issues.isEmpty, "\(language.rawValue): \(issues.count) bad puzzles, e.g. \(issues.prefix(10))")
    }

    @Test(arguments: PuzzleLanguage.allCases)
    func difficultyRampsUp(language: PuzzleLanguage) throws {
        let pack = try PuzzlePack.load(language)
        let sizes = pack.levels.map(\.letters.count)
        #expect(sizes.prefix(3).allSatisfy { $0 == 3 })
        #expect(sizes.prefix(12).allSatisfy { $0 <= 4 })
        let late = sizes.suffix(100)
        #expect(Double(late.reduce(0, +)) / Double(late.count) >= 6)
        // The wheels grow all the way to seven letters: from the 19th chapter on, every finale has one.
        for start in stride(from: 18 * Chapter.size, to: sizes.count, by: Chapter.size) {
            #expect(sizes[start + Chapter.size - 1] == 7, "\(language.rawValue) chapter \(start / Chapter.size + 1)")
        }
        // A saw-tooth: each chapter ends with its biggest wheel, and once wheels have grown, it
        // also opens gently.
        for start in stride(from: 0, to: sizes.count, by: Chapter.size) {
            let chapter = sizes[start..<min(start + Chapter.size, sizes.count)]
            let name = "\(language.rawValue) chapter \(start / Chapter.size + 1): \(Array(chapter))"
            #expect(chapter.last == chapter.max(), "\(name)")
            if start >= 6 * Chapter.size {
                #expect(chapter.prefix(2).max() ?? 0 < chapter.max() ?? 0, "\(name)")
            }
        }
        // …and its finale is the chapter's biggest grid, whatever the wheels of the others.
        for start in stride(from: 0, to: pack.levels.count, by: Chapter.size) {
            let chapter = pack.levels[start..<min(start + Chapter.size, pack.levels.count)]
            guard let finale = chapter.last else { continue }
            #expect(chapter.allSatisfy { $0.words.count <= finale.words.count },
                    "\(language.rawValue) chapter \(start / Chapter.size + 1): \(chapter.map(\.words.count))")
        }
    }

    /// Daily puzzles are as big as the late journey's levels: Czech ones always have seven letters
    /// (a six-letter Czech wheel spells too few base forms), English ones six, and seven twice a week.
    @Test(arguments: PuzzleLanguage.allCases)
    func dailyWheelsAreBig(language: PuzzleLanguage) throws {
        let pack = try PuzzlePack.load(language)
        let sizes = pack.daily.map(\.letters.count)
        switch language {
        case .czech:
            #expect(sizes.allSatisfy { $0 == 7 }, "\(Set(sizes))")
        case .english:
            #expect(sizes.allSatisfy { (6...7).contains($0) }, "\(Set(sizes))")
            #expect(sizes.filter { $0 == 7 }.count == pack.daily.indices.filter { [5, 6].contains($0 % 7) }.count)
        }
    }

    /// Every tier of the achievements a journey fills can be reached in one language's journey,
    /// without waiting months for daily puzzles: the crossword words (a twentieth of them left
    /// for hints, whose words don't count), the seven-letter words, the levels and the chapters.
    @Test(arguments: PuzzleLanguage.allCases)
    func journeyAchievementsCanBeCompletedOnTheJourney(language: PuzzleLanguage) throws {
        let pack = try PuzzlePack.load(language)
        let words = pack.levels.flatMap(\.words)
        let available: [(Achievement, Int)] = [
            (.wordsmith, words.count * 95 / 100),
            (.longHaul, words.filter { $0.length >= 7 }.count * 95 / 100),
            (.trailblazer, pack.levels.count),
            (.explorer, pack.levels.count / Chapter.size),
        ]
        for (achievement, count) in available {
            let top = try #require(achievement.thresholds.last)
            #expect(top <= count, "\(language.rawValue) \(achievement): \(top) asked, \(count) on the journey")
        }
    }

    /// A regression guard for the generator's block lists: vulgar words may not appear at all,
    /// mildly crude ones only as bonus words.
    @Test(arguments: PuzzleLanguage.allCases)
    func puzzlesAreFamilyFriendly(language: PuzzleLanguage) throws {
        let pack = try PuzzlePack.load(language)
        let prefixes: [String], exact: Set<String>, notInGrid: Set<String>
        switch language {
        case .czech:
            // Every stem written out in `BLOCKED_PREFIXES` in curation.py, except "heroin", which lets
            // "heroina" (a heroine) through, a sample of the verb prefixes it puts on the worst verbs,
            // and the forms of "srát" and "čumět" that its patterns catch.
            prefixes = ["KURV", "KUREV", "ZKURV", "PRD", "NEPRD", "SPRD", "MRD", "VYMRD", "JEB", "VYJEB", "POJEB", "ZAJEB",
                        "PÍČ", "PIČ", "KOKOT", "HOVN", "HOVEN", "SRAČ", "SRANÍ", "CHCAN", "CHCÁ", "CHCAL", "CHČIJ", "CHČÍ",
                        "ŠOUST", "ŠUK", "OŠUK", "ZAŠUK", "VYŠUK", "NEŠUK", "ČURÁK", "ČURÁC", "KUND", "BUZN", "BUZER",
                        "HAJZL", "CHUJ", "PIZD", "PRCA", "PRCÁ", "ZMRD", "DĚVK", "DĚVEK", "NEGR", "TEPLOUŠ", "NASRA",
                        "POSRA", "VYSRA", "ZASRA", "USRA", "SESRA", "OBSRA", "PROSRA", "ROZSRA", "NASER", "POSER", "VYSER",
                        "ZASER", "PRŮSER", "PORN", "ONAN", "SEXOV", "BORDEL", "FLUNDR", "DRŽK", "ŠULIN", "OČUM",
                        "KRIPL", "SPERM", "ANÁL", "DEBIL", "KRETÉN", "IDIOT", "BLBC", "CIKÁN", "NACIST", "ZNÁSIL",
                        "SEBEVRA", "VRAH", "VRAŽD", "MRTVOL", "SEXU", "KOKAIN", "EROTIK", "EROTICK", "ŠOURK",
                        "OTROK", "OTROC", "POTRAT", "GESTAP", "PEDOFIL", "NEGŘ", "CIGÁN", "ČUBK", "ČUBEK", "ŠLAPK",
                        "ŠLAPEK", "POŠUK", "POŠUC", "NAŠUK", "PROŠUK", "ŽIDÁK", "ŽIDÁC", "CHCÍP", "EROTIC", "NUDIS",
                        "NASR", "POSR", "VYSR", "ZASR", "ČUMĚ", "ČUMÍ",
                        // The consonant changes of "blbec", "šlapka" and "čubka", and "mrzák".
                        "BLBČ", "ŠLAPC", "ČUBC", "ČUBČ", "MRZÁK", "MRZÁC",
                        // "incest", "nácek" and "sexista" with their words and forms.
                        "INCEST", "NÁCK", "SEXIS",
                        // Verb prefixes on the worst verbs, negated too.
                        "ZJEB", "ROZJEB", "NAJEB", "OJEB", "NEJEB", "POMRD", "ROZMRD", "ZAMRD", "OMRD", "VYŠOUST",
                        "PROŠOUST", "OŠOUST", "VYPRD", "UPRD", "NAPRD", "ZAPRD", "POCHCA", "VYCHCA", "NACHCA", "DOPÍČ"]
            exact = ["SERU", "SEROU", "SERE", "SEREŠ", "SER", "SERME", "SERTE", "NESER", "NESERTE", "OSER", "SRÁT",
                     "SRAL", "SRALA", "SRALI", "SRALO", "SRALY", "NASRÁN", "NASRÁNO", "ČUM", "ČUMTE", "SEXU",
                     "HOMO", "COURA", "COURO", "ŠOUREK", "VRAZI", "DĚVCE",
                     // Forms the dictionary traces to a blocked or vulgar-flagged entry, and the verb
                     // "ojet" with the forms it lists as entries of their own.
                     "BLBČE", "ŠLAPCE", "ČUBCE", "ČUBČÍ", "OBESRAT", "ODESRAT", "SKOPČÁCKÝ", "CIKÁNSKÝ",
                     "OJET", "OJEL", "OJELA", "OJELI", "OJELO", "OJEDE", "OJEDU", "MRZÁK", "MRZÁCI",
                     // A slur and an obscenity the dictionary doesn't flag.
                     "ČMOUD", "PYJ",
                     // A content audit: vocatives used as slurs, a crude word, and a form of a word with a
                     // blocked prefix that its spelling leaves ("otročtí" of "otrocký").
                     "LESBO", "ŽIDE", "NÁCEK", "BĚHNA", "BĚHNY", "OTROČTÍ"]
            notInGrid = ["BLB", "BLBÝ", "MAGOR", "PITOMÝ", "BURAN", "HLUPÁK", "MRCHA", "SVINĚ", "OŽRALA", "OŽRALÝ",
                         "NAHÝ", "NAHOTA", "ORÁLNÍ", "PRSO", "ZADEK", "ZADNICE", "ČŮRAT", "PÉRO", "CHLAST", "ZVRACET",
                         "SRAB", "KSICHT", "PODĚLAT", "PRSNÍ", "LIBIDO", "KONDOM", "MASAKR", "MUČENÍ", "POPRAVA",
                         "OPILEC", "IRENA", "BUDVAR", "ČERNOCH", "RASISTA", "KRAVINA", "PITVA",
                         "DĚLOHA", "STOLEC", "ŽVANIL", "VOLE", "HOVADO", "HUBA", "TRUS", "PÍCHAT", "ŽRÁT", "ŽIDOVKA",
                         // Grim subjects.
                         "SMRT", "MRTVÝ", "ZEMŘÍT", "ZABÍT", "ZABÍJET", "KAT", "MOR", "JED", "HROB", "RAKEV", "POHŘEB",
                         "ÚNOS", "TEROR", "ZBRAŇ", "PISTOLE", "PUŠKA", "SAMOPAL", "KULOMET", "GRANÁT", "BOMBA", "DROGA",
                         "ZABITÍ", "UMŘÍT", "ÚMRTÍ", "USMRTIT", "VÝSTŘEL", "CHOLERA", "TYFUS", "SODOMA", "ČUBA", "BĚLOCH",
                         // Grave illness, blades, tobacco and spirits, gambling.
                         "NEMOC", "NEMOCNÝ", "INFARKT", "MEČ", "KOPÍ", "DÝKA", "TANK", "TABÁK", "KOUŘIT",
                         "KOUŘENÍ", "VODKA", "RUM", "KASINO", "HAZARD",
                         // …and where they are less obvious: weapons, poisons, illness, drink, gambling.
                         "NÁDOR", "TUMOR", "CHOROBA", "KOMA", "DĚLO", "KUŠE", "MUNICE", "ARZENÁL", "TORPÉDO", "RÁŽE",
                         "KALIBR", "VÝZBROJ", "MINA", "OTRAVA", "ARSEN", "BITÍ", "DUŠENÍ", "OPÍT", "ALKOHOL", "POKER",
                         "LOTERIE", "TIKET", "SÁZKA", "VSADIT", "PÁŘENÍ", "MILENKA", "SLIPY",
                         // A second reading: revenge, kidnapping, spears, bodily words, insults.
                         "POMSTA", "POMSTÍT", "ODPLATA", "UNÉST", "OŠTĚP", "PUBERTA", "STŘEVO", "STŘEVNÍ",
                         "CHROMÝ", "GAUNER", "PLODIT",
                         // A third reading: the skull, explosives and wounds, colloquial words, insults,
                         // the occult and horror, and "lesb-", now a bonus word only.
                         "LEBKA", "ODPÁLIT", "ZRANIT", "ZRANĚNÍ", "KECAT", "POKECAT", "MAKAT", "PAŘIT", "HONIČKA",
                         "NAIVKA", "ŠPRT", "DAREBÁK", "HLOUPÝ", "TLUSTÝ", "OŠKLIVÝ", "SLEPEC", "KOKTEJL", "BRÁCHA",
                         "OKULTNÍ", "DÉMON", "UPÍR", "LESBA", "LESBIČKA", "LESBICKÝ",
                         // A content audit: past tenses, colloquial words, war and fallout, insults, the
                         // skeleton, a cartel and blindness.
                         "VÁL", "BÁL", "VOLEJ", "DOLEJŠÍ", "UKECAT", "SRANDA", "BRÁŠKA", "BARÁK", "PLAC", "MACHR",
                         "PARŤÁK", "ÚLET", "KLASA", "VÁLČENÍ", "SPAD", "ZAJETÍ", "LOTR", "PODIVÍN", "SMOLAŘ",
                         "ODPORNÝ", "SKELET", "KARTEL", "SLEPOTA", "KLÍDEK", "BASA", "EMBRYO", "ODPAL", "VÁLEČNÝ",
                         "ŠIKULKA", "ŠUPLÍK", "ŽENUŠKA",
                         "FABRIKA"]
        case .english:
            prefixes = ["FUCK", "SHIT", "CUNT", "JIZZ", "SMEGM"]
            // Forms the block lists reach only through the inflection rules (a dropped e, a doubled
            // consonant, y → i), and words added to them by hand.
            exact = ["SEXT", "SEXTS", "RAPER", "RAPERS", "NUDER", "NUDEST", "NUDIST", "ORGIES", "SLAVER", "SLAVED",
                     "CRAPPY", "SEXIER", "SLUTTY", "WHORING", "PUSSIES", "PERVERT", "LEWD", "KRAUT", "YID", "SQUAW",
                     "MIDGET", "SPICK", "SHAT", "TARTY", "VAGINAL", "SPERM", "WOG", "WOGS", "SPIK", "SPIKS", "ABO",
                     "ABOS", "LEZ", "LEZZY", "MICK", "MICKS", "SLAVERY", "KAFFIR", "KAFIR", "DARKEY",
                     "SHEENY", "MULATTO", "HONKIE", "POOFTER", "LEZZIE", "SHYLOCK", "JISM", "HOMOSEX", "PISSANT",
                     "SCROTUM", "SCROTA", "TESTES", "PECKER", "FRIG", "FRIGS", "NOOKY", "PORNIER", "LUSTIER",
                     "PENES", "LIMEY", "LIMEYS", "GINK", "GINKS",
                     // The external block list's worst words with their common forms, a guard against
                     // the list not loading, and the spellings and plurals it doesn't list.
                     "COCK", "COCKS", "DICK", "DICKS", "PUSSY", "TWAT", "TWATS", "NIGGER", "NIGGERS", "NIGGA", "WANK",
                     "WANKS", "WANKER", "FAG", "FAGS", "FAGGOT", "SLUT", "SLUTS", "WHORE", "WHORES", "BITCH", "BITCHY",
                     "BITCHES", "BASTARD", "CUM", "TIT", "TITS", "BOOB", "BOOBS", "BOOBIE", "PORN", "PORNO", "RAPE",
                     "RAPED", "RAPIST", "NAZI", "NAZIS", "NAZIFY", "KIKE", "SPIC", "CHINK", "GOOK", "DYKE", "HOMO",
                     "RETARD", "PENIS", "VAGINA", "DILDO", "DILDOE", "ANUS", "ANAL", "SEMEN", "ORGASM", "ORGY",
                     "HORNY", "SEX", "SEXY", "SEXIST", "SEXISTS", "NUDE", "NUDISTS", "JEW", "JEWS", "JEWING",
                     "SCROTAL", "GODDAM", "TITTIE", "WOP", "PAKI", "COON", "BEANER", "GYP", "JAP", "JAPS", "SKANK",
                     "HOOKER", "TRANNY",
                     // Slurs a pack once offered as bonus words, words of the blocked "vulva", "orgy" and
                     // "sex" no inflection rule reaches, and the dictionary's own vulgar entries.
                     "OFAY", "OFAYS", "NANCE", "FAGOT", "FAGOTS", "GIMP", "GIMPY", "GRINGO", "GRINGOS", "WELSH",
                     "WELSHER", "ORGIC", "DESEX", "VULVAE", "VULVAL", "VULVAR", "ASSHOLE",
                     // Slurs the lexicon accepted before any wheel spelled them, and a vulgar word that
                     // was a bonus word.
                     "SAMBO", "SAMBOS", "BOCHE", "BOCHES", "GREASER", "CHOLO", "CHOLOS", "BUCKRA", "BUCKRAS",
                     "POMMY", "POMMIES", "TURD", "TURDS",
                     // A content audit: the Nazi salute, slang for heroin and meth, a French obscenity,
                     // slurs, and words the prefixes and suffixes of blocked words make.
                     "HEIL", "HEILS", "SKAG", "SCAG", "METH", "MERDE", "GOY", "GOYIM", "SHIKSA", "BINT", "BINTS",
                     "MESTEE", "FAGIN", "GIP", "GIPS", "LECH", "SWIVE", "QUEAN", "EROTIZE", "UNSEX", "UNSEXY",
                     "ANTISEX", "SEXLESS", "ANALITY", "ENSLAVE", "BEDAMN", "DEBONER",
                     // The Yiddish "bastard", and "nigh"'s comparative, which reads as a slur at a
                     // glance: bonus words of a regenerated pack.
                     "MOMSER", "MOMSERS", "MOMZER", "MOMZERS", "MAMZER", "NIGHER"]
            notInGrid = ["FART", "FARTS", "FARTING", "POOP", "POOPS", "POOPING", "BUM", "BUMS",
                         "IDIOT", "IDIOTIC", "MORON", "LOSER", "SCUM", "SCUMBAG", "PSYCHO", "WEIRDO", "REDNECK",
                         "PRICK", "NAKED", "ORAL", "ORALLY", "BREAST", "STUPID", "DUMB", "WALLY", "CONDOM", "DOUCHE",
                         "HERPES", "TORTURE", "NOOSE", "JUNKIE", "COWARD", "RACIST", "SAVAGES", "UTERUS",
                         "FETUS", "GUNSHOT", "WIENER", "GYPSIES", "FANNY", "SHAG", "WILLY",
                         // Grim subjects and underwear.
                         "KILL", "KILLED", "KILLER", "DEAD", "DEATH", "DIE", "DIED", "DYING", "GRAVE", "COFFIN", "GUN",
                         "GUNS", "SHOTGUN", "PISTOL", "RIFLE", "BULLET", "WEAPON", "BOMB", "NUKE", "ARSON", "DROWN",
                         "POISON", "DRUG", "DRUGS", "ADDICT", "ABUSE", "ABUSIVE", "CANCER", "DISEASE", "PLAGUE", "THUG",
                         "TERROR", "RACISM", "BRA", "THONG", "VIRGIN", "SCREWED", "DUNG", "GORE", "WOMB", "FETAL",
                         "GUNFIRE", "GUNMEN", "GUNNER",
                         // Burial, grave illness, blades, kidnapping, tobacco and spirits, gambling.
                         "BURY", "BURIED", "COMA", "SWORD", "SWORDS", "SPEAR", "SPEARS", "RANSOM", "VAPE", "TOBACCO",
                         "CIGAR", "WHISKEY", "RUM", "GIN", "CASINO", "GAMBLE",
                         // …and where they are less obvious: weapons, death, illness, spirits, gambling.
                         "AMMO", "ARSENAL", "CANNON", "TORPEDO", "LETHAL", "FATAL", "PERISH", "HOSPICE", "MARTYR",
                         "CHEMO", "TEQUILA", "SCOTCH", "SMOKING", "POKER", "LOTTERY", "WAGER", "BETTING", "ANTE",
                         "SAVAGE", "OBESITY", "LIBIDO", "BROTHEL", "JACKASS", "BIKINI", "BOOTY", "HOES",
                         // A second reading: betting, illness and harm, weapons, insults, underwear.
                         "BET", "BETS", "URN", "PALSY", "CHOKE", "BLEED", "FAMINE", "LESIONS", "TOXIC", "VIOLENT",
                         "WARSHIP", "ARMORY", "STALKER", "SWINE", "HOE", "LIAR", "FOOL", "BRAT", "NERD", "NERDY",
                         "FREAK", "BOXERS", "BLADDER", "PELVIC",
                         // A third reading: insults, war and wounds, explosives and poisons, the skull,
                         // horror, slang, underwear, and the everyday words the external list blocked,
                         // now bonus words only.
                         "FAT", "UGLY", "GEEK", "JERK", "WARFARE", "WARTIME", "RAMPAGE", "AMBUSH", "MILITIA", "WOUNDS",
                         "WOUNDED", "INJURED", "ILLNESS", "REHAB", "FALLOUT", "EXPLODE", "TOXIN", "SKULL", "HIJACK",
                         "REVENGE", "ZOMBIE", "VAMPIRE", "DEMON", "SWAG", "BOOMERS", "FREAKY", "FREAKED", "BUSTER",
                         "PSYCH", "BRIEFS", "GAY", "SUCK", "SUCKS", "ESCORT", "ESCORTS", "SNATCH", "NIPPLE",
                         // A content audit: forms of the words above, "lame", "devil" and "creepy".
                         "FATTER", "FATTEST", "UGLIER", "UGLIEST", "GEEKY", "FOOLISH", "PSYCHED", "INJURY", "LAME",
                         "DEVIL", "DEVILS", "CREEPY", "SEPTIC", "RACIAL", "RAFFLE", "POSTWAR", "DRINKER"]
        }
        func isVulgar(_ word: String) -> Bool { exact.contains(word) || prefixes.contains { word.hasPrefix($0) } }
        for puzzle in pack.levels + pack.daily {
            let grid = puzzle.words.map(\.text)
            let offending = grid.filter { isVulgar($0) || notInGrid.contains($0) } + puzzle.bonus.filter(isVulgar)
            #expect(offending.isEmpty, "\(language.rawValue) \(String(puzzle.letters)): \(offending)")
        }
    }

    /// Words from a nearby level are the repetition a player notices; the generator keeps each
    /// grid word out of the ten puzzles on either side unless the wheel has nothing else. The daily
    /// rotation starts over after its last puzzle, so there the first ones follow the last.
    @Test(arguments: PuzzleLanguage.allCases)
    func neighbouringPuzzlesRarelyShareWords(language: PuzzleLanguage) throws {
        let pack = try PuzzlePack.load(language)
        // Percentages. The daily puzzles are planned after the journey, from the wheels it left.
        for (name, puzzles, tenLimit, cycles) in [("levels", pack.levels, Self.levelNeighbourLimit, false),
                                                  ("daily", pack.daily, Self.dailyNeighbourLimit, true)] {
            let grids = puzzles.map { Set($0.words.map(\.text)) }
            let count = grids.count
            func before(_ index: Int, _ step: Int) -> Int? {
                cycles ? (index - step + count) % count : (index - step >= 0 ? index - step : nil)
            }
            let previous = grids.indices.filter { index in
                before(index, 1).map { !grids[index].isDisjoint(with: grids[$0]) } ?? false
            }.count
            let lastTen = grids.indices.filter { index in
                (1...10).contains { step in before(index, step).map { !grids[index].isDisjoint(with: grids[$0]) } ?? false }
            }.count
            #expect(previous * 100 <= grids.count * 2, "\(language.rawValue) \(name): \(previous) share a word with the previous one")
            #expect(lastTen * 100 <= grids.count * tenLimit, "\(language.rawValue) \(name): \(lastTen) share a word with one of the ten before")
        }
    }

    /// A puzzle doesn't come back, however far back it was: of an earlier puzzle whose words a wheel
    /// spells half of or more (of the smaller of the two grids), the generator takes at most two
    /// unless the grid needs more to reach its minimum. Counted over every pair of a language's
    /// 1,600 puzzles: how many share four words or more that make up half of the smaller grid, and
    /// the most words two grids share.
    @Test(arguments: PuzzleLanguage.allCases)
    func puzzlesDoNotComeBack(language: PuzzleLanguage) throws {
        let pack = try PuzzlePack.load(language)
        let grids = (pack.levels + pack.daily).map { Set($0.words.map(\.text)) }
        var puzzlesWith: [String: [Int]] = [:]
        var echoes: [String] = [], most = 0
        for (index, grid) in grids.enumerated() {
            var shared: [Int: Int] = [:]
            for word in grid {
                for earlier in puzzlesWith[word, default: []] { shared[earlier, default: 0] += 1 }
                puzzlesWith[word, default: []].append(index)
            }
            for (earlier, count) in shared {
                most = max(most, count)
                if count >= 4, count * 2 >= min(grid.count, grids[earlier].count) {
                    echoes.append("\(index)~\(earlier)")
                }
            }
        }
        let (echoLimit, mostLimit) = Self.echoLimits[language] ?? (0, 0)
        #expect(echoes.count <= echoLimit, "\(language.rawValue): \(echoes.count) pairs, e.g. \(echoes.prefix(5)) (puzzles counted levels first)")
        #expect(most <= mostLimit, "\(language.rawValue): two grids share \(most) words")
    }

    /// The generator keeps a word already in twelve puzzles to making up a grid's minimum, and uses
    /// none in more than thirty (`SPENT` in generate.py) of a language's 1,600 puzzles.
    @Test(arguments: PuzzleLanguage.allCases)
    func noWordIsWornOut(language: PuzzleLanguage) throws {
        let pack = try PuzzlePack.load(language)
        var uses: [String: Int] = [:]
        for puzzle in pack.levels + pack.daily {
            for word in Set(puzzle.words.map(\.text)) { uses[word, default: 0] += 1 }
        }
        let worn = uses.filter { $0.value > Self.wornOutLimit }
        #expect(worn.isEmpty, "\(language.rawValue): \(worn.sorted { $0.value > $1.value }.prefix(10))")
    }

    /// Words a player would not take for an answer: a contraction without its apostrophe, an
    /// abbreviation, a British or archaic word in the American list, a name, the rarer of two Czech
    /// spellings, an archaic Czech word.
    @Test(arguments: PuzzleLanguage.allCases)
    func gridWordsReadAsWords(language: PuzzleLanguage) throws {
        let pack = try PuzzlePack.load(language)
        let odd: Set<String> = switch language {
        case .english: ["WHATS", "CANT", "WONT", "PICS", "REFS", "REPS", "AMPS", "SIM", "SIMS", "YEA", "NAY", "MUM",
                        "GRAN", "LOO", "BLOKE", "TONNE", "WHILST", "PENCE", "LAIRD", "THY", "THINE", "SHALT", "OFT",
                        "UNTO", "PSI", "TRUMP", "NELSON", "CARTER", "COOPER", "TURNER", "MARIA", "PETER", "HARRY", "SALLY",
                        // Names, places and nationalities, abbreviations and prefixes, British and archaic
                        // words, interjections and clippings.
                        "WALES", "WELSH", "DUTCH", "SOVIET", "ULSTER", "SURREY", "OXFORD", "TED", "TOM", "MAC",
                        "GRAHAM", "NEWTON", "ROMEO", "SMITH", "IDS", "GEN", "TRANS", "ANTI", "STAT", "MID", "AYE",
                        "WEE", "NIGH", "SOD", "DAFT", "SHIRE", "FIRTH", "TAT", "EARL", "DALE", "GLEN", "LADS", "OOPS",
                        "GEE", "DOC", "GAL", "DUDE",
                        // A second reading: interjections, British and archaic words, prefixes and
                        // clippings, foreign currencies, names.
                        "HEY", "WOW", "BYE", "HECK", "MEOW", "AMEN", "HELLO", "ALRIGHT", "ADVERT", "VEG", "SIRE",
                        "LIEU", "FRO", "POSH", "TRAM", "BEHOLD", "SEMI", "SUB", "BIO", "MINI", "MULTI", "HYPER",
                        "AMINO", "INFO", "PREP", "PROMO", "ADMIN", "SYNC", "GLAM", "CARBS", "SAX", "THETA", "YEN",
                        "PESO", "EURO", "FRANC", "AUGUST", "SABBATH", "MARTIAN", "BIBLE", "MESSIAH",
                        // A third reading: plurals whose frequency is a name's or a team's, names, titles.
                        "CAIRNS", "SEARS", "PARSONS", "PACERS", "STOKES", "STILES", "BRAVES", "DODGERS",
                        "PACKERS", "RAIDERS", "BRONCOS", "MARLINS", "ORIOLES", "STEIN", "SERGE", "JASPER", "BARKER",
                        "KAISER", "OTTOMAN",
                        // A content audit: names, places and teams, titles, Greek letters, "whites" and
                        // "boomer", British words and "-wards", clippings, brands, an interjection.
                        "FRANK", "DON", "DONS", "NICK", "VICTOR", "WARREN", "HOMER", "CHINA", "LEAFS", "BROWNS",
                        "COLTS", "TITANS", "REDS", "ROYALS", "RAVENS", "POTTER", "MASON", "DYER", "SHAH", "SULTAN",
                        "SIGMA", "WHITES", "BOOMER", "UPWARDS", "TOWARDS", "ISLE", "ISLES", "JUMPER", "CAM", "ALUM",
                        "RAD", "MART", "FIAT", "CANTON", "CAPITOL", "SIERRA", "DRAKE", "MADDEN", "ROWAN", "YES",
                        "BOLOGNA", "HAMLET", "KELVIN", "JAY", "TRIBUNE", "MUSTANG", "RANGERS", "THEREOF",
                        "CORONA", "COLOGNE", "INDIES", "CHATEAU", "FIESTA", "IMAM", "HEREIN", "THEREIN",
                        "GRANDMA", "GRANNY", "AUNTIE", "PAPA", "DADDY"]
        case .czech: ["ARCHÍV", "BALKON", "KURS", "KONKURS", "VITAMIN", "MILIÓN", "STADIÓN", "ŠAMPÓN", "ZEMAN", "FORMAN",
                      "JARKA", "BORKA", "KORÁN", "ESTER", "SLÁVKA", "KÁČA", "BLANKA", "JANEK", "VÍT", "LEČ", "LÁN", "BOL",
                      // Names, places and nationalities, archaic words, prefixes, fragments.
                      "PORTA", "RUS", "TUREK", "POLÁK", "FIALA", "PLZEŇ", "ZLÍNSKÝ", "PRAŽSKÝ", "KATAR", "ASTRA",
                      "MSTA", "LUKA", "VOJ", "PRVÝ", "NEBESA", "SEČ", "MAKRO", "ELEKTRO", "MOTO", "FATA",
                      // A second reading: place and nationality adjectives, language names,
                      // interjections, clippings, a title.
                      "ČESKÝ", "BRITSKÝ", "ARABSKÝ", "POLSKÝ", "ITALSKÝ", "NORSKÝ", "TURECKÝ", "ŘÍMSKÝ",
                      "RUŠTINA", "ČEŠTINA", "NĚMČINA", "PARDON", "VIDA", "AHOJ", "HURÁ", "MATIKA", "ÁČKO",
                      "BÉČKO", "CHÁN",
                      // A third reading: words whose frequency is a surname's, foreign currencies.
                      "PAŘÍZEK", "HOMOLKA", "SLÁDEK", "STRNAD", "KALOUS", "KUDRNA", "TESAŘÍK", "PALEČEK", "KOLÁŘ",
                      "VALÁŠEK", "RUBL", "DOLAR", "EURO",
                      // A content audit: names and places, a word only of set phrases.
                      "VLČEK", "KOMÁREK", "HRÁDEK", "KUPKA", "KRUPKA", "VODIČKA", "PODLESÍ", "OTAVA", "KALINA",
                      "KROUPA", "SKALICE", "SLATINA", "ORLÍK", "LIPKA", "LOUČKA", "ODIV", "KOREC", "ŠPITÁL",
                      "MNÍŠEK", "ORLICE", "MESIÁŠ", "JITRO", "ZELINKA", "PODRUČÍ"]
        }
        let found = Set((pack.levels + pack.daily).flatMap { $0.words.map(\.text) }).intersection(odd)
        #expect(found.isEmpty, "\(language.rawValue): \(found.sorted())")
    }

    /// Abbreviations and symbols the Czech dictionary accepts so that a spell check passes "cca" or
    /// "zool." in running text: they are no words, and are not accepted even as bonus words.
    @Test func bonusWordsAreWords() throws {
        let pack = try PuzzlePack.load(.czech)
        let notWords: Set<String> = ["DTO", "DTTO", "MST", "CCA", "CCM", "DKG", "TBC", "WWW", "HTTP", "KCAL", "MMOL",
                                     "MBAR", "PPM", "DPI", "RBL", "VVN", "BTO", "ADJ", "ATM", "ZOOL", "GEOL", "BIOL",
                                     "ANAT", "HIST", "PODST", "FILOZ", "ELEKTR"]
        let found = Set((pack.levels + pack.daily).flatMap { $0.bonus }).intersection(notWords)
        #expect(found.isEmpty, "\(found.sorted())")
    }

    /// The Czech dictionary lists some inflected forms as entries of their own; the generator
    /// keeps them out of the grid (they remain bonus words). A sample of them as a regression guard,
    /// transgressives ("sleduje", "jsa", "chtě") included.
    @Test func czechGridUsesBaseForms() throws {
        let pack = try PuzzlePack.load(.czech)
        let forms: Set<String> = ["BOJÍM", "BOJÍME", "JSEM", "JSME", "BYL", "ŠEL", "JDU", "ODEJDU", "POJEDU",
                                  "NAVEDL", "PŘIJAT", "SCHOPEN", "SVÉHO", "JEDNOHO", "SLEDUJE", "JSA", "CHTĚ",
                                  "STOJE", "SEDĚ", "MAJE", "JDA", "NESA", "UKAZUJE", "SMĚŘUJE", "NASTAV",
                                  // Dictionary entries that read as a form of a commoner word ("řada", "volný").
                                  "ŘAD", "PAŽÍ", "VOLNÍ", "HOŘE", "VYBRANÍ", "ZABRÁNÍ", "NIČÍ", "ZMÍNĚNÍ", "UNAVENÍ",
                                  "ZVANÍ", "HÁDEK", "PLÁNÍ", "VÝSTAV", "SKRYT", "POCHOP", "MAZAL",
                                  // Comparatives, of adverbs too, and present participles.
                                  "MENŠÍ", "VĚTŠÍ", "LEPŠÍ", "HORŠÍ", "DELŠÍ", "STARŠÍ", "MLADŠÍ", "VYŠŠÍ", "TENČÍ",
                                  "TVRDŠÍ", "LÍP", "LÉPE", "VÍC", "VÍCE", "MÉNĚ", "DÁL", "DÁLE", "DŘÍV", "DŘÍVE", "VÝŠ",
                                  "NÍŽE", "BLÍŽ", "BLÍŽE", "HŮŘ", "RADŠI", "LEŽÍCÍ", "SPÍCÍ", "JDOUCÍ", "MAJÍCÍ",
                                  // Feminine, neuter and plural forms of pronouns and numerals.
                                  "ONA", "TATO", "TOTO", "TYTO", "TOHLE", "SAMA", "OBĚ", "DVĚ", "MOJE", "TVOJE", "SVOJE",
                                  "VŠE", "VŠECHNO", "VDANÁ",
                                  // A plural ("akta" of "akt"), participles, predicative colour forms.
                                  "AKTA", "VROUCÍ", "ŽIVOUCÍ", "BÍLO", "ČERNO", "ČERVENO", "ŽLUTO", "ZELENO", "KRÁSNO",
                                  "MODRO", "SKLÁNÍ"]
        let grids = (pack.levels + pack.daily).map { Set($0.words.map(\.text)) }
        let found = grids.reduce(into: Set<String>()) { $0.formUnion($1) }.intersection(forms)
        #expect(found.isEmpty, "\(found.sorted())")
        // Of two forms of a word, only the standard one is a grid word, so a grid never offers both.
        let variants = ["BRZO", "TAKY", "ZEM", "BANK", "BUS", "ZNOVA", "DNESKA", "ASPOŇ", "JENOM", "KAFE", "ODSUD",
                        "VLONI", "VŽDYCKY", "LIDI", "POLÍVKA", "POMOCT", "SPÍŠE", "ŘÍCI",
                        "VELIKÝ", "DÍKY", "MAMKA", "MAMINA", "PŮLE", "FOUSEK", "CENĚNÝ", "JELENÍ"]
        let colloquial = grids.reduce(into: Set<String>()) { $0.formUnion($1) }.intersection(variants)
        #expect(colloquial.isEmpty, "\(colloquial.sorted())")
        // Nor does a grid hold two words that read as forms of one word: many entries are also a
        // form of another ("pilota", a pile, is the genitive of "pilot"). A sample of such pairs.
        let pairs = [("PILOT", "PILOTA"), ("ROBOT", "ROBOTA"), ("KMOTR", "KMOTRA"), ("KLASIK", "KLASIKA"),
                     ("MASO", "MASA"), ("KOS", "KOSA"), ("TRIBUN", "TRIBUNA"), ("RÁNO", "RÁNA"), ("LÍC", "LÍCE"),
                     ("ŠÁL", "ŠÁLA"),
                     // A verb and the adjective of its passive participle or its verbal noun, entries
                     // of their own.
                     ("SKRÝT", "SKRYTÝ"), ("UKRÝT", "UKRYTÝ"), ("KRYT", "KRYTÝ"), ("KRÝT", "KRYTÝ"), ("DÁT", "DANÝ"),
                     ("PRODAT", "PRODANÝ"), ("ZVOLIT", "ZVOLENÝ"), ("PLATIT", "PLACENÝ"), ("DOŽÍT", "DOŽITÍ"),
                     ("PŘEŽÍT", "PŘEŽITÍ"), ("UŽÍT", "UŽITÍ"), ("VYUŽÍT", "VYUŽITÍ"), ("PROŽÍT", "PROŽITÍ"),
                     ("ŽÍT", "ŽITÍ"), ("PŘÁT", "PŘÁNÍ"), ("ČÍST", "ČTENÍ")]
        let together = grids.flatMap { grid in pairs.filter { grid.contains($0.0) && grid.contains($0.1) } }
        #expect(together.isEmpty, "\(together.map { "\($0.0)+\($0.1)" })")
    }

    /// The largest grid the generator lays out (a seven-letter wheel's), which the game's layout
    /// still fits on the smallest iPhone.
    static let maxRows = 10, maxCols = 11

    /// Percentages of puzzles sharing a word with one of the ten before, with room above what the
    /// shipped packs have (levels: none in English, 4 % in Czech, whose grids leave out more forms
    /// and subjects than its vocabulary can easily spare; daily puzzles: none and 2 %), and the most
    /// puzzles one grid word may appear in (the generator's cap).
    static let levelNeighbourLimit = 6, dailyNeighbourLimit = 4, wornOutLimit = 30

    /// For `puzzlesDoNotComeBack`: how many pairs of puzzles may share four words or more that make
    /// up half of the smaller grid, and the most words two grids may share, with room above the
    /// shipped packs (English: 7 pairs of the 1.3 million, five words at most; Czech: 149 and five,
    /// most of them grids at their minimum, which the late wheels reach only with words the
    /// journey has used already).
    static let echoLimits: [PuzzleLanguage: (pairs: Int, words: Int)] = [.english: (20, 6), .czech: (200, 6)]

    static let alphabets: [PuzzleLanguage: Set<Character>] = [
        .english: Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
        .czech: Set("AÁBCČDĎEÉĚFGHIÍJKLMNŇOÓPQRŘSŠTŤUÚŮVWXYÝZŽ"),
    ]

    static func problems(in puzzle: Puzzle, language: PuzzleLanguage) -> [String] {
        var problems: [String] = []
        let wheel = Self.counts(puzzle.letters)
        if !(3...7).contains(puzzle.letters.count) { problems.append("wheel size \(puzzle.letters.count)") }
        let alphabet = Self.alphabets[language] ?? []
        if !puzzle.letters.allSatisfy(alphabet.contains) { problems.append("wheel \(String(puzzle.letters)) outside the alphabet") }
        if Set(puzzle.letters).count < 2 { problems.append("wheel of one letter") }
        let texts = puzzle.words.map(\.text)
        if Set(texts).count != texts.count { problems.append("duplicate grid words") }
        if puzzle.words.isEmpty { problems.append("no words") }

        var grid: [GridPoint: Character] = [:]
        for word in puzzle.words {
            if word.length < LevelSession.minimumWordLength { problems.append("\(word.text) too short") }
            if word.text != word.text.uppercased() { problems.append("\(word.text) not uppercase") }
            if !Self.fits(Self.counts(word.letters), in: wheel) { problems.append("\(word.text) not formable") }
            if word.start.row < 0 || word.start.col < 0 { problems.append("\(word.text) starts off the grid") }
            for (cell, letter) in zip(word.cells, word.letters) {
                if let existing = grid[cell], existing != letter { problems.append("conflict at \(cell)") }
                grid[cell] = letter
            }
        }
        let board = Board(puzzle: puzzle)
        if board.rows > Self.maxRows || board.cols > Self.maxCols { problems.append("grid \(board.rows)×\(board.cols)") }
        // The grid starts at row 0 and column 0, so the game centres it correctly.
        if !puzzle.words.isEmpty, board.cells.map(\.row).min() != 0 || board.cells.map(\.col).min() != 0 {
            problems.append("grid not normalized")
        }
        // The wheel is one of the answers' letters exactly: the seed word is always on the board.
        if !puzzle.words.contains(where: { Self.counts($0.letters) == wheel }) { problems.append("no word uses the whole wheel") }
        // A word never sits inside a longer run of letters (CAT within CATS).
        for word in puzzle.words {
            let (dr, dc) = word.direction == .across ? (0, 1) : (1, 0)
            let before = GridPoint(row: word.start.row - dr, col: word.start.col - dc)
            let after = GridPoint(row: word.start.row + dr * word.length, col: word.start.col + dc * word.length)
            if grid[before] != nil || grid[after] != nil { problems.append("\(word.text) is part of a longer run") }
        }
        for bonus in puzzle.bonus {
            if texts.contains(bonus) { problems.append("\(bonus) is both grid and bonus") }
            if bonus.count < LevelSession.minimumWordLength { problems.append("bonus \(bonus) too short") }
            if !bonus.allSatisfy(alphabet.contains) { problems.append("bonus \(bonus) outside the alphabet") }
            if !Self.fits(Self.counts(Array(bonus)), in: wheel) { problems.append("bonus \(bonus) not formable") }
        }
        // Every horizontal or vertical run of two or more letters must be a placed word.
        let placed = Set(puzzle.words.map { "\($0.text)@\($0.start.row),\($0.start.col),\($0.direction.rawValue)" })
        for (cell, _) in grid {
            for direction in [Direction.across, .down] {
                let (dr, dc) = direction == .across ? (0, 1) : (1, 0)
                if grid[GridPoint(row: cell.row - dr, col: cell.col - dc)] != nil { continue }
                var run = ""
                var k = 0
                while let letter = grid[GridPoint(row: cell.row + dr * k, col: cell.col + dc * k)] {
                    run.append(letter)
                    k += 1
                }
                if run.count > 1, !placed.contains("\(run)@\(cell.row),\(cell.col),\(direction.rawValue)") {
                    problems.append("stray run \(run)")
                }
            }
        }
        // All words must form one connected crossword.
        var reached: Set<Int> = [0]
        var frontier = [0]
        let cellSets = puzzle.words.map { Set($0.cells) }
        while let current = frontier.popLast() {
            for other in cellSets.indices where !reached.contains(other) && !cellSets[current].isDisjoint(with: cellSets[other]) {
                reached.insert(other)
                frontier.append(other)
            }
        }
        if reached.count != puzzle.words.count { problems.append("grid not connected") }
        return problems
    }

    private static func counts(_ letters: [Character]) -> [Character: Int] {
        letters.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private static func fits(_ need: [Character: Int], in have: [Character: Int]) -> Bool {
        need.allSatisfy { have[$0.key, default: 0] >= $0.value }
    }
}
