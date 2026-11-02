//
//  conform.swift
//  Wordwander App Store tools
//
//  Rewrites a finished App Preview into exactly the shape App Store Connect
//  accepts. The upload check is strict and its error messages are not: it
//  reports "unsupported or corrupted audio" for problems that have nothing to
//  do with sound, so everything here is pinned rather than left to a preset.
//
//      swift Tools/AppStoreMedia/conform.swift <preview.mp4> <width> <height> \
//          [<music.wav> [gain]]
//
//  Wordwander ships with no audio files — its sounds are synthesised on the
//  device — so the bed comes from Tools/AppStoreMedia/music.py, a WAV, rather
//  than from the bundle. Anything else AVFoundation reads (m4a, caf, aiff) will
//  do as well. This file is the Sudoku project's appstore_conform.swift
//  (github.com/RobertLib/sudoku), itself the chess project's, unchanged but for
//  the names and the note on the bit rate — so a fix in one belongs in the others.
//
//  Apple's specification (App Store Connect Help → App preview specifications):
//
//      resolution   iPhone 886 × 1920, iPad 13" 1200 × 1600 (portrait)
//      video        H.264 High Profile Level 4.0, progressive, 30 fps
//      bit rate     10–12 Mbps VBR
//      audio        stereo AAC, 256 kbps, 44.1 or 48 kHz — required
//      duration     15–30 s, at most 500 MB
//
//  Two things about that list are worth knowing, because both cost an upload to
//  find out. The native device resolution is *not* accepted — the one 886 × 1920
//  file is what Apple lists for every iPhone slot from 6.9" down to 6.1", and
//  the device's own 1206 × 2622 is not on the list — and Level 4.0 is a real
//  ceiling, so a preview at the device's own size comes out as Level 5.0 and is
//  refused. Silence does not satisfy the audio requirement either: AAC
//  compresses digital silence to about 2 kbps, two orders of magnitude under
//  the 256 kbps asked for, and a preview with no usable audio is treated as an
//  unsupported audio configuration. Hence the music bed — pass a file and it is
//  looped under the whole cut.
//
//  The picture is re-encoded, which it has to be to hit the profile and the
//  size. The final mux inserts both encoded tracks from time zero, so the video
//  comes out without the offset edit list a composed export carries; the audio
//  keeps the usual AAC priming edit (about 44 ms), which every AAC file has.
//
//  And every frame is put on an exact 30 fps grid — frame n at n/30 s, lasting
//  1/30 s, as many as the length asks for — because nothing upstream promises
//  it. A video composition renders a frame only where its source has one: when
//  the take's last change inside the cut comes a few frames before the cut's
//  end, the cut — and the composition output read here — stops those few
//  frames short, and closing the session at the cut's end stretched the last
//  one over the rest. One preview went up as 559 frames of 1/30 s and one of
//  1/6 s: 18.8 s long, and not 30 fps. So a frame the source does not have is
//  the one before it, repeated, and the last line checks the written file for
//  exactly that.
//
//  Used by Tools/AppStoreMedia/media.sh; see AppStore/screenshots.md.
//
import AVFoundation
import CoreMedia
import Foundation

let argv = CommandLine.arguments
guard argv.count >= 4, argv.count <= 6,
      let targetW = Double(argv[2]), let targetH = Double(argv[3]) else {
    FileHandle.standardError.write(Data(
        "usage: conform.swift <preview.mp4> <width> <height> [<music.wav> [gain]]\n".utf8))
    exit(2)
}

let videoURL = URL(fileURLWithPath: argv[1])
let targetSize = CGSize(width: targetW, height: targetH)
let musicURL = argv.count > 4 ? URL(fileURLWithPath: argv[4]) : nil
// A gain that does not parse (a typo, or a decimal comma: "0,5") stops the run
// rather than quietly mixing the music at the default level.
let gain: Float
if argv.count > 5 {
    guard let parsed = Float(argv[5]), parsed.isFinite, parsed >= 0 else {
        FileHandle.standardError.write(Data("conform.swift: gain '\(argv[5])' is not a number of 0 or more\n".utf8))
        exit(2)
    }
    gain = parsed
} else {
    gain = 0.7
}

