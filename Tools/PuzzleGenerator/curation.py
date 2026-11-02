"""
Hand-curated word lists for the puzzle generator.

Keep these lists lowercase. "Blocked" words are never accepted anywhere; "not target"
words are still accepted as bonus words but never appear as grid answers. In English an excluded
word's plain plurals ("pics" of "pic") are excluded with it.
"""
import re

# Words that are not profane but have no place in a relaxing family puzzle grid.
EXTRA_BLOCKED = {
    "en": {
        "rape", "raped", "rapes", "rapist", "nazi", "nazis", "hitler", "slave", "slaves",
        "incest", "jihad", "suicide", "murder", "corpse", "abort", "heroin", "cocaine",
        "porn", "porno", "sexy", "sex", "nude", "nudes", "whore", "pimp", "pimps", "crap",
        "piss", "pissed", "damn", "hell", "bitch", "bastard", "slut", "tit", "tits", "fag",
        "homo", "dyke", "negro", "retard", "spic", "kike", "chink", "wop", "gook",
        "jap", "paki", "coon", "nig", "nigga", "cum", "jizz", "anal", "anus", "semen", "penis",
        "vagina", "dildo", "boob", "boobs", "booby", "horny", "lust", "orgy", "orgasm", "sext",
        "erotica", "orgiac", "nudie", "pervert", "perv", "molest", "lecher", "lewd", "harlot", "hussy",
        "trollop", "strumpet", "bimbo", "bugger", "sexpot", "arse", "goddamn",
        "darky", "honky", "kraut", "dago", "hebe", "yid", "jewed", "gyp", "coolie", "squaw", "redskin",
        "negroid", "spaz", "midget", "mongol", "spick", "shat", "tarty", "vaginal", "sperm",
        "wog", "spik", "abo", "lez", "mick", "slavery", "pedophile", "paedophile",
        # Slurs and obscenities that ENABLE spells in ways the external list doesn't cover.
        "kaffir", "kafir", "darkey", "darkie", "sheeny", "mulatto", "honkie", "poofter", "pooftah",
        "lezzie", "shylock", "fuckup", "jism", "jissom", "gism", "smegma", "homosex", "pissant",
        "spermic", "vaginae", "scrotum", "scrota", "testes", "testis", "penile", "labia", "pecker",
        "frig", "nooky", "nookie",
        # An irregular plural no inflection rule reaches ("penis" → "penes"), and slurs for
        # nationalities that have no innocent sense ("limey", "gink"; "dink" and "nip" do).
        "penes", "limey", "gink",
        # Spellings of blocked words the lists miss, and ENABLE's slur verb "jew" with every form
        # of it (the people are "Jews", a name, which a lowercase list has no entry for).
        "jew", "jews", "jewing", "jewfish", "nazify", "nazified", "dildoe", "dildoes", "goddam",
        "goddams", "tittie", "titties", "boobie", "scrotal",
        # Slurs that the lists above missed and a pack still offered as bonus words ("ofay", "nance",
        # "gimp", the verb "welsh", the spelling "fagot"), and words of the blocked "vulva", "orgy"
        # and "sex" that no inflection rule reaches.
        "ofay", "nance", "fagot", "gimp", "gringo", "welsh", "vulvae", "vulval", "vulvar", "orgic", "desex",
        # The Yiddish "bastard" in ENABLE's spellings, and an archaic comparative of "nigh" that reads
        # as a slur at a glance; both came up as bonus words when the packs were regenerated.
        "momser", "momzer", "mamzer", "nigher",
        # Slurs the lexicon still accepted, though no wheel had spelled them yet, and a vulgar word
        # that was a bonus word ("turd").
        "sambo", "boche", "greaser", "cholo", "buckra", "pommy", "turd",
        # Bonus words a content audit of the packs found (November 2026): the Nazi salute ("heil", as
        # "nazi"), slang for heroin and for meth ("skag", "scag", "meth", as "heroin" and "cocaine"),
        # a French obscenity, slurs ("goy", "shiksa", "bint"; "mestee", as "mulatto"; "fagin", as
        # "shylock"; "gip", as "gyp"), "lech" of the blocked "lecher", archaic words for sex and for
        # a prostitute ("swive", "quean"), and "erotize" of "erotic", which no rule reaches.
        "heil", "heils", "skag", "skags", "scag", "scags", "meth", "meths", "merde", "merdes",
        "goy", "goys", "goyim", "goyish", "shiksa", "shiksas", "shikse", "shikses", "bint", "bints",
        "mestee", "mestees", "fagin", "fagins", "gip", "gips", "lech", "swive", "quean", "queans",
        "erotize", "erotized", "erotizes",
    },
    "cs": {
        "debil", "kretén", "idiot", "blbec", "píča", "zkurvit", "sex", "sexy", "porno",
        "nacista", "hitler", "vrah", "vražda", "znásilnit", "sebevrah", "kokain", "heroin",
        "cikán", "negr", "teplouš", "buzerant", "děvka", "kurva", "hovno", "prdel", "sračka",
        "sexem", "sexe", "sexshop", "homo", "cour", "coura", "couro", "coury", "couře",
        "couru", "courou", "šourek",
        # Forms the prefixes below miss because the stem changes ("vrah" → "vrazi", "děvka" → "děvce").
        "vrazi", "vrazích", "děvce",
        # A slur for a disabled person, and the verb whose vulgar sense outweighs "to wear down by
        # driving" ("ojetý", a used car, is an entry of its own and stays). The dictionary lists
        # the verb's past and present forms as entries of their own ("ojel", "ojedu").
        "mrzák", "ojet", "ojel", "ojedu",
        # A slur for the Roma and an obscenity, neither flagged as vulgar by the dictionary. ("Štětka"
        # stays a bonus word: it is first of all a brush.)
        "čmoud", "pyj",
        # Found by the same audit: "incest" (blocked in English), the vocative "lesbo" (the English
        # slur) and the vocative "žide", used as an insult ("žid", of the faith, stays), slang for a
        # Nazi ("nácek", as "nacista") and a crude word for a prostitute ("běhna", as "děvka").
        "incest", "lesbo", "žide", "nácek", "běhna",
    },
}

