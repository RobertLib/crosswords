#!/bin/bash
#
# media.sh — regenerates every App Store screenshot and App Preview in AppStore/.
#
#     Tools/AppStoreMedia/media.sh                    # screenshots + preview, every device
#     Tools/AppStoreMedia/media.sh screenshots        # screenshots only
#     Tools/AppStoreMedia/media.sh video              # App Preview only
#     Tools/AppStoreMedia/media.sh screenshots duo    # one device only: iphone, ipad or duo
#
# Needs Xcode, the simulators named below and ImageMagick (`brew install
# imagemagick`). Every pose is driven by the `#if DEBUG` launch arguments read in
# crosswords/App/DebugLaunch.swift and GameController.applyDebugArguments (plus
# small hooks in HomeView, GameView, DailyView, TrophiesView and the wheel's demo
# finger), so this builds Debug, and none of it exists in the build that goes to
# the App Store.
#
# This is the Sudoku project's appstore_media.sh (github.com/RobertLib/sudoku),
# with this game's poses, demo and names. The parts that look after the
# simulators — putting back their languages and an installed copy of the app —
# are unchanged, so a fix there belongs in both.
#
# The iPhone Duo needs a hand: nothing on the command line unfolds it, so the
# screenshots start with it, and the run waits until you unfold it in DeviceHub
# (see wait_unfolded). Everything after that runs on its own, and a run for the
# iPhone or the iPad alone needs nobody.
#
# Output goes to AppStore/screenshots/<locale>/<device>/ and
# AppStore/preview/<locale>/<device>.mp4, where <device> is iphone-6.3,
# iphone-6.9, iphone-duo or ipad-13 — one folder and one file per slot in App
# Store Connect. `iphone` shoots both iPhone sizes.
# Override the root with OUT_ROOT=… to try things out without touching the set
# you are about to upload. Tools/AppStoreMedia/compose.sh then turns these plain
# shots into the captioned ones that are uploaded.
#
set -euo pipefail
# Decimals with a point whatever the Terminal's language: awk prints and reads numbers in the
# locale's format, and under a Czech one it writes "0,33" and reads "20.5" as 20, which the Swift
# helpers (gaps.swift, video.swift) then refuse.
export LC_ALL=C.UTF-8

MODE="${1:-all}"
ONLY="${2:-}"
# A typo would otherwise build, shoot nothing and still reset the simulators.
usage() { echo "usage: $0 [all|screenshots|video] [iphone|ipad|duo]" >&2; exit 2; }
case "$MODE" in all | screenshots | video) ;; *) usage ;; esac
case "$ONLY" in "" | iphone | ipad | duo) ;; *) usage ;; esac
if [ "$MODE" = video ] && [ "$ONLY" = duo ]; then
    echo "the iPhone Duo has no take of its own: its preview is the iPhone's (see IPHONE_VIDEO_SIZE)" >&2
    exit 2