let fps: Int32 = 30
// Apple's band is 10–12 Mbps, and `AVVideoAverageBitRateKey` is a *ceiling*, not
// a target — the encoder spends what the picture needs and no more. Flat UI
// needs very little: on the Sudoku project, whose board is eighty-one flat cells,
// asking for 14 Mbps with an ordinary one-second GOP measured well under the
// floor, and Wordwander's drawn landscapes are flat colour too.
//
// What makes the number behave like a floor is `AVVideoMaxKeyFrameIntervalKey: 1`
// below — with every frame an I-frame there is no temporal prediction to save
// bits with, so each frame takes its equal share of the average and the result
// lands on the number asked for. Measured: 11.5 requested → 11.5 delivered,
// 35 MB for 25 s, well inside Level 4.0's ceiling and nowhere near Connect's
// 500 MB. Do not "optimise" the GOP back without re-measuring; a GOP of 2 was
// tried and came out at 26.5 Mbps, which is out of spec on its own.
let videoBitRate = 11_500_000
let sampleRate = 48_000.0
let audioChannels = 2
let audioBitRate = 256_000
let fadeIn = 0.5
let fadeOut = 1.5

func problem(_ code: Int, _ message: String) -> NSError {
    NSError(domain: "appstore_conform", code: code,
            userInfo: [NSLocalizedDescriptionKey: message])
}

func time(_ seconds: Double) -> CMTime {
    CMTime(seconds: seconds, preferredTimescale: 600)
}

/// Drains `nextSample` into `input` and closes the writer at `end`. Both passes
/// below are a single track, so one reader and one writer input is all this has to
/// juggle. `nextSample` is the reader's output as it comes for the sound, and the
/// same output put on the frame grid (`FrameGrid`) for the picture.
func transfer(from nextSample: @escaping () -> CMSampleBuffer?, to input: AVAssetWriterInput,
              reader: AVAssetReader, writer: AVAssetWriter, end: CMTime) async throws {
    guard reader.startReading() else {
        throw reader.error ?? problem(1, "could not start reading")
    }
    guard writer.startWriting() else {
        throw writer.error ?? problem(2, "could not start writing")
    }

    // The first frame does not always sit at time zero, so the session opens on
    // it rather than on zero — the writer then measures the track from the frame
    // it was actually given. (On the grid it does: frame 0 is at zero.)
    guard let first = nextSample() else {
        throw reader.error ?? problem(3, "nothing to encode")
    }
    writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(first))

    let queue = DispatchQueue(label: "cz.rob.crosswords.appstore-conform")
    var pending: CMSampleBuffer? = first
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        // Everything below runs on `queue`, so the feeding and the watchdog take turns,
        // and the continuation is resumed exactly once.
        var done = false
        var lastProgress = Date()
        let watchdog = DispatchSource.makeTimerSource(queue: queue)
        func finish(_ error: Error?) {
            guard !done else { return }
            done = true
            watchdog.cancel()
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        }
        // A writer that fails while it isn't ready for more data never calls back
        // again, and media.sh would wait for it forever; so would one that just stops.
        watchdog.schedule(deadline: .now() + 1, repeating: 1)
        watchdog.setEventHandler {
            if writer.status == .failed {
                finish(writer.error ?? problem(7, "the writer failed"))
            } else if Date().timeIntervalSince(lastProgress) > 60 {
                finish(problem(8, "the encoder has taken nothing for a minute"))
            }
        }
        watchdog.resume()
        input.requestMediaDataWhenReady(on: queue) {
            while !done, input.isReadyForMoreMediaData {
                let next: CMSampleBuffer?
                if let pending {
                    next = pending
                } else {
                    next = nextSample()
                }
                pending = nil
                guard let sample = next else {
                    input.markAsFinished()
                    finish(reader.status == .failed ? reader.error ?? problem(4, "read failed") : nil)
                    return
                }
                if !input.append(sample) {
                    input.markAsFinished()
                    finish(writer.error ?? problem(5, "encode failed"))
                    return
                }
                lastProgress = Date()
            }
        }
    }
    // Closed explicitly at the source's end. A video composition output stops a
    // few frames short of it (its last frame comes without a duration), and a
    // session left open ends at that frame: an 18.8 s cut came out as 18.73 s.
    // The picture reaches the end on its own now (FrameGrid), so for it this
    // closes the last frame at its own 1/30 s rather than stretching it.
    writer.endSession(atSourceTime: end)
    await writer.finishWriting()
    if writer.status == .failed {
        throw writer.error ?? problem(6, "could not finish \(writer.outputURL.lastPathComponent)")
    }
}