# Czech words are also blocked whenever the Czech dictionary traces them to a blocked entry: one of
# the words above, or one it flags itself as vulgar (NOSUGGEST, "w": "srát", "cikán", "skopčácký").
# That reaches every inflected form, those whose consonants change too ("blbče" of "blbec",
# "šlapce" of "šlapka"), which no prefix can. English inflections are covered by `en_stems`.

# Words a block list catches by mistake: "heroina" is not "heroin", and "píchat" (to sting) and
# "žrát" (to eat, of animals) are crude at most, which is fine for a bonus word. "Dršťky" (tripe)
# and "courám" (of "courat", to dawdle) only share their spelling with a form of a blocked word.
# The external English list has everyday words for their slang senses: "suck" (while "sucked" and
# "sucking" are valid), "escort", "snatch", and "nipple" (as "breast" is); they are valid bonus
# words, kept out of the grid below.
NOT_BLOCKED = {
    "en": {"suck", "sucks", "escort", "escorts", "snatch", "nipple", "nipples",
           # A prefix taken off leaves a blocked word, but the word is one of its own (to strip bare).
           "denude", "denudes", "denuder"},
    "cs": {"heroina", "heroiny", "heroině", "heroinou", "heroinám", "heroinách", "heroinami", "píchat", "žrát",
           "dršťky", "courám"},
}

# Every form of "srát" and "čumět", with any verb prefix and negation ("ser", "neserte",
# "nasrán", "čumte"). The bare stems are too short to block as prefixes: "sraz", "sérum" and
# "čumák" have to stay.
CS_BLOCKED_FORMS = re.compile(r"""
    (ne)?(do|na|o|ob|obe|od|ode|po|pro|roz|se|u|vy|z|za)?
    ( sr[aá](t|l|la|li|lo|ly|n|na|ni|no|ny|ná|né|ný|ní|ním)
    | ser(u|eš|e|eme|ete|ou|me|te)?
    | čum(ět|ěl|ěla|ěli|ělo|ěly|ěj|ějte|í|ím|íš|íme|íte|il|ila|ili|ilo|ily|ilů|ilům|ilové|te|me)?
    )
""", re.X)

# English blocking also catches inflections ("bitch" → "bitchy", "rape" → "raper", "orgy" →
# "orgies"), two steps deep ("porn" → "porny" → "pornier"), and their plurals ("nudists"). These
# words merely look like one, or have an everyday sense a player means ("sucked", "groping in the
# dark", "a damning report"), and stay valid, and so do their own inflections ("cocker" → "cockers").
EN_NOT_INFLECTIONS = {
    "butter", "butters", "butted", "butting", "buttes", "spicy", "spiced", "spicer", "spices", "spicing",
    "luster", "monger", "mongers", "cocker", "cocky", "skeeter", "spunky", "dicker", "titer", "titers",
    "heller", "sexes", "assist", "bustier", "gaily", "gayly", "pimply", "scatter", "scatted",
    "scatty", "slavish", "titter", "titters", "twinkly", "shatter", "shatters",
    "spiked", "spiker", "spikers", "spikes", "spiking", "spiky",
    "crape", "crapes", "jape", "japes", "japed", "japer", "japers", "japing",
    "rapier", "rapiers", "butties", "lustily",
    "sucked", "sucking", "sucker", "cocked", "cocking", "damning", "groped", "groping", "gayer",
    "gayest", "beanery",
}
EN_MODERN = set("""
    email emails emailed blog blogs blogger online offline app apps emoji emojis selfie selfies
    inbox login website webcam webcams podcast hashtag meme memes malware spyware toolbar toolkit
    plugin plugins popup dataset runtime daycare airbag airbags barista cardio cosplay earbuds wiki
    vape vaping texting texted meetup newbie prenup retweet parkour netball mashup closeup babysit
    bitcoin manga glam bling zen halal hijab stepdad stepmom tagline webinar zine hazmat gumball
    airlock airshow airbase kaboom offsite onsite inline multi mega techno tech techs vocab admin
    emo goth goths uni fest fab bicep physio dongle droid phish mugshot scammer stent infill
    gonna wanna dunno gotta kinda sorta lemme outta gotcha betcha
""".split())
# Valid as bonus words, but too informal or archaic to be a grid answer, the family words among
# them as "mom" ("grandma", "auntie", "papa").
EN_INFORMAL = set("""
    tho thru nite yeah yep nope gonna wanna gotta dunno kinda sorta lemme outta gotcha betcha
    ain aint ya yer yous ole hon hun mom moms bro bros sis
    grandma grandmas granny grannies grandpa grandpas auntie aunties aunty papa papas mama mamas
    daddy daddies mommy mommies nana nanas
""".split())