fi
wants() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; } # wants <iphone|ipad|duo>: does this run shoot it?
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_ROOT="${OUT_ROOT:-$ROOT/AppStore}"
# The build, the takes and the media on their way. A new folder in $TMPDIR on
# every run, which a run that succeeds deletes again (see on_exit); WORK=… names
# one of your own instead, and that one is never deleted as a whole. The run
# does clear folders of its own inside it, though — preview/ among them — and
# OUT_ROOT has a preview/ too, the last good set. So a WORK at or inside
# OUT_ROOT is refused rather than left to delete it.
if [ -n "${WORK:-}" ]; then
    OWN_WORK=no
    # Compared as real paths, so neither a relative WORK nor a symlink slips past.
    work_existed=no
    if [ -d "$WORK" ]; then work_existed=yes; fi
    mkdir -p "$WORK" "$OUT_ROOT"
    WORK="$(cd "$WORK" && pwd -P)"
    OUT_REAL="$(cd "$OUT_ROOT" && pwd -P)"
    case "$WORK/" in
        "$OUT_REAL"/*)
            echo "WORK=$WORK is inside OUT_ROOT ($OUT_REAL); give it a folder of its own" >&2
            if [ "$work_existed" = no ]; then rmdir "$WORK" 2>/dev/null || true; fi
            exit 2 ;;
    esac
else
    WORK="$(mktemp -d -t wordwander-appstore)"
    OWN_WORK=yes
fi
FINISHED=no
# Until the devices are recorded and on_exit takes over (below), a run that stops
# — a failed build, a missing simulator — still says where its files are, rather
# than leaving a folder holding a whole DerivedData in $TMPDIR without a word.
early_exit() {
    if [ "$FINISHED" != yes ] && [ -d "$WORK" ]; then
        echo "  the run's working files, the build log among them, are in $WORK" >&2
    fi
}
trap early_exit EXIT
BID=cz.rob.crosswords

# Every device shoots its App Store slot size natively, so nothing is scaled
# or cropped:
#   iPhone 18 Pro     → 1206 × 2622, one of the two sizes Connect takes for 6.3"
#   iPhone 18 Pro Max → 1320 × 2868, one of the two it takes for 6.9"
#   iPad Pro 13" (M5) → 2064 × 2752, one of the two it takes for iPad 13"
#   iPhone Duo        → 2007 × 2853, one of the four it takes for iPhone Duo
#
# 6.3" is "iPhone with Dynamic Island (medium display)", for 6.1" and 6.3"
# displays, which Connect requires. Its rules also call for the large display
# (6.9") when the app runs on iPhone and that slot is empty, and the two readings
# of them disagree (see AppStore/README.md) — so both are shot, and neither can
# be the one missing at submission.
IPHONE_NAME="iPhone 18 Pro"
IPHONE_LARGE_NAME="iPhone 18 Pro Max"
IPAD_NAME="iPad Pro 13-inch (M5)"
IPHONE_SHOT_SIZE=(1206 2622)
IPHONE_LARGE_SHOT_SIZE=(1320 2868)
IPAD_SHOT_SIZE=(2064 2752)

# The iPhone Duo slot takes either display, either way round: the outer one at
# 1398 × 2034, the inner one at 2007 × 2853. This shoots the inner one upright.
# It is the display the device is bought for, and the one the Sudoku project
# found fits its poses whole, as this game's do (see AppStore/screenshots.md).
# simctl calls the outer display `primary` and the inner one `primary-1`.
DUO_NAME="iPhone Duo"
DUO_SHOT_SIZE=(2007 2853)
DUO_DISPLAY=primary-1

# Xcode makes these simulators of its own; a Mac where one was deleted gets it
# back on demand. The iPad is the 13-inch iPad Pro with the memory Xcode's own
# has (the name says nothing of it).
IPHONE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro
IPHONE_LARGE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max
IPAD_TYPE=com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB
DUO_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-Duo

# App Preview render sizes — the only two App Store Connect takes for these
# devices, and *not* the devices' own resolutions. The iPhone one is also the
# only size it takes for the 6.9" iPhone and the iPhone Duo, so neither has a
# take of its own: their previews are the 6.3" iPhone's, under their own names.
# Checked against Apple's App preview specifications (developer.apple.com/help/
# app-store-connect/reference/app-preview-specifications, November 2026): the
# iPhone Duo, like every iPhone with Face ID or Dynamic Island, accepts 886 × 1920
# upright and 1920 × 886 on its side; the 13" iPad 1200 × 1600 and 1600 × 1200.
# See AppStore/screenshots.md.
IPHONE_VIDEO_SIZE=(886 1920)
IPAD_VIDEO_SIZE=(1200 1600)

# Previews must carry stereo AAC at 256 kbps and silence does not satisfy the
# check, so a bed is synthesised — the app itself ships no audio files.
DEFAULT_MUSIC="$WORK/bed.wav"
# An empty PREVIEW_MUSIC= means the default too: a preview without music is
# refused by Connect, and conform.swift stops on one.
PREVIEW_MUSIC="${PREVIEW_MUSIC:-$DEFAULT_MUSIC}"
PREVIEW_GAIN="${PREVIEW_GAIN:-0.5}"
# Only the default bed is synthesised when it is missing. A PREVIEW_MUSIC that
# names a file that isn't there is a typo, and would otherwise be quietly
# replaced by the default music under that name — so it stops the run before
# anything is built or shot.
if { [ "$MODE" = all ] || [ "$MODE" = video ]; } && [ -n "$PREVIEW_MUSIC" ] \
    && [ "$PREVIEW_MUSIC" != "$DEFAULT_MUSIC" ] && [ ! -f "$PREVIEW_MUSIC" ]; then
    echo "PREVIEW_MUSIC=$PREVIEW_MUSIC does not exist" >&2
    if [ "$OWN_WORK" = yes ]; then rm -rf "$WORK"; fi
    exit 1
fi

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

udid_for() {
    # Device lines are indented four spaces and read "<name> (<udid>) (<state>)".
    # The name is everything before the UDID and compared whole, because names carry
    # brackets of their own: a prefix match would take "iPad Pro 13-inch (M5) (16GB)"
    # for "iPad Pro 13-inch (M5)", and "iPhone 18 Pro Max" for "iPhone 18 Pro".
    # The list goes from the oldest runtime to the newest, and the last match is taken: a
    # same-named simulator left on an older runtime may be too old for the app. Which one
    # that is goes to stderr when there are several, as a step done by hand (unfolding the
    # iPhone Duo) has to be done on that one.
    xcrun simctl list devices available \
        | sed -nE 's/^    (.*) \(([0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12})\) \([A-Za-z ]+\) *$/\1|\2/p' \
        | awk -F'|' -v name="$1" '$1 == name { udid = $2; n++ }
              END {
                  if (n > 1) printf "  %d simulators are called \"%s\"; using %s\n", n, name, udid > "/dev/stderr"
                  if (udid != "") print udid
              }' || true
}

ensure_device() { # ensure_device <name> <device-type-id> -> udid on stdout
    local udid; udid="$(udid_for "$1")"
    if [ -z "$udid" ]; then
        # Messages go to stderr, because the caller reads this function's stdout.
        # No runtime is named: simctl then takes the newest one that runs the
        # device type, and says which on stderr. Picking one here went wrong for
        # the iPhone Duo, which runs only on a runtime of its own
        # (`iOS-27-2-iPhone19-4`) that runs no other iPhone.
        echo "  creating simulator '$1'" >&2
        xcrun simctl create "$1" "$2" >/dev/null || return 1
        udid="$(udid_for "$1")"
    fi
    printf '%s' "$udid"
}

prefs_for() {
    printf '%s' "$HOME/Library/Developer/CoreSimulator/Devices/$1/data/Library/Preferences/.GlobalPreferences.plist"
}

# The status bar is the system's, not the app's, so `-AppleLanguages` never
# reaches it — and on the iPad it carries the date, which a Czech simulator
# prints in Czech over the English set. So the device itself is switched to the
# language being shot. That only takes after a reboot, so a device whose
# language changes is shut down here and boot_and_install brings it back up.
device_languages() { # device_languages <udid> -> the preferred languages, space-separated
    local prefs i=0 lang list=""; prefs="$(prefs_for "$1")"
    while lang="$(plutil -extract "AppleLanguages.$i" raw "$prefs" 2>/dev/null)"; do
        list="${list:+$list }$lang"
        i=$((i + 1))
    done
    printf '%s' "$list"
}

# The whole list, not just its first entry: a simulator set to Czech with
# English after it has to come back with both. Each key on its own: an empty
# region or no languages at all delete that key instead of writing it, which is
# how restore_devices puts back a device that never had it — writing the run's
# en_US there would leave it set for good.
set_device_language() { # set_device_language <udid> <region|""> [<language>...]
    local udid="$1" region="$2"; shift 2
    local prefs; prefs="$(prefs_for "$udid")"
    if [ "$(device_languages "$udid")" = "$*" ] \
        && [ "$(plutil -extract AppleLocale raw "$prefs" 2>/dev/null)" = "$region" ]; then
        return 0
    fi
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
    if [ "$#" -gt 0 ]; then
        xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array "$@"
    else
        xcrun simctl spawn "$udid" defaults delete -g AppleLanguages >/dev/null 2>&1 || true
    fi
    if [ -n "$region" ]; then
        xcrun simctl spawn "$udid" defaults write -g AppleLocale -string "$region"
    else
        xcrun simctl spawn "$udid" defaults delete -g AppleLocale >/dev/null 2>&1 || true
    fi
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
}

device_language() { # device_language <udid> <locale>
    case "$2" in
        cs)    set_device_language "$1" cs_CZ cs-CZ ;;
        en-US) set_device_language "$1" en_US en-US ;;
    esac
}

# A Wordwander already installed on these simulators — the developer's own, with its
# games and settings — would be lost to the clean installs below, so it is copied
# aside before the first of them and put back by restore_devices. A new folder on
# every run (SAVED, made next to the trap below): a copy from an earlier run is
# older than what is installed now, and must not be what gets put back. Nor is
# any copy ever deleted by the script: if a run died before putting the app back,
# its copy is the only one left.
#
# A copy counts only once it is whole. `complete` is written after both the app
# and its data are across, `none` when no Wordwander is installed, and
# restore_devices touches a device's app only after one of the two. A copy that
# failed or was cut short has neither: the run stops before the clean install, so
# the app on the device is still the one that was there, and it is left alone —
# rather than uninstalled, with its games, on the strength of half a copy.
# Every Debug build the run installs gets this file in its data container
# (boot_and_install), which no Wordwander of anyone's own has. A run that is
# killed outright (SIGKILL, a crash, a power cut) never gets to on_exit, and leaves
# that build on the device; the next run can then tell it from the player's own.
POSE_MARK="Library/wordwander-media-pose"

save_install() { # save_install <udid> — on a booted device, once per run
    local dir="$SAVED/$1" apps app data
    if [ -e "$dir/complete" ] || [ -e "$dir/none" ]; then return 0; fi
    rm -rf "$dir"
    # "Not installed" has to be proven, never read off a lookup that failed:
    # `none` is leave for the clean install to delete whatever Wordwander is on the
    # device, games and all. `get_app_container` fails the same way for an app
    # that is missing and for a device that is still booting or a CoreSimulator
    # hiccup, so the answer comes from the list of installed apps instead — and
    # only from a list that is evidently whole, which on any iOS simulator that
    # is up includes Settings (com.apple.Preferences). Bundle ids are the list's
    # keys, quoted (`    "cz.rob.crosswords" =     {`); the closing quote keeps
    # `cz.rob.crosswordsTests` apart. A device that is shut down cannot list its apps
    # at all, so that stops the run too.
    if ! apps="$(xcrun simctl listapps "$1" 2>/dev/null)"; then
        echo "  !! could not list the apps on $1; stopping, as a clean install could delete a Wordwander that is there" >&2
        return 1
    fi
    case "$apps" in
        *'"com.apple.Preferences" ='*) ;;
        *) echo "  !! the app list from $1 looks incomplete; stopping, as a clean install could delete a Wordwander that is there" >&2
           return 1 ;;
    esac
    case "$apps" in
        *"\"$BID\" ="*) ;;
        *) mkdir -p "$dir" && : > "$dir/none" || return 1
           return 0 ;;
    esac
    # A listed app can be a ghost: an uninstall just before a shutdown (the one
    # at the end of every run) leaves it in the list with neither its bundle nor
    # its data on disk, and there is nothing of it to lose. Anything that is left
    # on disk is still copied, or the run stops.
    app="$(xcrun simctl get_app_container "$1" "$BID" app 2>/dev/null)" || app=""
    data="$(xcrun simctl get_app_container "$1" "$BID" data 2>/dev/null)" || data=""
    # A pose build an interrupted run left behind, with its made-up history, is not
    # what this run should keep and put back. What was installed before it is the
    # copy that run kept aside — the newest copy of this device in SAVED_ROOT, whole
    # (`complete`) or proving there was none (`none`) — so this run takes that over.
    if [ -n "$data" ] && [ -e "$data/$POSE_MARK" ]; then
        local previous source
        previous="$(ls -t "$SAVED_ROOT"/installed.*/"$1"/complete "$SAVED_ROOT"/installed.*/"$1"/none 2>/dev/null \
            | grep -vF "$SAVED/" | head -n 1 || true)"
        rm -rf "$dir"
        mkdir -p "$dir" || return 1
        if [ -z "$previous" ] || [ "$(basename "$previous")" = none ]; then
            echo "  the Wordwander on $1 is a pose build an interrupted run left, and there was none before it"
            : > "$dir/none" || return 1
            return 0
        fi
        source="$(dirname "$previous")"
        # The marker last, as below: a copy cut short is not taken for a whole one.
        cp -R "$source"/*.app "$dir/" \
            && rsync -a "$source/data/" "$dir/data/" \
            && : > "$dir/complete" \
            || { echo "  !! could not take over the copy in $source; stopping before a clean install loses it" >&2
                 return 1; }
        echo "  the Wordwander on $1 is a pose build an interrupted run left; the app installed before it, kept in $source, is the one put back"
        return 0
    fi
    if [ -n "$app" ] && [ ! -e "$app" ] && { [ -z "$data" ] || [ ! -e "$data" ]; }; then
        echo "  the Wordwander listed on $1 has nothing left on disk; treated as not installed"
        mkdir -p "$dir" && : > "$dir/none" || return 1
        return 0
    fi
    mkdir -p "$dir" \
        && [ -n "$app" ] && [ -n "$data" ] \
        && cp -R "$app" "$dir/" \
        && rsync -a "$data/" "$dir/data/" \
        && : > "$dir/complete" \
        || { echo "  !! could not copy the installed Wordwander aside; stopping before a clean install loses it" >&2
             return 1; }
    echo "  kept the installed app and its data aside in $dir"
}

restore_install() { # restore_install <udid> — on a booted device; leaves it shut down
    local dir="$SAVED/$1" app data
    [ -e "$dir/complete" ] || return 0
    app="$(find "$dir" -maxdepth 1 -name '*.app' 2>/dev/null | head -n 1)"
    [ -n "$app" ] || return 0
    xcrun simctl install "$1" "$app" || return 1
    data="$(xcrun simctl get_app_container "$1" "$BID" data)" || return 1
    # Shut down first, so no running process holds the app's preferences in memory.
    xcrun simctl shutdown "$1" >/dev/null 2>&1
    # The container's own metadata belongs to the new install.
    rsync -a --delete --exclude .com.apple.mobile_container_manager.metadata.plist "$dir/data/" "$data/"
}

boot_and_install() { # boot_and_install <udid> <locale>
    local udid="$1"
    device_language "$udid" "$2"
    # `boot` fails on a device that is already up, which is fine; `bootstatus`
    # waits until the device has finished booting, and if it never does, nothing
    # after it can be trusted — save_install least of all.
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 \
        || { echo "  !! $udid did not finish booting" >&2; exit 1; }
    save_install "$udid" || exit 1
    # Each locale starts from a clean install: nothing the last run left behind
    # may leak into the next set. The poses themselves don't need it —
    # `-debugProgress` replaces the player's data on every launch.
    xcrun simctl uninstall "$udid" "$BID" >/dev/null 2>&1 || true
    xcrun simctl install "$udid" "$APP"
    # So that a later run knows this build for the run's own (see POSE_MARK). Not
    # fatal: without it, only a run killed outright would go wrong, as before.
    local pose_data
    if pose_data="$(xcrun simctl get_app_container "$udid" "$BID" data 2>/dev/null)" && [ -n "$pose_data" ]; then
        mkdir -p "$pose_data/Library" && : > "$pose_data/$POSE_MARK" \
            || echo "  !! could not mark the Debug build's data on $udid" >&2
    else
        echo "  !! could not mark the Debug build's data on $udid" >&2
    fi
    # 9:41 is the time Apple puts on its own. The battery is `discharging` at
    # 100 %, not `charged`: charged is the plugged-in glyph with a bolt through it,
    # which reads as a phone on charge rather than as a phone.
    if ! xcrun simctl status_bar "$udid" override --time "9:41" \
        --batteryState discharging --batteryLevel 100 \
        --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 >/dev/null 2>&1; then
        # Not fatal, but the shots will carry the real time and battery.
        echo "  !! the status bar could not be set to 9:41; check the shots' status bars" >&2
    fi
    # The first launch after a boot and an install is the slow one; take that
    # cost before anything is shot.
    launch "$udid" "$2" -debugProgress 1
    sleep 6
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
}

# Shuts a device down once its part of the run is done. Left up, every simulator
# the run has used would still be running through the preview takes, which are
# the part that is sensitive to a busy Mac (see record). The next part that needs
# the device boots it again, which a change of language does anyway, and
# restore_devices leaves each one running or shut down as it found it.
shut_down() { # shut_down <udid>
    xcrun simctl terminate "$1" "$BID" >/dev/null 2>&1 || true
    xcrun simctl shutdown "$1" >/dev/null 2>&1 || true
}

locale_args() {
    case "$1" in
        cs)    printf '%s\0%s\0%s\0%s\0' -AppleLanguages "(cs)" -AppleLocale cs_CZ ;;
        en-US) printf '%s\0%s\0%s\0%s\0' -AppleLanguages "(en-US)" -AppleLocale en_US ;;
    esac
}

# Arguments every pose gets. Sounds are off so a run doesn't play every letter
# of every word through the Mac's speakers. Each pose adds `-debugProgress`,
# which replaces the player's data with the history DebugLaunch.seed writes for
# that many levels: the words found, six weeks of daily puzzles ending in a
# 12-day streak, and the achievements they earned — the same on every launch.
COMMON_ARGS=(-debugMute 1)

# A launch soon after a boot can fail outright — "Application launch … did not
# return a process handle nor launch error. No such process" — though `bootstatus`
# has said the device is up: it once stopped a run on the iPhone Duo, rebooted
# for its second language with DeviceHub showing it, and did not happen again on
# the same steps. So a failed launch is tried again, a few seconds apart, and
# only the last failure stops the run.
launch() { # launch <udid> <locale> <args...>
    local udid="$1" loc="$2"; shift 2
    local largs=() attempt err=""
    while IFS= read -r -d '' a; do largs+=("$a"); done < <(locale_args "$loc")
    for attempt in 1 2 3 4; do
        xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
        clear_ready "$udid" || exit 1
        if err="$(xcrun simctl launch "$udid" "$BID" "${largs[@]}" "${COMMON_ARGS[@]}" "$@" 2>&1 >/dev/null)"; then
            return 0
        fi
        [ "$attempt" -lt 4 ] || break
        echo "  … the launch failed, trying again in 5 s: ${err%%$'\n'*}" >&2
        sleep 5
    done
    echo "  !! the app could not be launched on $udid:" >&2
    echo "$err" >&2
    exit 1
}

# Every pose drops a marker when it is set up (DebugLaunch.markReady): a menu
# once its screen has appeared and its push has finished, a game once its board
# is set up — the puzzle pack
# has to be decoded first, which is slower in a Debug build and slower still on
# a slower Mac. Waiting for the file rather than for a number keeps the fast
# poses fast and the slow ones correct.
#
# The marker sits in the app's data container. A lookup that fails stops here,
# naming the device: an empty path would point at /Documents/shot-ready instead,
# and the wait would sit out its whole timeout for a file that cannot appear.
ready_marker() { # ready_marker <udid> -> the marker's path on stdout
    local data
    data="$(xcrun simctl get_app_container "$1" "$BID" data)" && [ -n "$data" ] \
        || { echo "  !! no data container for $BID on $1" >&2; return 1; }
    printf '%s' "$data/Documents/shot-ready"
}

clear_ready() { # clear_ready <udid>
    local marker; marker="$(ready_marker "$1")" || return 1
    rm -f "$marker"
}

wait_ready() { # wait_ready <udid> <timeout-seconds> -> seconds waited on stdout
    local marker; marker="$(ready_marker "$1")" || return 1
    local ticks=0 limit=$(( $2 * 5 ))
    while [ ! -f "$marker" ] && [ "$ticks" -lt "$limit" ]; do
        sleep 0.2
        ticks=$((ticks + 1))
    done
    # stderr, because the caller reads this function's stdout.
    [ -f "$marker" ] || { echo "  !! the pose never became ready (${2}s)" >&2; return 1; }
    # A pose names words from today's packs; one the puzzle does not have is
    # written into the marker rather than quietly left out of the shot.
    [ -s "$marker" ] && { echo "  !! the pose could not be set up: $(cat "$marker")" >&2; return 1; }
    printf '%s' "$(( ticks / 5 ))"
}

# The iPhone Duo boots folded, on its outer display, and nothing on the command
# line unfolds it: simctl has no hinge, and toggling its displays' power only
# blanks them (and once took SpringBoard down with it). DeviceHub does it with a
# click, so the run asks for that and watches the inner display until it is lit
# and upright. Folded, that display is pure black; on its side, it comes out
# 2853 × 2007. A language switch is a reboot and folds it again, which is why
# the Duo is shot before anything else, in both languages.
wait_unfolded() { # wait_unfolded <udid>
    local probe="$WORK/unfolded.png" want="${DUO_SHOT_SIZE[0]}x${DUO_SHOT_SIZE[1]}"
    # Ten minutes by the clock, so a run nobody is watching ends instead of waiting
    # for ever. (A count of rounds would overrun it: each takes a screenshot and a
    # probe on top of its sleep.)
    local lit size asked=no deadline=$((SECONDS + 600))
    while :; do
        lit=0 size=""
        if xcrun simctl io "$1" screenshot --display="$DUO_DISPLAY" "$probe" >/dev/null 2>&1; then
            read -r lit size < <(magick "$probe" -alpha off \
                -format '%[fx:maxima > 0.1] %wx%h\n' info: 2>/dev/null) || true
        fi
        if [ "$lit" = 1 ] && [ "$size" = "$want" ]; then
            break
        fi
        if [ "$asked" = no ]; then
            # The UDID, because there may be more than one simulator of the name
            # (see udid_for), and unfolding another one would go unnoticed.
            printf '\a  → Unfold the iPhone Duo %s in DeviceHub and turn it upright; the run then goes on by itself.\n' "$1"
            asked=yes
        fi
        [ "$SECONDS" -lt "$deadline" ] \
            || { echo "  !! the iPhone Duo $1 was not unfolded upright within 10 minutes" >&2; exit 1; }
        sleep 2
    done
    # Unfolding resizes whatever is on screen; give it a moment to settle.
    if [ "$asked" = yes ]; then sleep 3; fi
}

# ---------------------------------------------------------------- build

say "Building Debug, optimised, for the simulator"
# Into a log, because a build says a great deal — and when it fails, its errors
# and the end of the log come out here, rather than the run just stopping.
#
# Debug, because the poses are `#if DEBUG` code; optimised as a release build is,
# because an unoptimised one is not the game people get. It drew the
# level-complete card on the 13" iPad so slowly that a take stood still for a
# second as the last word went in — caught by the gap check, and nothing a player
# ever sees. The optimisation level is a setting of its own, apart from the DEBUG
# condition, so the poses stay in.
BUILD_LOG="$WORK/build.log"
if ! xcodebuild -project "$ROOT/crosswords.xcodeproj" -scheme crosswords \
    -configuration Debug -sdk iphonesimulator \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$WORK/dd" SWIFT_OPTIMIZATION_LEVEL=-O build >"$BUILD_LOG" 2>&1; then
    echo "  !! the build failed. Its errors:" >&2
    grep -E '(^|: )(fatal )?error: ' "$BUILD_LOG" | awk '!seen[$0]++' | head -n 20 >&2 || true
    echo "  and the end of $BUILD_LOG:" >&2
    tail -n 25 "$BUILD_LOG" >&2
    exit 1
fi
APP="$WORK/dd/Build/Products/Debug-iphonesimulator/crosswords.app"

# Only the devices this run shoots, so a run for one device leaves the others
# alone and a `video` run does not need a Duo.
IPHONE_UDID="" IPHONE_LARGE_UDID="" IPAD_UDID="" DUO_UDID=""
DEVICES=()
if wants iphone; then
    IPHONE_UDID="$(ensure_device "$IPHONE_NAME" "$IPHONE_TYPE" || true)"
    [ -n "$IPHONE_UDID" ] \
        || { echo "no simulator named '$IPHONE_NAME', and creating one failed"; exit 1; }
    DEVICES+=("$IPHONE_UDID")
fi
# The 6.9" iPhone has screenshots only; its preview is the 6.3" one's.
if wants iphone && [ "$MODE" != video ]; then
    IPHONE_LARGE_UDID="$(ensure_device "$IPHONE_LARGE_NAME" "$IPHONE_LARGE_TYPE" || true)"
    [ -n "$IPHONE_LARGE_UDID" ] \
        || { echo "no simulator named '$IPHONE_LARGE_NAME', and creating one failed"; exit 1; }
    DEVICES+=("$IPHONE_LARGE_UDID")
fi
if wants ipad; then
    IPAD_UDID="$(ensure_device "$IPAD_NAME" "$IPAD_TYPE" || true)"
    [ -n "$IPAD_UDID" ] \
        || { echo "no simulator named '$IPAD_NAME', and creating one failed"; exit 1; }
    DEVICES+=("$IPAD_UDID")
fi
if wants duo && [ "$MODE" != video ]; then
    DUO_UDID="$(ensure_device "$DUO_NAME" "$DUO_TYPE" || true)"
    [ -n "$DUO_UDID" ] \
        || { echo "no simulator named '$DUO_NAME', and creating one failed (it needs Xcode 27.1 or later)"; exit 1; }
    DEVICES+=("$DUO_UDID")
fi

# The simulators are somebody's everyday ones, so they are put back the way they
# were when the run ends, however it ends: their languages, an installed Wordwander
# with its data (see save_install), and running or shut down. AppleLocale and
# AppleLanguages are each recorded as they were — set, or absent, which the run's
# own en_US must not outlive. A device that had never been booted has no
# preferences file yet, so both are absent and are deleted again. The one thing
# not put back is a status bar override of your own: it is cleared.
ORIGINAL_DEVICES=()
for udid in "${DEVICES[@]}"; do
    booted=no
    # Not `grep -q`: quitting at the first match can leave simctl writing into
    # a closed pipe, and under pipefail that reads as no match.
    xcrun simctl list devices | grep -F "($udid) (Booted)" >/dev/null && booted=yes
    region="$(plutil -extract AppleLocale raw "$(prefs_for "$udid")" 2>/dev/null || true)"
    ORIGINAL_DEVICES+=("$udid|$booted|$region|$(device_languages "$udid")")
done
restore_devices() {
    # Whatever fails here, the rest still has to be put back.
    set +e
    local entry udid booted region languages dir
    for entry in "${ORIGINAL_DEVICES[@]}"; do
        IFS='|' read -r udid booted region languages <<<"$entry"
        dir="$SAVED/$udid"
        # Only a device whose app save_install has accounted for: copied aside
        # whole, or found not installed. On any other the app is somebody's own —
        # never copied, or copied only in part — and the run never touched it.
        if [ -e "$dir/complete" ] || [ -e "$dir/none" ]; then
            # Booted first: a run that stopped mid-way can leave a device shut
            # down, and none of the next three commands works on one.
            xcrun simctl boot "$udid" >/dev/null 2>&1
            xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
            xcrun simctl status_bar "$udid" clear >/dev/null 2>&1
            # The poses leave a Debug build with a made-up history behind; nobody
            # should open the simulator later and find it in their own data.
            xcrun simctl uninstall "$udid" "$BID" >/dev/null 2>&1
            restore_install "$udid" || echo "  !! could not put back the app kept in $dir" >&2
        elif [ -d "$dir" ]; then
            echo "  !! the Wordwander on $udid was not copied aside in full, so it is left as it was" >&2
            if [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
                echo "     (what did get copied is in $dir)" >&2
            fi
        fi
        # An empty region or language list deletes that key again — also on a
        # device that had no preferences file at all, which the run gave one.
        # (set_device_language returns at once when nothing differs.)
        # shellcheck disable=SC2086
        set_device_language "$udid" "$region" $languages
        if [ "$booted" = yes ]; then
            xcrun simctl boot "$udid" >/dev/null 2>&1
        else
            xcrun simctl shutdown "$udid" >/dev/null 2>&1
        fi
    done
}

# Where the copies of an installed Wordwander go: Application Support, not WORK.
# WORK is in $TMPDIR, which macOS clears of files left unused for a few days, and
# the copy may be the only one left if putting it back failed; Caches is meant to
# be disposable and is what cleaning tools empty; the repository's .build/ goes
# with `swift package reset`. Application Support is for data that has to stay.
# The script never deletes a copy: its path is printed before the devices are
# put back, and removing it once the app is back is up to you.
SAVED_ROOT="$HOME/Library/Application Support/wordwander-appstore"
mkdir -p "$SAVED_ROOT"
SAVED="$(mktemp -d "$SAVED_ROOT/installed.XXXXXX")"

on_exit() {
    # Nothing may cut the restore short: a second Ctrl-C between uninstalling
    # the Debug build and putting the kept Wordwander back would leave the device
    # with neither. So from here on the signals that end a run are ignored, by
    # this shell and by the simctl calls it makes; the restore takes a minute.
    trap '' INT TERM HUP
    # Said first, so the copy can be found whatever happens below.
    if ls "$SAVED"/*/complete >/dev/null 2>&1; then
        echo "  the Wordwander that was installed is kept in $SAVED — delete it once it is back" >&2
    fi
    restore_devices
    if [ "$FINISHED" != yes ]; then
        echo "  the run's working files, the build log among them, are in $WORK" >&2
    elif [ "$OWN_WORK" = yes ]; then
        # The build and the takes, about 300 MB; nothing in WORK is needed now.
        rm -rf "$WORK"
    fi
    # A copy, whole or in part, is kept; a folder holding nothing but `none`
    # markers (no Wordwander was installed) is not worth leaving behind.
    if [ -z "$(find "$SAVED" -mindepth 2 ! -name none -print 2>/dev/null | head -n 1)" ]; then
        rm -rf "$SAVED"
    fi
}
trap on_exit EXIT