/// Hands out the composition's frames on the 30 fps grid, `count` of them: frame
/// n is stamped n/30 s and lasts 1/30 s. The picture in it is the newest source
/// frame due by then (within half a frame), so a slot the source has no frame for
/// repeats the one before — at the end of the cut above all — and a source that
/// starts late opens on its first frame. Everything after `count` is left unread.
final class FrameGrid {
    let reader: AVAssetReader
    let output: AVAssetReaderOutput
    let count: Int64
    private let step = CMTime(value: 1, timescale: fps)
    private let slack = CMTime(value: 1, timescale: fps * 2)
    private var index: Int64 = 0
    private var held: CMSampleBuffer?
    private var upcoming: CMSampleBuffer?
    private var exhausted = false
    private(set) var repeated = 0
    private(set) var dropped = 0

    init(reader: AVAssetReader, output: AVAssetReaderOutput, count: Int64) {
        self.reader = reader
        self.output = output
        self.count = count
    }

    func next() -> CMSampleBuffer? {
        guard index < count else { return nil }
        let slot = CMTime(value: index, timescale: fps)
        var fresh = false
        while true {
            if upcoming == nil, !exhausted {
                upcoming = output.copyNextSampleBuffer()
                exhausted = upcoming == nil
                // A reader that failed has not run out, and its last frame must
                // not stand in for the rest: stop here, and transfer reports it.
                if exhausted, reader.status == .failed { return nil }
            }
            guard let candidate = upcoming,
                  CMSampleBufferGetPresentationTimeStamp(candidate) < slot + slack else { break }
            if fresh { dropped += 1 }
            held = candidate
            upcoming = nil
            fresh = true
        }
        if held == nil, let candidate = upcoming {
            held = candidate
            upcoming = nil
            fresh = true
        }
        guard let frame = held else { return nil }
        if !fresh { repeated += 1 }
        index += 1

        var timing = CMSampleTimingInfo(duration: step, presentationTimeStamp: slot,
                                        decodeTimeStamp: .invalid)
        var stamped: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: frame, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleBufferOut: &stamped) == noErr else { return nil }
        return stamped
    }
}

/// Re-encodes the picture to the target size and to H.264 High 4.0, scaled to
/// width and centred vertically, as exactly `frames` frames on the 30 fps grid.
/// (video.swift fills the frame instead, by the larger of the two
/// ratios.) The preview's aspect ratio is within a rounding error of the target,
/// so either way only a fraction of a row is lost, and for a cut made by
/// video.swift the scale here is exactly 1.
func encodeVideo(asset: AVAsset, track: AVAssetTrack, frames: Int64, to outURL: URL) async throws {
    let duration = try await asset.load(.duration)
    let natural = try await track.load(.naturalSize)
    let scale = targetSize.width / natural.width
    let ty = (targetSize.height - natural.height * scale) / 2

    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
    layer.setTransform(CGAffineTransform(scaleX: scale, y: scale)
        .concatenating(CGAffineTransform(translationX: 0, y: ty)), at: .zero)
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
    instruction.layerInstructions = [layer]

    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = targetSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: fps)
    videoComposition.instructions = [instruction]

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
        kCVPixelBufferPixelFormatTypeKey as String:
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ])
    output.videoComposition = videoComposition
    reader.add(output)

    try? FileManager.default.removeItem(at: outURL)
    let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(targetSize.width),
        AVVideoHeightKey: Int(targetSize.height),
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: videoBitRate,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264High40,
            // Every frame a keyframe. Two reasons, and the second is the load
            // bearing one: Connect seeks the file to build the poster frame and a
            // long GOP has bitten this pipeline before — and all-intra is what
            // turns the average bit rate above from a ceiling the encoder ignores
            // into the figure it actually delivers. See the note there.
            AVVideoMaxKeyFrameIntervalKey: 1,
            AVVideoExpectedSourceFrameRateKey: Int(fps),
        ],
        // Tag the colour explicitly; the simulator's own recording is Rec. 709
        // and an untagged file is left to the reader to guess at.
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
    ])
    input.expectsMediaDataInRealTime = false
    writer.add(input)

    let grid = FrameGrid(reader: reader, output: output, count: frames)
    try await transfer(from: grid.next, to: input, reader: reader, writer: writer,
                       end: CMTime(value: frames, timescale: fps))
    if grid.repeated > 0 || grid.dropped > 0 {
        print(String(format: "  on the 30 fps grid: %ld of %lld frames repeated, %ld dropped",
                     grid.repeated, frames, grid.dropped))
    }
}