# Common Czech words that Hunspell lists without inflection flags, or with only the form
# flags that `is_cs_lemma` rejects (indeclinables and irregular lemmas), hand-picked so that
# stray inflected forms stay out of the grid. Each is a base form (a pronoun's or numeral's
# masculine one: "tento", "sám", "dva", not "tato", "sama", "dvě"), except five irregular
# plurals a player expects as words of their own: "lidé", "děti", "ruce", "oči" and "uši".
CS_FLAGLESS_KEEP = set("""
    ale tak pro jako jak když nebo jeho aby než ještě také ani pak při tam kde před protože
    podle pokud teď nic mezi proč asi kdy dnes takže však již nad jestli den právě tady
    přes dva proti proto nikdy práce kvůli zde tedy vůbec ano stejně lidé možná pouze tento
    hodně opravdu prostě tři děti což zase trochu dost pořád sebe během hned kdyby několik
    člověk kolem někdy sem snad opět vlastně sám vždy často peníze dlouho hlavně spolu nakonec
    zatím navíc takhle doma celkem nejen přímo kromě nyní kolik mimo poté zároveň zejména kam
    sice včetně znovu dokonce čtyři tolik totiž týden poprvé zcela téměř dítě domů nějak ovšem
    prý skoro půl letos zrovna bohužel dům alespoň přece zda docela oba paní konečně jistě potom
    mnohem naopak pan vedle zpět ruce tehdy buď někde zatímco zítra spíš včera občas rovněž
    přesto brzy daleko finále fajn super tenhle venku velice nicméně okolo vždyť neboť všude
    zhruba oči syn ven pomalu takto teprve dokud zpátky jenže nejprve dosud předtím dvakrát
    úterý uvnitř oproti kdysi náhodou pryč dcera nikam pes avšak též loni anebo dodnes odkud
    dolů bůh ihned nahoru devět doslova akorát blízko nikde pán poněkud pozdě včas poblíž
    zkrátka odtud dopředu mezitím vítr předem stůl zoo zvlášť málem kámen jedině sotva třikrát
    byť ovoce párty naproti vzhůru zeď navždy turné vlevo sníh vzadu vpravo chleba dokola lež
    lev mysl čest uši déšť nahlas pěšky dovnitř zdaleka kůň nůž blázen hrách jinam dvůr skrz
    takřka vcelku sůl kněz kudy kotel tudy zevnitř zprvu vesměs doleva tvrdě jeden
    jinak hezky málo mnoho příliš třeba velmi zřídka přítel rád
""".split())

# Czech is highly inflected, so vulgar stems are matched as prefixes, including the verb
# prefixes ("na-", "po-", "vy-"…) that the bare stems miss.
BLOCKED_PREFIXES = {
    # English compounds of the worst words ("fuckup", "shithead") that no inflection rule reaches.
    "en": ("fuck", "shit", "cunt", "jizz", "smegm"),
    "cs": (
        "kurv", "kurev", "zkurv", "prd", "neprd", "sprd", "mrd", "vymrd", "jeb", "vyjeb", "pojeb", "zajeb",
        "píč", "pič", "kokot", "hovn", "hoven", "srač", "sraní", "chcan", "chcá", "chcal", "chčij", "chčí",
        "šoust", "šuk", "ošuk", "zašuk", "vyšuk", "nešuk", "čurák", "čurác", "kund", "buzn", "buzer",
        # "prca", "prcá": every form of "prcat" ("prcal", "prcá"), while "prcek" (a toddler) stays.
        "hajzl", "chuj", "pizd", "prca", "prcá", "zmrd", "děvk", "děvek", "negr", "teplouš", "nasra", "posra", "vysra",
        "zasra", "usra", "sesra", "obsra", "prosra", "rozsra", "naser", "poser", "vyser", "zaser",
        "průser", "porn", "onan", "sexov", "bordel", "flundr", "držk", "šulin", "očum", "kripl",
        "sperm", "anál",
        # Insults and grim subjects, matching what the English list keeps out.
        "debil", "kretén", "idiot", "blbc", "cikán", "nacist", "znásil", "sebevra", "vrah", "vražd",
        "mrtvol", "sexu", "kokain", "heroin",
        # Matching the English blocks of "erotica", "scrotum", "slave", "abort" and "nazi".
        "erotik", "erotick", "šourk", "otrok", "otroc", "potrat", "gestap", "pedofil",
        # Stems whose consonant changes in inflection ("negr" → "negři") or that take another
        # verb prefix ("po-šuk"), and the slurs and crude words built like them.
        "negř", "cigán", "čubk", "čubek", "šlapk", "šlapek", "pošuk", "pošuc", "našuk", "prošuk",
        # An antisemitic slur ("žid", of the faith, stays), the vulgar "chcípnout" (of people dying)
        # and its insult "chcípák", "erotika" with its k → c ("erotice"), and "nudista", matching
        # the English "nudist".
        "židák", "židác", "chcíp", "erotic", "nudis",
        # The consonant changes of "blbec", "šlapka" and "čubka" ("blbče", "šlapce", "čubce",
        # "čubčí"), and "mrzák" ("mrzáci"); the dictionary check above reaches them as well.
        "blbč", "šlapc", "čubc", "čubč", "mrzák", "mrzác",
        # "incest" with "incestní", "nácek" with its k dropped ("nácka", "náckové"), and "sexista"
        # with "sexismus" (the English "sexist" and "sexism" are blocked as words of "sex").
        "incest", "náck", "sexis",
    ),
}
# The worst verbs with any verb prefix, negated or not ("zjebat", "rozmrdat", "vyšoustat",
# "pochcat", "nejebe"), which a prefix list written out by hand kept missing. Not "smrd-": "smrdět"
# (to stink) is crude at most.
_CS_VERB_PREFIXES = ("", "do", "na", "o", "ob", "od", "po", "pro", "pře", "před", "roz", "s", "se", "u", "v", "vy",
                     "z", "za")
