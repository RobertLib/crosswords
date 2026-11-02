//
//  video.swift
//  Wordwander App Store tools
//
//  Cuts recorded simulator clips into one App Preview: concatenates the given
//  time ranges, scales them to the size App Store Connect expects and writes
//  them at 30 fps (the simulator records at ~72 fps, which Apple rejects) —
//  as ProRes 422 to a `.mov`, H.264 otherwise. media.sh cuts to ProRes
//  and lets conform.swift do the one H.264 encode: an H.264 export
//  reorders frames and hides the first two behind an edit list, so a cut came
//  out 0.07 s short and a generation worse.
//
//      swift Tools/AppStoreMedia/video.swift <out.mp4> <width> <height> \
//          <clip.mp4>:<in>:<out> ...
//
//  A range that runs past the end of its clip holds the clip's last frame for
//  the rest, so the preview always comes out as long as the cut asks: the
//  simulator stops writing frames once the screen stops changing, and a take
//  can end earlier than the cut.
//
//  30 fps everywhere but, sometimes, the very end: when the take's last change
//  inside the range comes a few frames before its end, the export stretches
//  that frame rather than repeating it (one cut ended on a frame of 1/6 s).
//  conform.swift puts every frame back on the 30 fps grid.
//
//  Used by Tools/AppStoreMedia/media.sh; see AppStore/screenshots.md.
//  The Sudoku project's appstore_video.swift (github.com/RobertLib/sudoku),
//  which took it from the chess project and added the fill scaling and the held
//  last frame; unchanged here but for the names.
//
import AVFoundation
import CoreMedia
import Foundation

let argv = CommandLine.arguments
guard argv.count > 4, let targetW = Double(argv[2]), let targetH = Double(argv[3]) else {
    FileHandle.standardError.write(Data(
        "usage: video.swift <out.mp4> <width> <height> <clip.mp4>:<in>:<out>...\n".utf8))
    exit(2)
}

let outURL = URL(fileURLWithPath: argv[1])
let fps: Int32 = 30

struct Segment {
    let url: URL
    let start: Double
    let end: Double
}

let segments: [Segment] = argv[4...].map { spec in
    // The range is read from the end: the path before it may hold colons of its own (a WORK=
    // folder named so).
    let parts = spec.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count >= 3, let start = Double(parts[parts.count - 2]), let end = Double(parts[parts.count - 1]),
          !parts.dropLast(2).joined(separator: ":").isEmpty else {
        FileHandle.standardError.write(Data("bad segment: \(spec)\n".utf8))
        exit(2)
    }
    return Segment(url: URL(fileURLWithPath: parts.dropLast(2).joined(separator: ":")), start: start, end: end)
}

let done = DispatchSemaphore(value: 0)

Task {
    do {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "appstore_video", code: 1, userInfo:
                            [NSLocalizedDescriptionKey: "could not add a video track"])
        }

        var instructions: [AVMutableVideoCompositionInstruction] = []
        var cursor = CMTime.zero

        for segment in segments {
            let asset = AVURLAsset(url: segment.url)
            guard let source = try await asset.loadTracks(withMediaType: .video).first else {
                throw NSError(domain: "appstore_video", code: 2, userInfo:
                                [NSLocalizedDescriptionKey:
                                    "no video track in \(segment.url.lastPathComponent)"])
            }
            let natural = try await source.load(.naturalSize)
            let range = CMTimeRange(
                start: CMTime(seconds: segment.start, preferredTimescale: 600),
                end: CMTime(seconds: segment.end, preferredTimescale: 600))
            let clipEnd = try await source.load(.timeRange).end
            let recorded = CMTimeRange(start: range.start, end: min(range.end, clipEnd))
            try track.insertTimeRange(recorded, of: source, at: cursor)
            if recorded.end < range.end {
                // Stretch the clip's last frame over the rest of the range.
                let frame = CMTime(value: 1, timescale: fps)
                let last = CMTimeRange(start: recorded.end - frame, duration: frame)
                let at = cursor + recorded.duration
                try track.insertTimeRange(last, of: source, at: at)
                track.scaleTimeRange(CMTimeRange(start: at, duration: frame),
                                     toDuration: range.end - recorded.end)
                print(String(format: "  %-18@ ends at %5.2fs: last frame held for %4.2fs",
                             segment.url.lastPathComponent as NSString,
                             clipEnd.seconds, (range.end - recorded.end).seconds))
            }

            // Fill the frame and centre: scale by the larger of the two ratios,
            // so the picture is cropped by a fraction of a pixel rather than
            // letterboxed. Scaling by the width alone left a black row at the top
            // and the bottom of the Sudoku project's iPhone preview, whose recording
            // (1242 × 2688) came out 1917.5 rows tall at 886 wide. This game's
            // (1206 × 2622, iPhone 18 Pro) comes out 1926.3 rows tall, so it loses
            // three rows at the top and three at the bottom instead.
            let scale = max(targetW / natural.width, targetH / natural.height)
            let tx = (targetW - natural.width * scale) / 2
            let ty = (targetH - natural.height * scale) / 2
            let transform = CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(translationX: tx, y: ty))

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layer.setTransform(transform, at: .zero)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: range.duration)
            instruction.layerInstructions = [layer]
            instructions.append(instruction)

            cursor = cursor + range.duration
            print(String(format: "  %-18@ %5.2f→%5.2f  %5.2fs   running %5.2fs",
                         segment.url.lastPathComponent as NSString,
                         segment.start, segment.end, range.duration.seconds, cursor.seconds))
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: targetW, height: targetH)
        videoComposition.frameDuration = CMTime(value: 1, timescale: fps)
        videoComposition.instructions = instructions

        let isProRes = outURL.pathExtension.lowercased() == "mov"
        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: isProRes ? AVAssetExportPresetAppleProRes422LPCM : AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "appstore_video", code: 3, userInfo:
                            [NSLocalizedDescriptionKey: "could not create an export session"])
        }
        export.videoComposition = videoComposition
        try? FileManager.default.removeItem(at: outURL)
        try await export.export(to: outURL, as: isProRes ? .mov : .mp4)

        print(String(format: "→ %@  %d×%d  %.2fs  30 fps",
                     outURL.path, Int(targetW), Int(targetH), cursor.seconds))
    } catch {
        FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    done.signal()
}

done.wait()