/// Writes `seconds` of silent PCM — the fallback when no music is given. The
/// encoder needs samples to chew on and there is no way to ask for an empty
/// track. Note the warning above: a silent track is *not* enough for Connect.
func writeSilence(seconds: Double, to url: URL) throws {
    let file = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: audioChannels,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ])
    let chunk = AVAudioFrameCount(sampleRate)   // a second at a time
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                        frameCapacity: chunk) else {
        throw problem(6, "could not allocate a silence buffer")
    }
    if let data = buffer.floatChannelData {
        for channel in 0..<Int(buffer.format.channelCount) {
            memset(data[channel], 0, Int(chunk) * MemoryLayout<Float>.size)
        }
    }
    var remaining = AVAudioFrameCount((seconds * sampleRate).rounded(.up))
    while remaining > 0 {
        buffer.frameLength = min(chunk, remaining)
        try file.write(from: buffer)
        remaining -= buffer.frameLength
    }
}

/// Loops the music (or silence) up to `duration` and encodes it to AAC at the
/// rate Apple asks for. The reader handles the mixing and the rate conversion.
func encodeAudio(duration: CMTime, to outURL: URL) async throws {
    let sourceURL = musicURL ?? outURL.deletingLastPathComponent()
        .appendingPathComponent("silence.caf")
    if musicURL == nil {
        try writeSilence(seconds: duration.seconds, to: sourceURL)
    }

    let asset = AVURLAsset(url: sourceURL)
    guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
        throw problem(7, "no audio track in \(sourceURL.lastPathComponent)")
    }
    let sourceDuration = try await asset.load(.duration)
    guard sourceDuration > .zero else {
        throw problem(8, "\(sourceURL.lastPathComponent) is empty")
    }

    let composition = AVMutableComposition()
    guard let track = composition.addMutableTrack(
        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
        throw problem(9, "could not add an audio track")
    }
    var cursor = CMTime.zero
    while cursor < duration {
        let take = min(sourceDuration, duration - cursor)
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: take),
                                  of: sourceTrack, at: cursor)
        cursor = cursor + take
    }

    let parameters = AVMutableAudioMixInputParameters(track: track)
    parameters.setVolume(gain, at: .zero)
    if musicURL != nil {
        // Music that starts and stops at full volume reads as a glitch. The
        // fades are short enough not to eat into the gameplay.
        parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: gain,
                                 timeRange: CMTimeRange(start: .zero,
                                                        duration: time(fadeIn)))
        parameters.setVolumeRamp(fromStartVolume: gain, toEndVolume: 0,
                                 timeRange: CMTimeRange(start: duration - time(fadeOut),
                                                        duration: time(fadeOut)))
    }
    let mix = AVMutableAudioMix()
    mix.inputParameters = [parameters]

    let reader = try AVAssetReader(asset: composition)
    let output = AVAssetReaderAudioMixOutput(
        audioTracks: composition.tracks(withMediaType: .audio),
        audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: audioChannels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
    output.audioMix = mix
    reader.add(output)

    try? FileManager.default.removeItem(at: outURL)
    let writer = try AVAssetWriter(outputURL: outURL, fileType: .m4a)
    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: audioChannels,
        AVEncoderBitRateKey: audioBitRate,
    ])
    input.expectsMediaDataInRealTime = false
    writer.add(input)

    try await transfer(from: output.copyNextSampleBuffer, to: input, reader: reader,
                       writer: writer, end: duration)
    if musicURL == nil {
        try? FileManager.default.removeItem(at: sourceURL)
    }
}