_CS_VULGAR_VERB_STEMS = ("jeb", "mrd", "šoust", "prd", "chca", "chcá", "chčij", "chčí", "šuk", "srač", "píč")
BLOCKED_PREFIXES["cs"] += tuple(sorted({negation + prefix + stem for prefix in _CS_VERB_PREFIXES
                                         for stem in _CS_VULGAR_VERB_STEMS for negation in ("", "ne")}
                                        - {"smrd", "nesmrd"}))

# Valid words that make poor grid answers: abbreviations, names, foreign or archaic words,
# stray inflected forms and anything a player would reasonably call "not a real word".
NOT_TARGET = {
    "en": set("""
        chi cis col cor cos cox deb dis dos dun eff ems hes ifs ins jun lac lam lea lee lei lib
        mas med mil mos nos obi ops ova pap pas phi pic pol pom rec ref reg rem rep res rev sac
        sec sen sic sol tau tel til tor tot ugh uni var wen yin bey bis bop fay git ken nee alt
        amp ave mar eta nah yup huh ooh yum ahs ohs oho aah hmm bah pah ism tis ort rho
        chad coca dell frat gaga hast hath joey lama ling mach mans noel pooh sans shes ting
        tony trey troy vita wont yang yuan kart khan bios alps mars mike rand dong bong fart
        dope coke para poly prof temp sims feds offs yeas nays thee thou doth whom
        farts farted farting poop poops pooped pooping bum bums pee peed peeing pees puke puked
        snot booze drunk drunks bummer bummed randy jerking kink kinks
        idiot idiots idiotic moron morons loser losers scum scumbag scumbags psycho psychos weirdo
        weirdos lunatic cripple cripples redneck rednecks gringo gringos gypsy queer queers prick pricks
        slag slags wench wenches buttock buttocks naked oral orally breast breasts
        stupid dumb dumber dumbest dork chump wally fatty hag condom condoms douche herpes fetish
        arousal aroused crotch groin pubic seduce seduced feces urine vomit pus puss torture noose
        stab stabs stabbed slain gunman sniper snipers gory bloody junkie junkies opium stoned stoner
        coward cowards savages racist racists lesbian uterus uterine charlie molly gunshot obese
        wiener mating fetus genital rectal tampons ovary ovaries ovarian bowel bowels bigot bigots
        hanged
    """.split()),
    "cs": set("""
        alt art bas bos del don dok fet jal jer kur liz man mok pin pit pln pop prs puč ras
        ret sel set sil sir sob sol sos sun tag tik vid vit vir zen zet zvu žid šup lžu měj řež
        pře lze dna
        aids beat bona bond drop fiat game hana iron jura just kuba lego link mail mana míša
        nova rand rank ring shop skin song soul spam spin spot trap trek trip tung yard zora lord
        mela kovu pasu tepu ženu jedu vedu píši svým svou práv moci boje bojí
        web server design blog android gay frank house junior email justice gang penis drink kurt
        cloud police manager avenue science market double bitcoin summit rover holding boom rapid
        boxer boss forbes trans update remix eden lincoln western trust trailer lux satan muslim
        anton marina bowling router rating gin swing exit bon risk zoom upgrade nexus rap graham
        puzzle mustang jang turner restart leader steak hybrid fix zip casting romance fax viking
        babylon desktop porter vous braun buddha doping basket hacker lama var newton balance
        leasing malware rapper covid stud banner label alma remake laguna bourbon jackpot playboy
        crack latina packard hosting ethan these meeting nitro panic sed lori fiesta dealer japan
        joint strip laptop pixel benefit dong devon lucifer pony petit pascal squash driver rest
        rocker detox minor tweet layout taj notes brexit insider sakura axis sitcom flirt draft
        forward muffin watt chips esprit nok pence spoiler grizzly drift popcorn memento ibn
        smoking dol macho bal lazar flip wolfram lupus mim kar bastard broker upload mls lok
        grunt plato dandy cicero bingo varna banking repo demise bypass hoax gospel
        roaming listen lump mem lit xerox trs primus kala amor tara twist ghetto
        blb magor pitomý pitomec buran hlupák mrcha nahý nahá nahé nahota orální prso prsa zadek
        blbý blbnout blbější svině ožrala ožralý chlast zvracet čůrat zadnice péro prsatý
        srab ksicht dement zmetek úchyl štětka feťák opilec opilý podělat kondom erekce libido
        soulož prsní nevěra moč močení močový průjem bobek masakr mučit mučení poprava zabiják
        irena havelka budvar roll černoch rasista kravina sežrat pitva upálení fetiš blití děložní
        stolec děloha chtíč fracek hlen krvavý svlékat týrání zmlátit žvanil osahat
    """.split()),
}

# More words a player would not expect as an answer: contractions without their apostrophe,
# British and archaic words in an American word list, name-like words, crude Czech, Czech
# dictionary entries that read as an inflected form of a commoner word ("řad" of "řada", "volní"
# of "volný"), and the rarer of two Czech spellings, so that a grid never offers both.
NOT_TARGET["en"] |= set("""
    whats cant sim yea nay mum mums gran grans loo loos bloke blokes tonne tonnes whilst pence
    laird lairds glamour thy thine shalt oft unto ere nary yon psi trump trumps trumped nelson
    nelsons carter carters cooper coopers turner turners maria peter peters petered harry sally
    fanny gypsies shag shags willy
    sucked sucker suckers sucking cocked cocking groped groping damning gayer gayest
""".split())
NOT_TARGET["cs"] |= set("""
    vole hovado huba trus píchat žrát čuba běloch židovka zeman forman jarka borka korán ester slávka
    káča blanka janek polanka starka
    řad volní paží hoře vybraní zabrání ničí zmínění unavení zvaní hádek plání pletí výstav skryt
    pochop mazal spodky bol leč vít lán
    archív atelier balkon balon benzin citrón flóra folie folklor glóbus inzulin kupon maratón
    medium milión minus salón sezona sezonní stadión stádium vagon šampión šampón kurs konkurs
    vitamin lahev
""".split())