# ---------------------------------------------------------------- screenshots

# The daily puzzle's calendar opens on the current month, and early in a month
# most of the seeded 12-day streak sits on the previous month's page — so before
# the 7th the pose turns back a page, as a player would to see their streak. The
# streak ends yesterday, so on day d the previous month holds 13 − d of its days:
# most of them up to the 6th, and none at all from the 13th.
CAL_BACK=0
if [ "$(date +%-d)" -lt 7 ]; then CAL_BACK=1; fi

# name|extra settle seconds|launch arguments. The settle is what is left after
# the ready marker: the push animation, the level-complete card's entrance and
# its coins counting up. The order is the upload order and it matters more than
# the count: search results show the first three, and most people never scroll
# past them. See AppStore/screenshots.md for what each one is for.
#
# `-debugProgress N` seeds a player who has finished N levels and opens level
# N + 1, so N picks the landscape: chapter N / 12, landscape (N / 12) mod 24 —
# 101 is Northern Lights, 131 Frozen Fjord, 95 the last level of Cherry Blossom,
# 135 the first visit to the Firefly Forest.
# The words on the board are the puzzle's own in each language. `-debugElapsed`
# puts a believable time on the clock instead of the second a pose takes to set
# up. The wheel's letter order is shuffled on every launch, as in the game.
# `-debugLeave N` leaves N words unfound whatever the puzzle's size, which
# differs between the languages.
SHOTS=(
    "01-play|1.5|-debugProgress 101 -debugRoute level -debugLeave 3 -debugSpell longest -debugFinger 1 -debugElapsed 96"
    "02-journey|1.5|-debugProgress 95 -debugRoute journey"
    "03-daily|1.5|-debugProgress 95 -debugRoute dailyHub -debugCalendarBack $CAL_BACK"
    "04-calm|1.5|-debugProgress 46 -debugRoute level -debugLeave 3 -debugElapsed 71"
    "05-hints|1.5|-debugProgress 131 -debugRoute level -debugLeave 5 -debugSpotlight 1 -debugElapsed 133"
    "06-win|3.5|-debugProgress 95 -debugRoute level -debugSolve 99 -debugElapsed 154"
    "07-bonus|1.0|-debugProgress 135 -debugRoute level -debugGift 5 -debugBonusTip 1 -debugFinger 1 -debugElapsed 102"
    "08-trophies|1.5|-debugProgress 95 -debugRoute trophies"
    "09-chapter|1.5|-debugProgress 66 -debugRoute chapter"
    "10-home|1.5|-debugProgress 52"
)

