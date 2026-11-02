//
//  gaps.swift
//  Wordwander App Store tools
//
//  Fails a raw simulator take that stands still for too long inside its cut —
//  the one way a take goes wrong that nothing after it notices.
//
//      swift Tools/AppStoreMedia/gaps.swift <clip.mp4>[:<in>:<out>] [<limit-seconds>]
//
//  `simctl io recordVideo` writes a frame only when the screen changes, so a
//  take is variable frame rate and a still stretch in it is simply one long
//  frame. In Wordwander's demo something is always moving, letters or not: every
//  landscape drifts its clouds and particles, so the longest still stretch in a
//  good take measured 0.06–0.40 s. A take in which the simulator stalled differs by
//  that alone — on the Sudoku project, where this check comes from, one take
//  stood still for 2.21 s while the game went on behind it, so everything after
//  came late and the preview ran out before the result card, and the cut, the
//  encode and the length check all reported success. So anything longer than the
//  limit fails, naming the clip and the stretch, and the take has to be recorded
//  again. The default limit is Sudoku's 1.5 s; media.sh passes 0.5 s, which a
//  moving landscape never comes near.
//
//  The whole stretch counts once any of it is inside the cut, because a stall
//  just before the cut shifts everything in it too. So does the stretch from a
//  take's last frame to the end of the cut, which video.swift fills by
//  holding that frame: a few frames of a screen that has settled are fine, a
//  take that stopped seconds early is not.
//
//  Without a range the whole take is checked, which is also how to look at a
//  finished preview: at a constant 30 fps its longest frame is 0.03 s.
//
//  Used by Tools/AppStoreMedia/media.sh before every cut; see AppStore/screenshots.md.
//
import AVFoundation
import CoreMedia
import Foundation

let argv = CommandLine.arguments
func usage() -> Never {
    FileHandle.standardError.write(Data(
        "usage: gaps.swift <clip.mp4>[:<in>:<out>] [<limit-seconds>]\n".utf8))
    exit(2)
}
guard argv.count == 2 || argv.count == 3 else { usage() }

// The clip and the range in the form video.swift takes them, so
// media.sh hands both tools the same argument. The range is read from the end:
// the path before it may hold colons of its own (a WORK= folder named so).
let parts = argv[1].split(separator: ":", omittingEmptySubsequences: false)
let clipURL: URL
var range: (start: Double, end: Double)?
if parts.count >= 3, let start = Double(parts[parts.count - 2]), let end = Double(parts[parts.count - 1]) {
    let path = parts.dropLast(2).joined(separator: ":")
    guard !path.isEmpty, start < end else { usage() }
    clipURL = URL(fileURLWithPath: path)
    range = (start, end)
} else {
    clipURL = URL(fileURLWithPath: argv[1])
}
let limit = argv.count == 3 ? Double(argv[2]) ?? -1 : 1.5
guard limit > 0 else { usage() }

let done = DispatchSemaphore(value: 0)

Task {
    do {
        // AVFoundation's own word for a missing file is "The operation could not
        // be completed".
        guard FileManager.default.fileExists(atPath: clipURL.path) else {
            throw NSError(domain: "appstore_gaps", code: 5, userInfo:
                            [NSLocalizedDescriptionKey: "no such file: \(clipURL.path)"])
        }
        let asset = AVURLAsset(url: clipURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "appstore_gaps", code: 1, userInfo:
                            [NSLocalizedDescriptionKey: "no video track in \(clipURL.lastPathComponent)"])
        }
        let takeEnd = try await track.load(.timeRange).end.seconds

        // The samples as they are stored, nothing decoded: only the timestamps
        // are wanted, and a whole take reads in well under a second.
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "appstore_gaps", code: 2, userInfo:
                                            [NSLocalizedDescriptionKey: "could not read \(clipURL.lastPathComponent)"])
        }
        var frames: [Double] = []
        while let buffer = output.copyNextSampleBuffer() {
            let count = CMSampleBufferGetNumSamples(buffer)
            guard count > 0 else { continue }
            var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
            CMSampleBufferGetOutputSampleTimingInfoArray(
                buffer, entryCount: count, arrayToFill: &timing, entriesNeededOut: nil)
            frames += timing.map(\.presentationTimeStamp).filter(\.isValid).map(\.seconds)
        }
        if reader.status == .failed {
            throw reader.error ?? NSError(domain: "appstore_gaps", code: 3, userInfo:
                                            [NSLocalizedDescriptionKey: "could not read \(clipURL.lastPathComponent)"])
        }
        guard !frames.isEmpty else {
            throw NSError(domain: "appstore_gaps", code: 4, userInfo:
                            [NSLocalizedDescriptionKey: "no frames in \(clipURL.lastPathComponent)"])
        }
        frames.sort()

        // Each frame stands until the next one; the last until the take ends, or
        // until the cut does if the cut runs on past it (the held frame).
        let window = range ?? (frames[0], takeEnd)
        let edges = frames + [max(takeEnd, window.end)]
        var longest = (start: 0.0, length: 0.0)
        var stalls: [(start: Double, length: Double)] = []
        for i in 0..<frames.count {
            let start = edges[i], end = edges[i + 1]
            guard start < window.end, end > window.start else { continue }
            let length = end - start
            if length > longest.length { longest = (start, length) }
            if length > limit { stalls.append((start, length)) }
        }

        let name = clipURL.lastPathComponent as NSString
        let span = String(format: "%.2f→%.2f", window.start, window.end)
        let place = range == nil ? "in the take" : "inside the cut \(span)"
        guard stalls.isEmpty else {
            for stall in stalls {
                let what = stall.start + stall.length > takeEnd + 0.001
                    ? String(format: "ends at %.2fs, so its last frame would stand still for %.2fs",
                             takeEnd, stall.length)
                    : String(format: "stands still for %.2fs from %.2fs", stall.length, stall.start)
                FileHandle.standardError.write(Data(String(
                    format: "  !! %@ %@, %@ (the limit is %.2fs)\n",
                    name, what, place, limit).utf8))
            }
            FileHandle.standardError.write(Data(
                "     the take stalled — record it again (Tools/AppStoreMedia/media.sh video)\n".utf8))
            exit(1)
        }
        print(String(format: "  %@  %@  still at most %.2fs (at %.2fs)  take ends %.2fs",
                     name, span, longest.length, longest.start, takeEnd))
    } catch {
        FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    done.signal()
}

done.wait()