# Grim subjects (death, killing, weapons, drugs, grave illness) and underwear: valid bonus words,
# never grid answers, in line with the insults and the nudity above.
NOT_TARGET["en"] |= set("""
    dead deadly death deathly deaths die died dies dying coffin coffins funeral funerals grave graves
    tomb tombs kill kills killed killer killers killing killings slay slays slayer slayers slaying
    execute executed lynch massacre kidnap hostage hostages terror terrors terrorist thug thugs
    abuse abused abuser abusers abuses abusing abusive gun guns gunned pistol pistols rifle rifles
    shotgun shotguns grenade grenades bullet bullets weapon weapons bomb bombs bombed bomber bombers
    gunfire gunmen gunner gunners gunning
    bombing nuke nukes nuked arson arsonist drown drowns drowned drowning poison poisons poisoned
    poisonous drug drugs drugged addict addicts addicted addiction addictive ecstasy cancer cancers
    disease diseased diseases plague plagues plagued tumor tumors racism satanic
    bra bras thong thongs virgin virgins screwed dung gore womb fetal
""".split())
NOT_TARGET["cs"] |= set("""
    smrt smrtící mrtvý mrtvice umírat umírání zemřít zemřelý hrob hrobka rakev pohřeb pohřbít
    zabít zabíjet zabití usmrtit umřít úmrtí úmrtní umučení kat únos únosce vydírat teror otrávit
    utopit jed mor cholera tyfus sodoma výstřel
    zbraň pistole puška samopal kulomet kulka granát bomba bombový střela střelba střelný droga drogový
""".split())

# The same subjects where they are less obvious, and the same in both languages: burial, grave
# illness ("disease" and "nemoc" alike), blades and spears, kidnapping, tobacco and spirits (beer
# and wine stay, as everyday food words), and gambling. Arrows ("arrow", "šíp") and an English
# "tank" have everyday senses and stay; a Czech "tank" is only the armoured one.
NOT_TARGET["en"] |= set("""
    bury buried buries burying burial burials coma comas
    sword swords swordsman spear spears speared dagger daggers sabre saber sabers ransom ransoms
    tobacco cigar cigars cigaret vape vapes vaped vaper vapers vaping
    whiskey whiskeys whisky vodka vodkas rum rums gin gins brandy liquor liquors
    casino casinos gamble gambled gambler gamblers gambles gambling
""".split())
NOT_TARGET["cs"] |= set("""
    nemoc nemocný infarkt meč kopí dýka šavle kord tank výkupné
    tabák doutník dýmka fajfka kouřit kouření vodka rum whisky koňak likér
    kasino hazard ruleta
""".split())

# The rest of the subjects above, in both languages, and what a player wouldn't take for a word:
# found by reading every grid word of the lists through. Grim: poisons and explosives, burial and
# illness ("hospice", "chemo", "nádor", "koma"), weapons ("ammo", "arsenal", "dělo", "munice"),
# spirits and smoking ("tequila", "opít"), gambling ("poker", "lottery", "sázka", "loterie").
NOT_TARGET["en"] |= set("""
    ammo ante anthrax arsenal assault autopsy bayonet bookies bourbon cannon cannons carnage
    casket chemo cholera cognac coroner crypt cyanide demise dengue dirk doped doping drunken
    eulogy fatal fatally firearm gallows gestapo handgun hospice inter jackpot leprosy lethal
    lottery lotto lupus malaria martini martyr martyrs missile morgue mourn musket opioid
    opioids perish poker polio scotch sepsis shiv smoker smokers smoking tequila torpedo typhoid
    wager warhead
""".split())
NOT_TARGET["cs"] |= set("""
    arsen arzenál atentát bití choroba chorý cigáro dostřel dušení dynamit dělo džihád ebola
    embolie hlaveň hospic hulit hřbitov jatka kalibr kanón koma kuřák kuše loterie mina muka
    munice muniční márnice napalm nikotin nádor nálož násilný násilí odstřel opium opít otrava
    palba poker rukojmí ráže střílet syfilis sázka tiket torpédo tumor udušení vsadit výzbroj
    zbrojní zesnulý zhoubný zádušní škrcení
""".split())