/// What a file actually holds, measured rather than taken from the settings
/// above: the frame table sample by sample, the codec, profile and level as the
/// stream itself declares them, and the sound from its own format description.
struct Measured {
    var width = 0, height = 0
    var seconds = 0.0
    var frames = 0
    var offGrid = 0             // frames that do not last exactly 1/30 s
    var longest = 0.0
    var video = "no picture"
    var videoRate = 0.0
    var audio = "no sound"
    var audioRate = 0.0
    var bytes = 0

    var line: String {
        let rate = offGrid == 0
            ? "\(frames) frames at 30 fps"
            : String(format: "%ld frames, %ld of them not 1/30 s (the longest %.3fs)",
                     frames, offGrid, longest)
        return String(format: "%ld×%ld  %.2fs  %@  %@ %.1f Mbit/s  %@ %.0f kbit/s  %.1f MB",
                      width, height, seconds, rate, video, videoRate / 1_000_000,
                      audio, audioRate / 1000, Double(bytes) / 1_048_576)
    }
}

func fourCC(_ code: FourCharCode) -> String {
    String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .ascii) ?? "?"
}

func measure(_ url: URL) async throws -> Measured {
    var measured = Measured()
    let asset = AVURLAsset(url: url)
    measured.seconds = try await asset.load(.duration).seconds
    measured.bytes = (try FileManager.default.attributesOfItem(atPath: url.path)[.size]
                      as? Int) ?? 0

    if let track = try await asset.loadTracks(withMediaType: .video).first {
        let size = try await track.load(.naturalSize)
        measured.width = Int(size.width)
        measured.height = Int(size.height)
        measured.videoRate = Double(try await track.load(.estimatedDataRate))
        if let format = try await track.load(.formatDescriptions).first {
            let codec = CMFormatDescriptionGetMediaSubType(format)
            measured.video = codec == kCMVideoCodecType_H264 ? "H.264" : fourCC(codec)
            // Bytes 1 and 3 of the avcC record are the profile and the level.
            if let atoms = CMFormatDescriptionGetExtension(
                format, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
                as? [String: Any],
               let avcC = atoms["avcC"] as? Data, avcC.count > 3 {
                let profile = [66: "Baseline", 77: "Main", 100: "High"][Int(avcC[1])]
                    ?? "profile \(avcC[1])"
                measured.video += " \(profile) \(avcC[3] / 10).\(avcC[3] % 10)"
            }
        }

        // The samples as stored, nothing decoded: only their timing is wanted.
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? problem(15, "could not read back \(url.lastPathComponent)")
        }
        let frame = CMTime(value: 1, timescale: fps)
        while let buffer = output.copyNextSampleBuffer() {
            let count = CMSampleBufferGetNumSamples(buffer)
            guard count > 0 else { continue }
            // One entry per sample, or a single one when they are all alike.
            var entries = 0
            CMSampleBufferGetOutputSampleTimingInfoArray(
                buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &entries)
            var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(),
                                              count: max(entries, 1))
            CMSampleBufferGetOutputSampleTimingInfoArray(
                buffer, entryCount: timing.count, arrayToFill: &timing, entriesNeededOut: nil)
            for index in 0..<count {
                let duration = timing[min(index, timing.count - 1)].duration
                measured.frames += 1
                measured.longest = max(measured.longest, duration.seconds)
                if duration != frame { measured.offGrid += 1 }
            }
        }
        if reader.status == .failed {
            throw reader.error ?? problem(16, "could not read back \(url.lastPathComponent)")
        }
    }

    if let track = try await asset.loadTracks(withMediaType: .audio).first {
        measured.audioRate = Double(try await track.load(.estimatedDataRate))
        if let format = try await track.load(.formatDescriptions).first,
           let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
            let codec = description.mFormatID == kAudioFormatMPEG4AAC
                ? "AAC" : fourCC(description.mFormatID)
            let channels = [1: "mono", 2: "stereo"][Int(description.mChannelsPerFrame)]
                ?? "\(description.mChannelsPerFrame) channels"
            measured.audio = String(format: "%@ %g kHz %@",
                                    codec, description.mSampleRate / 1000, channels)
        }
    }
    return measured
}

