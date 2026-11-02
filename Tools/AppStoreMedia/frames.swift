//
//  frames.swift
//  Wordwander App Store tools
//
//  Pulls still frames out of a finished App Preview so the cut can be checked
//  without watching it.
//
//      swift Tools/AppStoreMedia/frames.swift <video.mp4> <out-dir> <seconds>...
//
//  The preview is one continuous take cut from a recording (see
//  AppStore/screenshots.md), and nothing enforces that the cut still frames the
//  game: a cut that has drifted past the action does not fail, it just opens or
//  ends on the wrong moment. So the check is to look at its opening, the bonus
//  gift, the level-complete card and the next landscape — which is what this is
//  for, and why it is a tool rather than a line of ffmpeg: ffmpeg is not
//  installed on a stock macOS, and this needs nothing that is not already here.
//  (The Sudoku project's appstore_frames.swift, unchanged but for the names.)
//
//  Frames come out named after their timestamp (`at-04.90s.png`), so a contact
//  sheet made of them is in order:
//
//      swift Tools/AppStoreMedia/frames.swift AppStore/preview/en-US/iphone-6.3.mp4 \
//          /tmp/frames 0.2 1.5 4.5 7.5 11.5 13 15.5 16.8
//      magick /tmp/frames/*.png -resize 240x +append /tmp/sheet.png
//
//  (`magick montage` needs a font for its labels, and the Homebrew ImageMagick
//  has no fontconfig map to find one with; `+append` needs none.)
//
//  Seeking is tolerant to one frame, not to the nearest keyframe: a keyframe snap
//  can land on the very frame you were trying to rule out. Zero tolerance was
//  tried first and is worse than it sounds — the finished previews are all-intra
//  and seek to the exact frame either way, but the *raw* simulator recordings are
//  variable frame rate, and on those an exact request past about 21 s silently
//  came back with the last frame it could find instead. A frame's worth of slack
//  costs nothing and makes the raw clips seekable, which is where the cut points
//  are actually chosen.
//
import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

let argv = CommandLine.arguments
guard argv.count >= 4 else {
    FileHandle.standardError.write(Data(
        "usage: frames.swift <video.mp4> <out-dir> <seconds>...\n".utf8))
    exit(2)
}

let videoURL = URL(fileURLWithPath: argv[1])
let outDir = URL(fileURLWithPath: argv[2])
let times = argv[3...].compactMap(Double.init)
guard times.count == argv.count - 3 else {
    FileHandle.standardError.write(Data("every argument after the directory has to be a number\n".utf8))
    exit(2)
}

let done = DispatchSemaphore(value: 0)

Task {
    do {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // One frame at 30 fps, either side; see the header.
        let slack = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceBefore = slack
        generator.requestedTimeToleranceAfter = slack

        var missed = 0
        for seconds in times {
            let requested = CMTime(seconds: seconds, preferredTimescale: 600)
            let (image, actual) = try await generator.image(at: requested)
            // Past the end the generator hands back the last frame rather than failing,
            // and a "check frame" that is quietly another frame checks nothing.
            if abs(actual.seconds - seconds) > slack.seconds + 0.001 {
                FileHandle.standardError.write(Data(String(
                    format: "  asked %6.2fs  got %6.2fs  skipped: not there (past the end?)\n",
                    seconds, actual.seconds).utf8))
                missed += 1
                continue
            }
            let name = String(format: "at-%05.2fs.png", seconds)
            let url = outDir.appendingPathComponent(name)
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw NSError(domain: "appstore_frames", code: 1, userInfo:
                                [NSLocalizedDescriptionKey: "could not write \(name)"])
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw NSError(domain: "appstore_frames", code: 2, userInfo:
                                [NSLocalizedDescriptionKey: "could not finalise \(name)"])
            }
            print(String(format: "  %@  asked %6.2fs  got %6.2fs  %dx%d",
                         name, seconds, actual.seconds, image.width, image.height))
        }
        if missed > 0 { exit(1) }
    } catch {
        FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    done.signal()
}

done.wait()