# Crude, bodily and sexual words, insults and slurs, and in English interjections ("gee", "oops"),
# informal clippings ("doc", "gal"), foreign currencies and words and brands ("jeep").
NOT_TARGET["en"] |= set("""
    arouse bigoted bigotry bosom brothel carnal cervix commie hickey hicks idiocy inbred jackass
    libido mucus sissy urinary whitey
    aha ahem aids alcohol amour anyways arsenic asexual avenge avenged avenger babe babel babes
    baht beck bender berg betting biggie bikini bikinis bingo biopsy bipolar bitcoin blacks blah
    blaster bloods bod booty butch cad captors carcass cartel cartels coco corset creme creole
    cur cystic dame dames dang deviant doc docs doge downer dude dudes embryo embryos fab
    fascism fascist fella fellas fey fink ford foxy gabby gal gals garter gee ghetto goers gosh
    guinea guineas harem haw hobbit hobo hoes holster hookup hustler inquest jag jeep jeez jock
    keto lad lance lira lite loco lube lunacy lux mace machete mafia magnum manure mated max
    measles mecca mega nether obesity obscene oops ouch outed overs paddy pascal payed phew
    potty pow pox prefect probate puberty pusher rabies rah reaper requiem ripper rubles rupee
    rupees sahib salaam savage senna sensual sexes sherry shooter slasher smokey snuff spank
    spanked steroid tam tong tramp tut twitter unborn viva wack whew whoa yikes yuck
""".split())
NOT_TARGET["cs"] |= set("""
    fízl honění hulvát hýždě orgie ožrat pasák páření píchání zadeček
    alkohol arytmie astra babice biopsie bitka bodnutí byte chrást demence deviace drbna dusit
    exekuce exploze extáze facka foyer gender harant herna hidžáb hlavice hnus hnusný honit
    hrdelní hubení indián intimní jidáš jiřina kanonýr katar koks kolika komando krvácet level
    léze lůza mafie mafián malárie milenec milenka mlácení mlátit mužství nemehlo nicka náboj
    nájemný nálet nářez obrna obézní obětní oběť obřízka ortel padlí padlý pager panna panák
    patolog patrona pietní plastik pohlaví polda popelka poprat poprsí potaz potvora početí
    počít požití pražský primer prudit roubík rozkoš rvačka salva seance senilní seč skalp slipy
    spoušť spáchat stolice strie střelec terno trdlo trenky třetice urna vdaná vyhubit výbuch
    výbušný výherní výprask výstřih vřed zbroj zneužít zplodit zrůda záhrobí óčko čáry šaría šat
    šikana šmejd šílenec ženství žrádlo
""".split())

# Names: first names and surnames ("ted", "graham", "jelínek"), places and nationalities ("wales",
# "welsh", "dutch", "rus", "zlínský"), brands; and in English, abbreviations and prefixes ("ids",
# "gen", "anti", "trans") and British or archaic words ("aye", "wee", "nigh", "daft", "shire").
NOT_TARGET["en"] |= set("""
    afghan afghans airbus alp amazon ares bailey balboa baptist basque bates batman billy bobby
    bowman brad bruins colleen corning cutler danish dickens dona dutch freeman french fritz
    graham grimes hamburg hank hanks hays hector hogan japan jenny jimmy john johnny johns josh
    lulu mac macron macs madras mahatma manila marge martin martins masonic medusa mercer mickey
    miller millers morocco newton oxford pacific panama patsy phoebe pollard reeves rick riviera
    roger rogers roman romeo roper savoy sawyer scrooge seine shay sheila smith smiths sonny
    soviet soviets surrey swede swedes tanner ted terry timothy tom toms tucker ulster viking
    vikings wales welsh wright xerox yahoo
    anti biz celeb celebs comp contra ecu exec execs fave fer gen gimme hydro ids infra lat mag
    mags maxi meta micro mid midi mod mods mono mot mun mus nitro pseudo quasi recon sapiens
    sous stat sup supra syn trad trans twas ultra ump vac vert wiz
    anon aye banger batsman batsmen bosh brill bullock carers chap chit collier crisps croft
    daft dale docker dodgy dost dram draper duff earl ell expiry firth footy gent gents giro
    glen grange hackney hap hart heath hove kip lads lass liege lorry mater midland minster morn
    morrow netball nigh nous petrol pong punter quid reeve rubbish saith shire smite sod squire
    swain tat telly thence thrice tun twain vale wee whence whit wicket wickets wight wot yonder
    zed
""".split())
NOT_TARGET["cs"] |= set("""
    amelie aurora chvojka drákula fiala filip fortuna hlinka horák husák iris jelínek kovařík
    ledecký matrix matuška mládek nečas opavský orient pešek plzeň podluží polák porta riviéra
    rosický rus rýnský sazka souček sparťan texaský toufar trabant turek waltz wan zelenka
    zlínský záruba ústecký štýrský žďárský
""".split())

# Czech forms that are not a dictionary's base form, which the flag rules let through: comparatives
# of adjectives and adverbs, both forms ("menší", "líp", "lépe", "víc", "dál"; "výše" stays, as a
# noun), present participles ("ležící"; lexicalised ones such as "vedoucí" stay), feminine,
# neuter and plural forms of pronouns and numerals ("ona", "tato", "dvě", "moje", "vše"),
# archaic and poetic forms ("msta", "luka", "nebesa", "voj", "prvý"), prefixes ("makro", "elektro")
# and fragments ("fata"). Of two forms of one word only the standard one is a grid word ("brzy",
# not "brzo"; "také", not "taky"; "lidé", not "lidi"), so a grid never offers both.
NOT_TARGET["cs"] |= set("""
    beroucí bijící bližší blíž blíže blížící bohatší bránící bydlící běžící chodící chudší
    dceřiná delší dražší držící dvě dál dále déle dělící dětičky dřív dříve elektro fata hezčí
    hlubší hlásící horší hořící hrající hrozící hrubší hustší hůř hůře jdoucí jedoucí jezdící
    kojící končící kotvící kratší lada lehčí lepící lepší letící ležící lidičky luka lépe líp
    magna mající makro maxima menší milejší mladší mluvící moje moto msta myslící méně mířící
    měkčí měnící měřící nebesa nebrat nebrání nedat nesoucí nižší novější níže obě ona patřící
    platící plačící plnící plnější plující pláně prvý píšící raději radši rodící sama sedící
    slabší sladší smějící snazší snažící snáze spící starší stojící sušší svoje svítící sídlící
    sílící tančící tato tekoucí tenčí tišší tlustší tmavší tohle toto toužící trpící tužší tvoje
    tvořící tvrději tvrdší tyto tyčící těžší užší vařící velící visící voj vonící vyšší vážící
    víc více výš větší vše všechno znějící zářící útočící čistící čistší řadící řešící řidší
    řídící širší šířeji šířící žijící živější
    aspoň bank brejle brzo bus bába břímě diskuze dneska horror houška impulz jenom kafe kuchyň
    lidi lítat misie oblíkat odsud okýnko polívka pomoct puding sekyra spíše studně taky transit
    vloni vždycky zem znova zář říci šéfová
""".split())