# What a pose needs in one language only: the words, and for 07-bonus how many
# of them stay unfound, as level 136 has 8 words in English and 5 in Czech.
# 07-bonus finds one bonus word the way a player does, so the game's own one-time
# tip about the bonus gift comes up (`-debugBonusTip`), and leaves another
# half-swiped on the wheel. Both are words the wheel of level 136 can spell that
# are not in its crossword; the game refuses the pose, and the run stops, if the
# packs no longer agree.
locale_shot_args() { # locale_shot_args <locale> <shot name>
    case "$1/$2" in
        # NFIRDE: FINDER spells the whole wheel and is not in the crossword, beside
        # its FRIEND; EZOLKM: nor is KOZLEM, beside the crossword's ZLOMEK.
        en-US/07-bonus) printf '%s' "-debugLeave 4 -debugBonusLive END -debugSpell FINDER" ;;
        cs/07-bonus)    printf '%s' "-debugLeave 2 -debugBonusLive MLOK -debugSpell KOZLEM" ;;
    esac
}

shoot() { # shoot <udid> <locale> <device-dir> <W> <H> [<display>]
    local udid="$1" loc="$2" dev="$3" w="$4" h="$5" display="${6:-}"
    local dir="$OUT_ROOT/screenshots/$loc/$dev"
    # Shot aside and swapped in once the set is complete: a run that stops half-way
    # leaves the last good set whole, and a shot dropped from the list must not
    # linger beside the new set and get uploaded with it.
    local staging="$WORK/shots/$loc/$dev"
    rm -rf "$staging"
    mkdir -p "$staging"
    for entry in "${SHOTS[@]}"; do
        IFS='|' read -r name settle args <<<"$entry"
        # shellcheck disable=SC2086,SC2046
        launch "$udid" "$loc" $args $(locale_shot_args "$loc" "$name")
        local waited
        waited="$(wait_ready "$udid" 120)" || exit 1
        sleep "$settle"
        local shot_log
        if ! shot_log="$(xcrun simctl io "$udid" screenshot ${display:+--display="$display"} \
            "$staging/$name.png" 2>&1)"; then
            echo "  !! the $name screenshot failed: $shot_log" >&2
            exit 1
        fi
        local size
        size="$(magick identify -format '%wx%h' "$staging/$name.png")"
        printf '  %-16s %-10s ready in %ss\n' "$name" "$size" "$waited"
        # Every device shoots its slot size, so a mismatch means the simulator
        # is not the one this script expects rather than something to paper over.
        if [ "$size" != "${w}x${h}" ]; then
            echo "     !! expected ${w}x${h} — wrong simulator or a changed runtime (or a Duo turned on its side)"
            exit 1
        fi
        # A black frame is a display that was off: an iPhone Duo folded mid-run
        # still gives its inner display's full size.
        if [ "$(magick "$staging/$name.png" -alpha off -format '%[fx:maxima > 0.1]' info:)" != 1 ]; then
            echo "     !! the screen is black — was the iPhone Duo folded?"
            exit 1
        fi
    done
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
    mkdir -p "$dir"
    rm -f "$dir"/*.png
    mv "$staging"/*.png "$dir"/
}

if [ "$MODE" = all ] || [ "$MODE" = screenshots ]; then
    command -v magick >/dev/null \
        || { echo "needs ImageMagick (brew install imagemagick)"; exit 1; }
    # The Duo first, in both languages, because it is the one that needs a
    # hand (wait_unfolded): the run asks in its first few minutes, while you
    # are still there, and the rest runs on its own.
    if wants duo; then
        for loc in cs en-US; do
            say "Screenshots — iPhone Duo / $loc"
            boot_and_install "$DUO_UDID" "$loc"
            wait_unfolded "$DUO_UDID"
            shoot "$DUO_UDID" "$loc" iphone-duo "${DUO_SHOT_SIZE[@]}" "$DUO_DISPLAY"
            shut_down "$DUO_UDID"
        done
    fi
    for loc in cs en-US; do
        if wants iphone; then
            say "Screenshots — iPhone 6.3\" / $loc"
            boot_and_install "$IPHONE_UDID" "$loc"
            shoot "$IPHONE_UDID" "$loc" iphone-6.3 "${IPHONE_SHOT_SIZE[@]}"
            shut_down "$IPHONE_UDID"
            say "Screenshots — iPhone 6.9\" / $loc"
            boot_and_install "$IPHONE_LARGE_UDID" "$loc"
            shoot "$IPHONE_LARGE_UDID" "$loc" iphone-6.9 "${IPHONE_LARGE_SHOT_SIZE[@]}"
            shut_down "$IPHONE_LARGE_UDID"
        fi
        if wants ipad; then
            say "Screenshots — iPad 13\" / $loc"
            boot_and_install "$IPAD_UDID" "$loc"
            shoot "$IPAD_UDID" "$loc" ipad-13 "${IPAD_SHOT_SIZE[@]}"
            shut_down "$IPAD_UDID"
        fi
    done

    # The simulator writes RGBA even though every pixel is opaque, and App Store
    # Connect wants screenshots without transparency. Dropping the channel leaves
    # the picture untouched and saves about a third of the size — verified rather
    # than assumed, and anything that is not identical is left alone. `-strip`
    # drops the colour tag too, which the pixel comparison cannot see; that is
    # safe only because simctl tags its screenshots sRGB (an `sRGB` chunk, checked
    # with `sips -g profile` on iOS 27.2), which is what untagged pixels are read
    # as. A screenshot tagged Display P3 would need its profile kept. `PNG24:`
    # keeps it truecolour: left to choose, ImageMagick writes a picture of few
    # colours as a palette PNG, down to one bit.
    say "Squeezing PNGs (lossless)"
    while IFS= read -r f; do
        magick "$f" -alpha off -depth 8 -strip \
                    -define png:compression-level=9 \
                    -define png:compression-filter=5 "PNG24:$f.opt"
        if [ "$(magick compare -metric AE "$f" "$f.opt" null: 2>&1 | awk '{print $1}')" = "0" ]; then
            mv "$f.opt" "$f"
        else
            rm -f "$f.opt"
            echo "  left as-is (not identical): $f"
        fi
    done < <(find "$OUT_ROOT/screenshots" -name '*.png')
    du -sh "$OUT_ROOT/screenshots"
fi

# ---------------------------------------------------------------- preview

# One continuous take of a game being played (GameController.playDemo): the
# last level of the Cherry Blossom chapter, part of it already found, the rest
# swiped word by word at a person's pace by a finger drawn on the wheel — a
# bonus word on the way, which opens the bonus gift — then the level-complete
# card with the chapter reward and the confetti, "Next level", and the Northern
# Lights sliding in, where one more word is found. That is the whole game in
# twenty seconds: swiping, the crossword filling in, bonus words, rewards and
# the journey from one landscape to the next.
#
# The words are the puzzle's own, so they differ by language, and so does the
# bonus word: one the wheel can spell, common enough to read at a glance.
# `-debugGift 9` leaves the gift one word short, so the bonus word opens it.
# `-debugElapsed` puts a believable time on the level-complete card, and
# `-debugDemoLead` gives the recorder time to come up (see below).
demo_args() { # demo_args <locale>
    local common="-debugProgress 95 -debugRoute level -debugGift 9 -debugElapsed 128 -debugDemoLead 2.5"
    case "$1" in
        # EMIPLS: LIE LIES LIPS MILE are found; SLIP MILES (SLIM) SMILE SIMPLE
        # are swiped; then MET on EHMTE.
        en-US) printf '%s' "$common -debugDemo 4 -debugDemoBonus SLIM" ;;
        # AKOUTP: PAK POT are found; TAK AUTO (KOUPAT) KOPAT POKUTA are swiped;
        # then MÍT on SÍTMO.
        cs)    printf '%s' "$common -debugDemo 4 -debugDemoBonus KOUPAT" ;;
    esac
}
RECORD_SECONDS=24

# The app drops the ready marker the moment the board is up and starts playing
# `-debugDemoLead` (2.5) seconds later; recording starts as soon as the marker
# is seen, so the lead is what the recorder has to come up in (`record` checks
# that it did), and the cut
# points below are measured from it. The demo's pauses are fixed in the app,
# but the whole take still drifts by up to a second from run to run — the
# simulator does not keep exactly the same pace — so each cut ends about two
# seconds after the last word goes in, not on it. A take that stalls outright is
# caught by `assemble` (gaps.swift) before it is cut.
#
# Cut points, in seconds into the recording, measured on both devices (see
# AppStore/screenshots.md for the timeline). Both languages swipe five words,
# the bonus word included, of the same length (24 letters), so both cuts are
# the same 18.5 s. Nothing may reach into the last two seconds or so of a
# recording, past about 22 s of these 24: the tail is not reliably decodable,
# and a range that crosses it
# comes out holding one frame while every step reports success (learned on the
# chess project). Apple wants 15 to 30 seconds.
cut_for() { # cut_for <locale> <clip.mp4>
    local cut late
    case "$1" in
        en-US) cut='2.0:20.5' ;;
        cs)    cut='2.0:20.5' ;;
    esac
    # The points are for a recorder that came up 0.2 s after the app wrote the
    # marker (0.1 s for the recorder, and on average as long again for the script
    # to see the marker). One that came up later started that much later into the
    # game, so the whole cut moves back by the difference (`record` keeps it beside
    # the take), and the preview opens on the same moment whatever the recorder
    # and the polling did.
    late="$(cat "$2.late")"
    awk -v c="$cut" -v l="$late" 'BEGIN { split(c, p, ":"); s = l - 0.2; printf "%.2f:%.2f", p[1] - s, p[2] - s }'
}

now() { # seconds since the epoch, to the millisecond (`date` has no %N on macOS)
    python3 -c 'import time; print(f"{time.time():.3f}")'
}

record() { # record <udid> <locale> <out.mp4>
    local udid="$1" loc="$2" out="$3"
    mkdir -p "$(dirname "$out")"
    # A rehearsal first, unrecorded. SwiftUI compiles a Metal pipeline the first
    # time it draws something new, on the main thread, and keeps it in the app's
    # Caches — which the clean install has just emptied. On the 13" iPad the
    # level-complete card (its blurred material and the confetti) took over a
    # second to compile, and the take stood still at the last word. Played once
    # through, every pipeline the take needs is on disk before it starts.
    # shellcheck disable=SC2046
    launch "$udid" "$loc" $(demo_args "$loc")
    wait_ready "$udid" 120 >/dev/null || exit 1
    sleep "$RECORD_SECONDS"
    # Looked up before the take: the recorder should start the moment the marker
    # is seen, not after another simctl call.
    local marker
    marker="$(ready_marker "$udid")" || exit 1
    # shellcheck disable=SC2046
    launch "$udid" "$loc" $(demo_args "$loc")
    local waited marked
    waited="$(wait_ready "$udid" 120)" || exit 1
    # The moment the app wrote the marker, which the demo's lead is counted from.
    # Measured from when the script saw it instead, the up to 0.2 s the polling
    # took would go uncounted into the cut.
    marked="$(stat -f %Fm "$marker")" || exit 1
    local log="$WORK/recorder.log"
    xcrun simctl io "$udid" recordVideo --codec h264 --force "$out" >/dev/null 2>"$log" &
    local pid=$!
    # simctl says on stderr when it has actually started — about 0.1 s in, and
    # anything up to 1.5 s on a busy Mac. How long it took is kept beside the take
    # for cut_for, which moves the cut back by it. Only a start so slow that the
    # moved cut would begin before the recording does is refused.
    local ticks=0
    until grep -q "Recording started" "$log" 2>/dev/null; do
        ticks=$((ticks + 1))
        if ! kill -0 $pid 2>/dev/null || [ "$ticks" -gt 200 ]; then
            kill -INT $pid 2>/dev/null || true
            echo "  !! the recorder did not start: $(cat "$log")" >&2
            exit 1
        fi
        sleep 0.02
    done
    local late
    late="$(awk -v a="$marked" -v b="$(now)" 'BEGIN { printf "%.2f", b - a }')"
    if awk -v l="$late" 'BEGIN { exit !(l > 2.0) }'; then
        kill -INT $pid 2>/dev/null || true
        wait $pid 2>/dev/null || true
        echo "  !! the recorder took ${late}s to start, too late for the cut to start in time; run it again" >&2
        exit 1
    fi
    printf '%s' "$late" > "$out.late"
    sleep "$RECORD_SECONDS"
    kill -INT $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
    sleep 1
    printf '  %-10s %s (ready in %ss, recorder up %ss after the marker)\n' "$(basename "$out" .mp4)" \
        "$(avmediainfo "$out" | awk '/^Duration:/{print $2 "s"}')" "$waited" "$late"
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
}

assemble() { # assemble <clip.mp4> <out.mp4> <W> <H> <in:out>
    local clip="$1" out="$2" w="$3" h="$4" cut="$5"
    # First whether the take is worth cutting at all. A simulator that stalls
    # mid-take pushes everything after it late, and every step below would
    # still report success; the gap check names the clip and the stall instead.
    # Half a second, not gaps.swift's own 1.5: the landscape behind the game
    # never stops drifting, so a good take is never still for long (0.40 s at
    # most so far).
    swift "$ROOT/Tools/AppStoreMedia/gaps.swift" "$clip:$cut" 0.5 || exit 1
    mkdir -p "$(dirname "$out")"
    # The cut is ProRes, so the picture is encoded to H.264 once, by conform, and
    # nothing hides frames behind an edit list on the way (see video.swift).
    local cut_file="$WORK/cut.mov"
    swift "$ROOT/Tools/AppStoreMedia/video.swift" "$cut_file" "$w" "$h" "$clip:$cut"
    # What comes out of the cut is the right size and the wrong everything else
    # for App Store Connect — the wrong codec, too fast a bit rate and no audio at
    # all. This pins the lot to Apple's table, rewriting the file in place as the
    # finished MP4. The gain travels with the music: on its own it would land in
    # the music file's place.
    swift "$ROOT/Tools/AppStoreMedia/conform.swift" "$cut_file" "$w" "$h" \
        ${PREVIEW_MUSIC:+"$PREVIEW_MUSIC" "$PREVIEW_GAIN"}
    mv -f "$cut_file" "$out"
    # Every step above reports success even when the result is short, so measure
    # it. (Conform has already checked its frames: exactly 30 a second, all alike.)
    local want got
    want="$(awk -v c="$cut" 'BEGIN { split(c, p, ":"); printf "%.2f", p[2] - p[1] }')"
    # awk reads to the end rather than `exit` at the first match: quitting early can
    # leave avmediainfo writing into a closed pipe, and under pipefail that fails
    # the run after a good encode.
    got="$(avmediainfo "$out" | awk '/^Duration:/ && !seen { printf "%.2f", $2; seen = 1 }')"
    if awk -v a="$want" -v b="$got" 'BEGIN { exit !(a - b > 0.05 || b - a > 0.05) }'; then
        echo "  !! $(basename "$out") is ${got}s, the cut asks for ${want}s" >&2
        exit 1
    fi
}

if { [ "$MODE" = all ] || [ "$MODE" = video ]; } && { wants iphone || wants ipad; }; then
    # The default bed is made again on every run: in a WORK=… of your own, one left
    # by an earlier run would otherwise outlive a change to music.py.
    if [ "$PREVIEW_MUSIC" = "$DEFAULT_MUSIC" ] || { [ -n "$PREVIEW_MUSIC" ] && [ ! -f "$PREVIEW_MUSIC" ]; }; then
        say "Synthesising the music bed"
        python3 "$ROOT/Tools/AppStoreMedia/music.py" "$PREVIEW_MUSIC" 32
    fi
    # Made aside, like the screenshots, and swapped in only once every one has
    # passed every check: a run that stops on a stalled take leaves the last
    # good set whole, rather than new previews beside old ones, or a bad one in
    # their place.
    staging="$WORK/preview"
    rm -rf "$staging"
    for loc in cs en-US; do
        if wants iphone; then
            say "Preview — iPhone 6.3\" / $loc"
            boot_and_install "$IPHONE_UDID" "$loc"
            record "$IPHONE_UDID" "$loc" "$WORK/clips/iphone-$loc.mp4"
            shut_down "$IPHONE_UDID"
            assemble "$WORK/clips/iphone-$loc.mp4" "$staging/$loc/iphone-6.3.mp4" \
                "${IPHONE_VIDEO_SIZE[@]}" "$(cut_for "$loc" "$WORK/clips/iphone-$loc.mp4")"
            # The 6.9" iPhone's and the Duo's previews are this one (see
            # IPHONE_VIDEO_SIZE), copied under their names so that every slot in
            # Connect has a file of its own.
            cp "$staging/$loc/iphone-6.3.mp4" "$staging/$loc/iphone-6.9.mp4"
            cp "$staging/$loc/iphone-6.3.mp4" "$staging/$loc/iphone-duo.mp4"
        fi
        if wants ipad; then
            say "Preview — iPad 13\" / $loc"
            boot_and_install "$IPAD_UDID" "$loc"
            record "$IPAD_UDID" "$loc" "$WORK/clips/ipad-$loc.mp4"
            shut_down "$IPAD_UDID"
            assemble "$WORK/clips/ipad-$loc.mp4" "$staging/$loc/ipad-13.mp4" \
                "${IPAD_VIDEO_SIZE[@]}" "$(cut_for "$loc" "$WORK/clips/ipad-$loc.mp4")"
        fi
    done
    for loc in cs en-US; do
        mkdir -p "$OUT_ROOT/preview/$loc"
        # A run for every device replaces the whole folder, so a preview for a
        # slot the listing no longer uses does not linger and get uploaded; a
        # run for one device replaces only its own.
        if [ -z "$ONLY" ]; then rm -f "$OUT_ROOT/preview/$loc"/*.mp4; fi
        mv -f "$staging/$loc"/*.mp4 "$OUT_ROOT/preview/$loc"/
    done
fi

# ---------------------------------------------------------------- tidy up

# The build and the takes come to about 300 MB a run, in a folder of its own
# every run, so on_exit deletes that folder once the devices are put back —
# after a run that got this far only. A failed run keeps everything, the build
# log and the takes being what tells you why, and a WORK=… of your own is never
# deleted. A Wordwander copied aside is not in WORK (see SAVED) and is never deleted.
FINISHED=yes
say "Done."