let done = DispatchSemaphore(value: 0)

Task {
    do {
        let original = AVURLAsset(url: videoURL)
        guard let sourceVideo = try await original.loadTracks(withMediaType: .video).first else {
            throw problem(10, "no video track in \(videoURL.lastPathComponent)")
        }
        let duration = try await original.load(.duration)
        guard duration.seconds >= 15, duration.seconds <= 30 else {
            throw problem(11, String(format: "%.1fs is outside Connect's 15–30 s",
                                     duration.seconds))
        }

        // Work beside the file: replaceItemAt wants both on the same volume.
        let work = videoURL.deletingLastPathComponent()
            .appendingPathComponent(".appstore_conform-\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // The length in whole frames: the picture is exactly this many, and the
        // sound is made as long and then trimmed to the picture.
        let frames = Int64((duration.seconds * Double(fps)).rounded())
        let length = CMTime(value: frames, timescale: fps)

        let videoOnly = work.appendingPathComponent("video.mp4")
        let audioOnly = work.appendingPathComponent("audio.m4a")
        try await encodeVideo(asset: original, track: sourceVideo, frames: frames, to: videoOnly)
        try await encodeAudio(duration: length, to: audioOnly)

        // Put the two together. Passthrough copies both tracks as encoded, so
        // nothing above is undone here, and inserting from time zero is what
        // leaves the result without the offset edit list a composed export
        // would otherwise carry.
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoOnly)
        let audioAsset = AVURLAsset(url: audioOnly)
        guard let encodedVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let video = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw problem(12, "could not add the encoded picture")
        }
        let videoDuration = try await videoAsset.load(.duration)
        try video.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration),
                                  of: encodedVideo, at: .zero)

        guard let encodedAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let audio = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw problem(13, "could not add the encoded audio")
        }
        // AAC comes out in whole packets, a fraction of a second longer than
        // asked for. Trim it so the sound does not outlast the picture.
        let audioDuration = min(try await audioAsset.load(.duration), videoDuration)
        try audio.insertTimeRange(CMTimeRange(start: .zero, duration: audioDuration),
                                  of: encodedAudio, at: .zero)

        guard let export = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw problem(14, "could not create an export session")
        }
        // Moves the index to the front, so Connect can read the file as it
        // arrives instead of having to take all of it first.
        export.shouldOptimizeForNetworkUse = true
        let outURL = work.appendingPathComponent(videoURL.lastPathComponent)
        try await export.export(to: outURL, as: .mp4)
        _ = try FileManager.default.replaceItemAt(videoURL, withItemAt: outURL)

        // Report what the file ended up holding, not what was asked for above:
        // every figure on this line is read back from the written file.
        let result = try await measure(videoURL)
        print("→ \(videoURL.path)\n  \(result.line)  (" +
              (musicURL.map { "music: \($0.lastPathComponent)" } ?? "silent") + ")")
        // And the one promise this file makes that nothing else checks.
        guard result.frames == Int(frames), result.offGrid == 0 else {
            throw problem(17, "the preview should be \(frames) frames of 1/30 s each")
        }
        // And the sound, which Connect otherwise reports only a whole upload later:
        // without a music bed the track is AAC-encoded silence at a few kbit/s.
        guard result.audio.hasPrefix("AAC"), result.audio.hasSuffix("stereo"), result.audioRate >= 200_000 else {
            throw problem(18, String(format: "the sound is %@ at %.0f kbit/s; Connect wants stereo AAC at 256",
                                     result.audio, result.audioRate / 1000))
        }
    } catch {
        FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    done.signal()
}

done.wait()