# Words that came into the grids once the lists above had left room, read through in the
# regenerated packs: a clipping ("legit", "vnitro"), a name ("jean"), an interjection, a crude
# second sense ("hump"), and grim or close to it ("morbid", "trhací" of explosives, "punč" of
# spirits, "prcek" of the blocked "prcat").
NOT_TARGET["en"] |= {"morbid", "legit", "jean", "hump", "whoops"}
NOT_TARGET["cs"] |= {"prcek", "trhací", "vnitro", "punč"}

# A second reading of the grid words (November 2026), by the same rules. English: interjections
# ("hey", "bye", "amen"), British and archaic words ("advert", "veg", "sire", "lieu"), prefixes and
# clippings ("semi", "sub", "info", "promo"), foreign currencies ("yen", "peso"), names ("august",
# "sabbath"), betting, illness and harm ("bet", "palsy", "choke", "urn"), insults ("swine",
# "liar") and underwear ("boxers"); clippings that are everyday American words ("photo", "gym",
# "condo") stay. Czech: place and nationality adjectives and language names ("český",
# "ruština"), interjections ("pardon", "vida"), the rarer or inflected one of two forms ("veliký"
# of "velký", "díky" of "dík", "akta" of "akt"), predicative colour forms ("bílo"), clippings
# ("matika", "áčko"), a participle ("vroucí"), revenge, kidnapping and spears ("pomsta",
# "unést", "oštěp", as "avenge", "kidnap" and "spear"), and the bodily words English leaves out
# ("puberta", "střevo"). The last line of each came into the grids in their place.
NOT_TARGET["en"] |= set("""
    hey wow alas bye goodbye heck meow amen boo darn moo hello howdy aloha bravo hurrah hooray
    advert adverts veg fro lieu sire stead rue woe hale privy posh mains tram
    semi sub bio mini macro info prep intro expo promo admin grad gator spec sync synth
    franc peso yen euro
    martian padre sabbath august bible
    bet palsy urn bleed bleeds bled bleeding choke chokes choked choking
    swine hoe nerd fool liar brat shorty boxers
    alright behold bladder freak freaks glam messiah multi stalker theta toxic warship
    carbs violent violence violently amino hyper nerdy pelvic armory famine lesion lesions sax pelvis
    craven demonic hydra
""".split())
NOT_TARGET["cs"] |= set("""
    africký arabský asijský britský dánský finský indický irský irácký italský keltský mexický
    norský německý perský polský ruský skotský srbský syrský thajský trojský turecký uherský
    vlašský íránský český čínský řecký římský švédský němčina ruština čeština
    pardon vida ahoj hurá veliký díky akta bílo černo červeno žluto zeleno krásno veselo matika áčko béčko
    vroucí živoucí pomsta pomstít odplata unést oštěp puberta střevo střevní
    chromý chán gauner mamka mamina plodit
""".split())

# Dictionary entries that are not words at all: abbreviations and symbols the Czech Hunspell
# dictionary lists so that a spell check accepts "cca", "dkg" or "zool." in running text, and an
# archaic form ("mst", of "msta"). They are accepted nowhere, not even as bonus words.
NOT_WORDS = {
    "en": set(),
    "cs": set("""
        adj afr atm bto cca ccm dkg dpi dto fff mst plm ppm ppp rbl tbc vvn www
        anat biol celk cotg dtto ekol ekon geol geom hanl hist hosp http kcal mbar mmol podm přír
        quot skup zast zool filoz podst elektr
    """.split()),
}

# A third reading of the grid words (November 2026). English: insults ("fat", "ugly"); plurals whose
# frequency comes from a name while the word itself is rare ("cairns", "sears", "parsons", "pacers",
# "stokes"), and words that are mostly names ("stein", "serge"); grim words that match what is
# kept out already (war and wounds, "rehab" as "addict", explosives and poisons, "skull" as
# "coffin", "zombie", "hijack" as "kidnap", "ambush" as "assault", "illness" as "disease",
# "injured" as "wounded", "wartime" as "warfare", "revenge" as "avenge"); slang ("swag", "boomers",
# "freaky", "freaked", "buster"), insults ("geek" as "nerd", "jerk"), horror ("vampire" and "demon", as "zombie"
# and "demonic"; ghosts, witches and monsters of fairy tales stay); plurals that read as sports teams
# ("braves", "dodgers", "packers", "raiders", "broncos", "marlins", "orioles"), a plural that reads as a
# name ("stiles"), a clipping ("psych", as "psycho"), names and
# titles ("jasper", "barker", "kaiser", "ottoman"), underwear ("briefs", as "boxers"); the bonus-only
# words unblocked above. Czech: words whose
# frequency comes from surnames ("pařízek", "homolka", "sládek", "kolář", "valášek", as "mládek" and
# "pešek"), a mixed drink ("koktejl", as "punč"), a blind man ("slepec", as "chromý"), the
# skull and explosives and wounds as in English, foreign currencies (as "euro", "yen" and "peso"
# in English), colloquial words ("kecat", "makat", "pařit", "honička", "brácha"), insults ("naivka", "šprt",
# "darebák", "hloupý"; "tlustý" and "ošklivý" as "fat" and "ugly"), the occult and horror (as "satanic", "demon" and "vampire") and "lesb-" (as "lesbian").
# Kitchen knives ("knife", "nůž", "čepel"), tools ("hatchet", "sekera"), "bít" (a heart beats, a
# clock strikes), prisons, thieves and widows stay: everyday words the subjects above don't take in.
NOT_TARGET["en"] |= set("""
    fat ugly cairns sears parsons pacers stokes stein serge
    warfare rampage wounds wounded militia fallout explode toxin skull zombie hijack rehab
    gay suck escort snatch nipple
    ambush swag braves dodgers packers boomers freaky illness injured jasper briefs
    barker buster kaiser revenge wartime
    geek jerk demon vampire raiders broncos marlins orioles stiles ottoman psych freaked
""".split())
NOT_TARGET["cs"] |= set("""
    pařízek homolka sládek strnad kalous kudrna tesařík paleček
    lebka odpálit zranit zranění rubl dolar euro kecat pokecat makat pařit honička
    lesba lesbička lesbický naivka okultní
    démon upír šprt darebák koktejl kolář valášek slepec brácha tlustý ošklivý hloupý
""".split())

# A content audit of the packs (November 2026), by the same rules. English: words whose frequency
# comes from a name, a place or a team ("frank", "don", "nick", "homer", "china", "leafs", "browns",
# "ravens", as "ted", "smith" and "braves"), occupational surnames ("potter", "mason", "dyer", as
# "cooper" and "turner"), titles ("shah", "sultan", as "khan"), Greek letters ("sigma", as "theta"),
# "whites" (as "whitey" and "blacks"), "boomer" (as "boomers"), the British "-wards" ("upwards",
# beside "upward"), "isle" and "jumper", interjections ("yes", as "hello"), clippings ("cam",
# "alum", "rad"), brands and places ("mart", "fiat", "canton", "capitol", "sierra"), "lame" (as
# "chromý"), "devil" (as "demon") and "creepy" (as "freaky"), and the forms of the insults and
# wounds above that are words of their own ("fatter", "ugliest", "geeky", "foolish", "injury" as
# "injured"; the verbs "fooled" and "jerked" stay). Czech: past tenses read before their
# nouns ("vál", "bál", as "mazal"), an imperative ("volej"), a colloquial form ("dolejší" of
# "dolní"), colloquial words ("ukecat", "sranda", "barák", "plac", as "kecat"), war and fallout
# ("válčení", "spad", "zajetí", as "warfare", "fallout" and "hostage"), a word only of set phrases
# ("odiv", as "potaz"), names and places ("vlček", "otava", as "mládek"), insults ("lotr",
# "podivín", "smolař", "odporný", as "darebák", "weirdo", "loser" and "hnusný"), "skelet" (as
# "lebka"), "kartel" (as "cartel"), "slepota" (as "slepec"), and predicative colours ("modro", as
# "bílo"). The last lines of each came into the grids in their place, read through as the packs were
# regenerated: names, places, a newspaper and brands ("hamlet", "bologna", "tribune", "mustang",
# "corona", "cologne", "indies"), a team ("rangers"), archaic words ("thereof", "herein", as
# "thence"), foreign words ("chateau", "fiesta", as the Czech "fiesta"), a title ("imam", as
# "sahib"), "septic" (as "sepsis"), "racial" (as "racism"), "raffle" (as "lottery"), "postwar" (as
# "wartime") and "drinker" (as "drunk"); in Czech an archaic measure ("korec"), colloquial words
# ("klídek", "basa", "šikulka", "špitál", "šuplík", "ženuška", "fabrika", as "sranda"), names
# ("mníšek", "orlice", "zelinka", as "otava" and "zelenka"), a poetic word ("jitro", as "msta"), a
# word of a set phrase ("područí", as "odiv"), a verb form ("sklání"), "embryo", "odpal", "válečný"
# and "mesiáš" (as the English "embryo", "odpálit", "wartime" and "messiah"), and "půle", "fousek",
# "ceněný" and "jelení", which grids had beside "půl", "fous", "oceněný" and "jelen".
NOT_TARGET["en"] |= set("""
    frank don nick victor warren homer china leafs browns colts titans reds royals ravens
    potter mason dyer shah sultan sigma zeta iota kappa lambda whites boomer
    upwards towards backwards forwards afterwards downwards onwards inwards outwards homewards
    isle jumper yes cam alum rad mart fiat canton capitol sierra drake madden rowan
    lame devil creepy
    fatter fattest uglier ugliest geeky foolish psyched injure injures injury
    bologna hamlet kelvin jay tribune mustang rangers thereof septic
    corona cologne indies chateau fiesta imam racial herein therein raffle postwar drinker
""".split())
NOT_TARGET["cs"] |= set("""
    vál bál volej dolejší ukecat sranda bráška barák plac machr parťák šik úlet klasa rýna kotrba
    válčení spad zajetí odiv
    vlček komárek hrádek kupka krupka vodička podlesí otava
    kalina kroupa skalice slatina orlík lipka loučka
    lotr podivín smolař odporný skelet kartel slepota
    modro šedo hnědo růžovo fialovo oranžovo
    korec klídek basa embryo odpal válečný šikulka půle špitál mníšek orlice fousek mesiáš jitro ceněný
    šuplík ženuška fabrika zelinka područí sklání jelení
""".split())
