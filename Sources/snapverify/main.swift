import SnapCore
import CoreGraphics
import Foundation
import AppKit
import ImageIO
import AVFoundation

var failures = 0
@MainActor func check(_ cond: Bool, _ msg: String) {
    if cond { print("ok   - \(msg)") } else { failures += 1; print("FAIL - \(msg)") }
}

// MARK: Geometry
let r = selectionRect(from: CGPoint(x: 100, y: 80), to: CGPoint(x: 20, y: 10))
check(r == CGRect(x: 20, y: 10, width: 80, height: 70), "selectionRect normalizes reversed drag")

let sel = CaptureSelection(rect: CGRect(x: 0, y: 0, width: 100, height: 50), displayID: 1, scale: 2.0)
check(sel.pixelSize == CGSize(width: 200, height: 100), "pixelSize = points x scale")

// Region crop math: bottom-left points → top-left pixels.
// rect (20,30,100,50) on a 900pt-tall retina (2x) screen: maxY=80 → topY=820 → ×2.
let crop = pixelCropRect(selection: CGRect(x: 20, y: 30, width: 100, height: 50),
                         screenHeightPoints: 900, scale: 2)
check(crop == CGRect(x: 40, y: 1640, width: 200, height: 100),
      "pixelCropRect flips Y and scales (got \(crop))")
// A selection at the very top of the screen maps to y=0 in pixels.
let topCrop = pixelCropRect(selection: CGRect(x: 0, y: 850, width: 100, height: 50),
                            screenHeightPoints: 900, scale: 2)
check(topCrop.minY == 0, "selection at screen top crops from pixel y=0 (got \(topCrop.minY))")
check(sel.isValid, "non-empty selection is valid")
check(!CaptureSelection(rect: .zero, displayID: 1, scale: 2).isValid, "zero selection invalid")

// MARK: ImageOps
func renderSolid(width: Int, height: Int) -> CGImage? {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}
check(ImageOps.clampBlock(0) == 2, "block size floored to 2")
check(ImageOps.clampBlock(999) == 64, "block size capped at 64")
check(ImageOps.clampBlock(12) == 12, "block size in range unchanged")
check(ImageOps.fit(CGSize(width: 4000, height: 2000), maxEdge: 1000) == CGSize(width: 1000, height: 500),
      "fit scales longest edge to max")
check(ImageOps.fit(CGSize(width: 300, height: 200), maxEdge: 1000) == CGSize(width: 300, height: 200),
      "fit leaves already-small size")
if let fixture = renderSolid(width: 12, height: 8) {
    check(ImageOps.resized(fixture, width: 6, height: 4)?.width == 6, "resize changes pixel dimensions")
    let rotated = ImageOps.rotatedRight(fixture)
    check(rotated?.width == 8 && rotated?.height == 12, "rotate swaps width and height")
    check(ImageOps.flippedHorizontal(fixture)?.width == 12, "horizontal flip preserves dimensions")
    let filled = ImageOps.filling(fixture, rect: CGRect(x: 2, y: 2, width: 4, height: 3))
    check(filled?.width == 12 && filled?.height == 8, "smart-move fill preserves canvas dimensions")
}

// MARK: Redaction
check(Redaction.containsEmail("ping rahul@iamrraj.com now"), "detects email")
check(!Redaction.containsEmail("no address here"), "no false email")
check(Redaction.containsCardNumber("4242 4242 4242 4242"), "detects Luhn-valid card")
check(!Redaction.containsCardNumber("1234 5678 9012 3456"), "rejects non-Luhn digits")

// MARK: Annotation
var doc = AnnotationDocument()
let s1 = doc.add(.step, start: .zero, end: .zero)
let s2 = doc.add(.step, start: .zero, end: .zero)
check(s1.stepNumber == 1 && s2.stepNumber == 2, "step badges auto-increment")
let a1 = doc.add(.arrow, start: .zero, end: CGPoint(x: 10, y: 10))
check(a1.stepNumber == nil, "non-step has no step number")
check(Tool.allCases.contains(.smartMove), "smart move is available as an editor tool")
doc.remove(id: s1.id)
check(doc.stepCount == 1, "removal is non-destructive to others")
doc.update(id: s2.id) { $0.colorHex = "#00FF00" }
check(doc.items.first(where: { $0.id == s2.id })?.colorHex == "#00FF00", "update mutates in place")
let duplicate = doc.duplicate(id: a1.id)
check(duplicate != nil && duplicate!.id != a1.id, "duplicate creates a new annotation")
if let duplicate { doc.sendToBack(id: duplicate.id); check(doc.items.first?.id == duplicate.id, "send to back changes layer order") }

// Step numbering styles
check(StepStyle.number.label(for: 3) == "3", "numeric step label")
check(StepStyle.upper.label(for: 1) == "A", "upper letter A")
check(StepStyle.upper.label(for: 26) == "Z", "upper letter Z")
check(StepStyle.upper.label(for: 27) == "AA", "upper letter wraps to AA")
check(StepStyle.lower.label(for: 2) == "b", "lower letter b")

// MARK: OCR (renders text, recognizes it; skips gracefully if Vision unavailable)
func renderText(_ s: String) -> CGImage? {
    let size = NSSize(width: 320, height: 120)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 56),
        .foregroundColor: NSColor.black,
    ]
    (s as NSString).draw(at: NSPoint(x: 20, y: 30), withAttributes: attrs)
    image.unlockFocus()
    var rect = NSRect(origin: .zero, size: size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}

// MARK: Library
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
let fixedDate = cal.date(from: DateComponents(year: 2026, month: 7, day: 4,
                                              hour: 14, minute: 30, second: 5))!
check(CaptureLibrary.relativeFolder(for: fixedDate, calendar: cal) == "2026/07",
      "library groups by YYYY/MM")
let stem = CaptureLibrary.stem(for: fixedDate, suffix: "a1b2", calendar: cal)
check(stem.hasPrefix("2026-07-04_") && stem.hasSuffix("_a1b2"), "stem is sortable timestamp (got \(stem))")
let path = CaptureLibrary.relativePath(for: fixedDate, suffix: "a1b2", ext: "png", calendar: cal)
check(path.hasPrefix("2026/07/") && path.hasSuffix(".png"), "relativePath = folder/stem.ext (got \(path))")
let rec = CaptureRecord(id: "x", kind: .image, fileName: path, createdAt: fixedDate,
                        width: 100, height: 50, ocrText: "Invoice total 42.00", title: "Receipt")
check(CaptureLibrary.matches(rec, query: "invoice"), "search finds OCR text")
check(CaptureLibrary.matches(rec, query: "receipt"), "search finds title")
check(!CaptureLibrary.matches(rec, query: "banana"), "search rejects absent term")
check(CaptureLibrary.matches(rec, query: ""), "empty query matches all")

if let img = renderText("HELLO") {
    do {
        let lines = try await OCR.recognize(img)
        let joined = lines.joined(separator: " ").uppercased()
        check(joined.contains("HELLO"), "OCR reads rendered text (got: \(lines))")
    } catch {
        print("skip - OCR unavailable in this environment: \(error)")
    }
} else {
    print("skip - could not render OCR fixture")
}

// MARK: Meeting analysis
let meetingLines = [
    TranscriptLine(speaker: "You", text: "Thanks everyone for joining. Let's ship the release on Friday.", start: 1),
    TranscriptLine(speaker: "Participants", text: "Sounds good. I'll handle the QA testing before then.", start: 5),
    TranscriptLine(speaker: "Participants", text: "We agreed the deadline is Friday at 5pm.", start: 9),
    TranscriptLine(speaker: "You", text: "Can you also write the release notes?", start: 13),
    TranscriptLine(speaker: "Participants", text: "Yeah.", start: 16),   // fragment, should be dropped
]
let notes = MeetingAnalyzer.analyze(meetingLines)
check(notes.tasks.contains { $0.text.lowercased().contains("qa testing") },
      "extracts 'I'll handle QA' as a task")
check(notes.tasks.contains { $0.owner == "Participants" && $0.text.lowercased().contains("qa") },
      "owner of 'I'll handle QA' is the speaker (Participants)")
check(notes.tasks.contains { $0.text.lowercased().contains("release notes") && $0.owner == "Participants" },
      "'can you write release notes' delegates to Participants")
check(notes.keyPoints.contains { $0.lowercased().contains("deadline is friday") },
      "extracts the deadline as a key point")
check(!notes.summary.isEmpty, "summary is non-empty")
check(!notes.tasks.contains { $0.text.lowercased() == "yeah." },
      "one-word fragments are not tasks")
check(MeetingAnalyzer.splitSentences("One. Two! Three?").count == 3, "splits three sentences")

// MARK: Scrolling capture stitcher
func grad(_ w: Int, _ h: Int) -> CGImage? {   // monotonic, distinct rows, no modular wrap
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                              bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
    for row in 0..<h {
        ctx.setFillColor(gray: CGFloat(row) / CGFloat(max(1, h - 1)), alpha: 1)
        ctx.fill(CGRect(x: 0, y: h - 1 - row, width: w, height: 1))   // row 0 = top
    }
    return ctx.makeImage()
}
if let source = grad(40, 250) {
    // Simulate scrolling: 150-tall viewport moving down 50px at a time.
    let offsets = [0, 50, 100]
    let frames = offsets.compactMap { source.cropping(to: CGRect(x: 0, y: $0, width: 40, height: 150)) }
    check(frames.count == 3, "built 3 scroll frames")
    if let stitched = ScrollStitcher.stitch(frames) {
        check(stitched.width == 40, "stitched keeps width")
        check(abs(stitched.height - 250) <= 10, "stitched recovers full height (got \(stitched.height))")
    } else {
        check(false, "stitch produced an image")
    }
    // Two identical frames → no new rows appended (overlap ≈ full height).
    if let f = frames.first {
        let same = ScrollStitcher.stitch([f, f])
        check(same != nil && abs(same!.height - f.height) <= 6, "identical frames don't duplicate")
    }
}

// MARK: Kanban task board
var task = TaskItem(title: "Ship release", status: .todo)
check(task.history.isEmpty, "new task has no history")
task = TaskBoard.move(task, to: .inProgress)
check(task.status == .inProgress, "move changes status")
check(task.history.count == 1 && task.history[0].text.lowercased().contains("in progress"), "move logs history")
let unchanged = TaskBoard.move(task, to: .inProgress)
check(unchanged.history.count == 1, "moving to same status is a no-op")
var overdue = TaskItem(title: "Late", status: .todo, due: Date(timeIntervalSince1970: 0))
check(overdue.isOverdue, "past-due unfinished task is overdue")
overdue = TaskBoard.move(overdue, to: .done)
check(!overdue.isOverdue, "done task is never overdue")

// MARK: Notes
check(NoteText.wordCount("hello world  foo\nbar") == 4, "word count splits on whitespace/newlines")
check(NoteText.inferTitle("# My Title\nbody") == "My Title", "infers title from first heading")
check(NoteText.excerpt("# Heading\n\nThe **body** text here.").contains("body text here"), "excerpt strips markdown & heading")
let note = Note(title: "T", body: String(repeating: "word ", count: 400))
check(note.readingMinutes == 2, "reading time ~200wpm (got \(note.readingMinutes))")

// MARK: Layer placement
let canvas = CGSize(width: 1000, height: 800)
let fitted = LayerPlacement.fittedSize(CGSize(width: 2000, height: 400), canvas: canvas)
check(abs(fitted.width - 550) < 0.001 && abs(fitted.height - 110) < 0.001,
      "large overlay scales to 55% of canvas, keeping aspect (got \(fitted))")
check(LayerPlacement.fittedSize(CGSize(width: 100, height: 50), canvas: canvas) == CGSize(width: 100, height: 50),
      "small overlay is never upscaled")
check(LayerPlacement.fittedSize(.zero, canvas: canvas) == CGSize(width: 24, height: 24),
      "zero-size image falls back to minimum side")
check(LayerPlacement.fittedSize(CGSize(width: 5000, height: 2), canvas: canvas).height == 24,
      "sliver image keeps a grabbable minimum height")

let centered = LayerPlacement.rect(size: CGSize(width: 200, height: 100), centeredAt: CGPoint(x: 500, y: 400), in: canvas)
check(centered == CGRect(x: 400, y: 350, width: 200, height: 100), "rect centres on point")
let edgeDrop = LayerPlacement.rect(size: CGSize(width: 200, height: 100), centeredAt: CGPoint(x: 990, y: -40), in: canvas)
check(edgeDrop == CGRect(x: 800, y: 0, width: 200, height: 100), "drop near edge is pulled fully onto canvas (got \(edgeDrop))")
let oversized = LayerPlacement.rect(size: CGSize(width: 1200, height: 100), centeredAt: CGPoint(x: 500, y: 400), in: canvas)
check(oversized.minX == -100, "wider-than-canvas overlay stays centred instead of clamping")

let size = CGSize(width: 200, height: 100)
let firstRect = LayerPlacement.cascadedRect(size: size, in: canvas, existing: [])
check(firstRect == centered, "first overlay goes to the canvas centre")
let secondRect = LayerPlacement.cascadedRect(size: size, in: canvas, existing: [firstRect])
check(secondRect.minX > firstRect.minX && secondRect.minY > firstRect.minY && secondRect.intersects(firstRect),
      "second overlay cascades down-right and still overlaps the first (got \(secondRect))")
let thirdRect = LayerPlacement.cascadedRect(size: size, in: canvas, existing: [firstRect, secondRect])
check(thirdRect.minX > secondRect.minX, "third overlay cascades past the second")
let movedAway = CGRect(x: 0, y: 0, width: 200, height: 100)
check(LayerPlacement.cascadedRect(size: size, in: canvas, existing: [movedAway]) == centered,
      "centre is reused once the earlier overlay was dragged away")
let full = CGSize(width: 1000, height: 800)
check(LayerPlacement.cascadedRect(size: full, in: canvas, existing: [CGRect(origin: .zero, size: full)]).origin == .zero,
      "canvas-sized overlay with no room to cascade falls back to centre without looping")

var stack = [1, 2, 3]
check(LayerPlacement.bringToFront(&stack, index: 0) && stack == [2, 3, 1], "bringToFront moves item to the end")
check(!LayerPlacement.bringToFront(&stack, index: 2) && stack == [2, 3, 1], "already-front item reports no change")
check(!LayerPlacement.bringToFront(&stack, index: 7), "out-of-range index is ignored")
var empty: [Int] = []
check(!LayerPlacement.bringToFront(&empty, index: 0), "empty stack is a no-op")

// MARK: Audio mixdown
/// Writes a 1-second H.264 clip with `audioTracks` separate AAC tracks (sine tones).
func makeClip(audioTracks: Int) async throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapverify-\(UUID().uuidString).mp4")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)
    writer.add(video)
    let audioSettings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                                        AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000]
    let audios = (0..<audioTracks).map { _ in AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings) }
    audios.forEach { writer.add($0) }
    writer.startWriting(); writer.startSession(atSourceTime: .zero)

    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
    for frame in 0..<30 {
        while !video.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
        if let pixelBuffer { adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)) }
    }
    var format = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
                                             mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                             mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                                             mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
    var formatDescription: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &format, layoutSize: 0, layout: nil,
                                   magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDescription)
    for (trackIndex, input) in audios.enumerated() {
        let chunk = 4410
        for start in stride(from: 0, to: 44_100, by: chunk) {
            let frequency = Double(trackIndex + 1) * 440.0
            var samples = (0..<chunk).map { i -> Int16 in
                let phase: Double = Double(start + i) * frequency * 2.0 * Double.pi / 44_100.0
                return Int16(8000.0 * sin(phase))
            }
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: chunk * 2,
                                               blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                               dataLength: chunk * 2, flags: 0, blockBufferOut: &block)
            guard let block, let formatDescription else { continue }
            samples.withUnsafeMutableBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                                                               offsetIntoDestination: 0, dataLength: chunk * 2) }
            var sampleBuffer: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block,
                                                                 formatDescription: formatDescription, sampleCount: chunk,
                                                                 presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: 44_100),
                                                                 packetDescriptions: nil, sampleBufferOut: &sampleBuffer)
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            if let sampleBuffer { input.append(sampleBuffer) }
        }
    }
    video.markAsFinished(); audios.forEach { $0.markAsFinished() }
    await writer.finishWriting()
    return url
}

/// What a mixed clip contains, as plain values (AVFoundation objects stay inside this function).
struct ClipSummary: Sendable { let audioTracks: Int; let videoTracks: Int; let seconds: Double; let pcm: [Int16] }

func summarize(_ url: URL) async throws -> ClipSummary {
    let asset = AVURLAsset(url: url)
    return ClipSummary(audioTracks: try await asset.loadTracks(withMediaType: .audio).count,
                       videoTracks: try await asset.loadTracks(withMediaType: .video).count,
                       seconds: try await asset.load(.duration).seconds,
                       pcm: try await decodePCM(asset))
}

/// Decode an asset's first audio track to mono Int16 PCM.
func decodePCM(_ asset: AVAsset) async throws -> [Int16] {
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: 44_100])
    reader.add(output); reader.startReading()
    var samples: [Int16] = []
    while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
        var chunk = [Int16](repeating: 0, count: CMBlockBufferGetDataLength(block) / 2)
        chunk.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!) }
        samples += chunk
    }
    return samples
}

/// Goertzel power of one frequency in a PCM buffer.
func tonePower(_ samples: [Int16], frequency: Double, sampleRate: Double = 44_100) -> Double {
    let coefficient = 2 * cos(2 * Double.pi * frequency / sampleRate)
    var previous = 0.0, previous2 = 0.0
    for sample in samples {
        let current = Double(sample) + coefficient * previous - previous2
        previous2 = previous; previous = current
    }
    return previous2 * previous2 + previous * previous - coefficient * previous * previous2
}

do {
    let twoTrack = try await makeClip(audioTracks: 2)
    check(try await AudioMixdown.audioTrackCount(of: twoTrack) == 2, "fixture has two audio tracks")
    let mixed = try await AudioMixdown.mixInPlace(twoTrack)
    let after = try await summarize(twoTrack)
    check(mixed, "two-track clip is mixed")
    check(after.audioTracks == 1, "mixed clip has a single audio track")
    check(after.videoTracks == 1, "video track survives the mixdown")
    check(abs(after.seconds - 1) < 0.15, "duration preserved after mixdown (got \(after.seconds)s)")
    let pcm = after.pcm
    let control = tonePower(pcm, frequency: 660)
    check(tonePower(pcm, frequency: 440) > control * 50, "mixed track contains the first source's tone")
    check(tonePower(pcm, frequency: 880) > control * 50, "mixed track contains the second source's tone")

    let oneTrack = try await makeClip(audioTracks: 1)
    let before = try FileManager.default.attributesOfItem(atPath: oneTrack.path)[.modificationDate] as? Date
    check(!(try await AudioMixdown.mixInPlace(oneTrack)), "single-track clip is left alone")
    let unchanged = try FileManager.default.attributesOfItem(atPath: oneTrack.path)[.modificationDate] as? Date
    check(before == unchanged, "single-track file is not rewritten")

    let silent = try await makeClip(audioTracks: 0)
    check(!(try await AudioMixdown.mixInPlace(silent)), "video without audio is left alone")
    [twoTrack, oneTrack, silent].forEach { try? FileManager.default.removeItem(at: $0) }
} catch {
    check(false, "audio mixdown threw: \(error)")
}

// MARK: Coalescing writer
final class ErrorLog: @unchecked Sendable {
    private let lock = NSLock(); private var urls: [URL] = []
    func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return urls.count }
}
let writerDir = FileManager.default.temporaryDirectory.appendingPathComponent("snapverify-writer-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: writerDir, withIntermediateDirectories: true)
let errors = ErrorLog()
let writer = CoalescingWriter(delay: 0.1) { url, _ in errors.add(url) }
let indexFile = writerDir.appendingPathComponent("index.json")
for value in 1...100 { writer.schedule(indexFile) { Data("\(value)".utf8) } }
try? await Task.sleep(nanoseconds: 400_000_000)
check(writer.writeCount == 1, "100 rapid saves coalesce into one write (got \(writer.writeCount))")
check((try? String(contentsOf: indexFile, encoding: .utf8)) == "100", "coalesced write keeps the latest value")

let tasksFile = writerDir.appendingPathComponent("tasks.json")
writer.schedule(indexFile) { Data("a".utf8) }
writer.schedule(tasksFile) { Data("b".utf8) }
writer.flush()
check(writer.writeCount == 3, "flush writes every pending file immediately (got \(writer.writeCount))")
check((try? String(contentsOf: tasksFile, encoding: .utf8)) == "b", "separate files are written independently")
writer.flush()
check(writer.writeCount == 3, "flush with nothing pending writes nothing")

let missing = writerDir.appendingPathComponent("no-such-dir/x.json")
writer.schedule(missing) { Data("x".utf8) }
writer.flush()
check(errors.count == 1, "failed write is reported, not swallowed")
struct EncodeFailure: Error {}
writer.schedule(indexFile) { throw EncodeFailure() }
writer.flush()
check(errors.count == 2 && (try? String(contentsOf: indexFile, encoding: .utf8)) == "a",
      "encode failure is reported and leaves the previous file intact")
try? FileManager.default.removeItem(at: writerDir)

// MARK: Preferences
enum Flavor: String { case plain, fancy }
if let suite = UserDefaults(suiteName: "snapverify.\(UUID().uuidString)") {
    check(Preference.value("missing", default: true, in: suite), "missing bool falls back to default")
    Preference.set(false, for: "mic", in: suite)
    check(!Preference.value("mic", default: true, in: suite), "stored bool is read back")
    Preference.set(5, for: "delay", in: suite)
    check(Preference.value("delay", default: 0, in: suite) == 5, "stored int is read back")
    check(Preference.value("delay", default: "x", in: suite) == "x", "wrong stored type falls back to default")
    Preference.set(["de-DE"], for: "langs", in: suite)
    check(Preference.value("langs", default: ["en-US"], in: suite) == ["de-DE"], "stored string array is read back")
    Preference.set(Flavor.fancy, for: "flavor", in: suite)
    check(Preference.value("flavor", default: Flavor.plain, in: suite) == .fancy, "stored enum is read back")
    suite.set("removed-case", forKey: "flavor")
    check(Preference.value("flavor", default: Flavor.plain, in: suite) == .plain, "unknown enum raw value falls back")
}

// MARK: Annotation editing
var editDoc = AnnotationDocument()
let arrow = editDoc.add(.arrow, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 40), colorHex: "#FF0000", thickness: 4)
editDoc.translate(id: arrow.id, dx: 1, dy: -10)
check(editDoc.items[0].start == CGPoint(x: 11, y: 0) && editDoc.items[0].end == CGPoint(x: 51, y: 30), "translate moves both endpoints")
editDoc.translate(id: 999, dx: 5, dy: 5)
check(editDoc.items[0].start == CGPoint(x: 11, y: 0), "translate of unknown id is a no-op")

var blue = AnnotationStyle(of: editDoc.items[0]); blue.colorHex = "#0000FF"; blue.thickness = 9
editDoc.restyle(id: arrow.id, to: blue)
check(editDoc.items[0].colorHex == "#0000FF" && editDoc.items[0].thickness == 9, "restyle applies colour and thickness")
check(editDoc.items[0].start == CGPoint(x: 11, y: 0), "restyle keeps geometry")
var ghost = blue; ghost.opacity = 0; ghost.thickness = 0
editDoc.restyle(id: arrow.id, to: ghost)
check(editDoc.items[0].opacity == 0.05 && editDoc.items[0].thickness == 0.5, "restyle clamps opacity and thickness so objects stay selectable")
check(AnnotationStyle(of: editDoc.items[0]).colorHex == "#0000FF", "style round-trips from an annotation")

let stroke = editDoc.addStroke([CGPoint(x: 5, y: 9), CGPoint(x: 20, y: 2), CGPoint(x: 12, y: 30)], style: AnnotationStyle(colorHex: "#00FF00"))
check(stroke?.points.count == 3 && editDoc.items.count == 2, "a pen stroke is one annotation with all its points")
check(stroke?.start == CGPoint(x: 5, y: 2) && stroke?.end == CGPoint(x: 20, y: 30), "stroke bounds span its points")
check(editDoc.addStroke([CGPoint(x: 1, y: 1)], style: AnnotationStyle()) == nil, "single-point stroke is rejected")
check(editDoc.addStroke([], style: AnnotationStyle()) == nil, "empty stroke is rejected")
if let stroke {
    editDoc.translate(id: stroke.id, dx: 10, dy: 10)
    check(editDoc.items[1].points.first == CGPoint(x: 15, y: 19), "translating a stroke moves its points")
}

let copied = editDoc.items[0]
editDoc.remove(id: copied.id)
let pasted = editDoc.insertCopy(of: copied)
check(pasted.id != copied.id && pasted.start == CGPoint(x: copied.start.x + 16, y: copied.start.y + 16),
      "paste after cut inserts an offset copy with a fresh id")
var stepDoc = AnnotationDocument()
let step1 = stepDoc.add(.step, start: .zero, end: .zero)
let step2 = stepDoc.insertCopy(of: step1)
check(step2.stepNumber == 2, "pasted step takes the next number")
check(stepDoc.duplicate(id: 12345) == nil, "duplicate of unknown id returns nil")

var rotateDoc = AnnotationDocument()
_ = rotateDoc.addStroke([CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)], style: AnnotationStyle())
rotateDoc.transformAll { CGPoint(x: -$0.y, y: $0.x) }
check(rotateDoc.items[0].points == [CGPoint(x: -2, y: 1), CGPoint(x: -4, y: 3)], "transformAll maps stroke points too")

if let encoded = try? JSONEncoder().encode(editDoc),
   var decoded = try? JSONDecoder().decode(AnnotationDocument.self, from: encoded) {
    check(decoded.items == editDoc.items, "annotation document round-trips through JSON")
    let next = decoded.add(.rect, start: .zero, end: CGPoint(x: 1, y: 1))
    check(!editDoc.items.map(\.id).contains(next.id), "decoded document keeps issuing unique ids")
} else {
    check(false, "annotation document encodes and decodes")
}

// MARK: Annotation handles
let handleArrow = Annotation(id: 1, tool: .arrow, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 100, y: 50))
check(AnnotationHandle.handles(for: handleArrow).map(\.0) == [.start, .end], "arrow exposes start and end handles")
check(AnnotationHandle.hit(CGPoint(x: 98, y: 52), on: handleArrow, tolerance: 6) == .end, "grabbing near the tip picks the end handle")
check(AnnotationHandle.hit(CGPoint(x: 55, y: 30), on: handleArrow, tolerance: 6) == nil, "the middle of an arrow is not a handle")
check(AnnotationHandle.end.dragged(handleArrow, to: CGPoint(x: 200, y: 0)).end == CGPoint(x: 200, y: 0)
      && AnnotationHandle.end.dragged(handleArrow, to: CGPoint(x: 200, y: 0)).start == handleArrow.start,
      "dragging the end handle leaves the start in place")

let box = Annotation(id: 2, tool: .rect, start: CGPoint(x: 50, y: 40), end: CGPoint(x: 10, y: 10))
check(AnnotationHandle.handles(for: box).count == 4, "box shapes expose four corners")
check(AnnotationHandle.hit(CGPoint(x: 11, y: 11), on: box, tolerance: 4) == .topLeft, "corners are found even for a reversed drag")
let grown = AnnotationHandle.bottomRight.dragged(box, to: CGPoint(x: 80, y: 90))
check(selectionRect(from: grown.start, to: grown.end) == CGRect(x: 10, y: 10, width: 70, height: 80),
      "dragging bottom-right resizes against the top-left corner")
let flipped = AnnotationHandle.topLeft.dragged(box, to: CGPoint(x: 70, y: 60))
check(selectionRect(from: flipped.start, to: flipped.end) == CGRect(x: 50, y: 40, width: 20, height: 20),
      "dragging a corner past its opposite flips the box")
let tiny = Annotation(id: 3, tool: .ellipse, start: CGPoint(x: 5, y: 5), end: CGPoint(x: 7, y: 7))
check(AnnotationHandle.hit(CGPoint(x: 7, y: 7), on: tiny, tolerance: 10) == .bottomRight, "overlapping handles pick the nearest")
for tool in [Tool.text, .step, .stamp, .pen] {
    check(AnnotationHandle.handles(for: Annotation(id: 9, tool: tool, start: .zero, end: .zero)).isEmpty,
          "\(tool.rawValue) has no resize handles")
}

// MARK: Editor project files
do {
    let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("snapverify-project-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    let capture = projectRoot.appendingPathComponent("2026-10-13_capture.png")
    let folder = EditorProject.folder(for: capture)
    check(folder.lastPathComponent == "2026-10-13_capture.snappilot", "project folder sits next to the capture")
    check(try EditorProject.load(from: folder) == nil, "a capture without a project loads as nil")

    var projectDoc = AnnotationDocument()
    projectDoc.add(.arrow, start: CGPoint(x: 1, y: 2), end: CGPoint(x: 30, y: 40), colorHex: "#00FF00")
    let diskCallout = projectDoc.add(.callout, start: CGPoint(x: 2, y: 3), end: CGPoint(x: 15, y: 8), text: "Save\nnow")
    projectDoc.update(id: diskCallout.id) { $0 = CalloutGeometry.create($0, target: CGPoint(x: 400, y: 6)) }
    _ = projectDoc.addStroke([CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5)], style: AnnotationStyle())
    let layerInfo = EditorProject.Layer(id: 7, rect: CGRect(x: 3, y: 4, width: 6, height: 4), opacity: 0.5, name: "Logo")
    let project = EditorProject(doc: projectDoc, layers: [layerInfo], framed: true)
    if let base = renderSolid(width: 20, height: 10), let layerImage = renderSolid(width: 6, height: 4) {
        try EditorProject.save(project, base: base, layerImages: [7: layerImage], to: folder)
        let loaded = try EditorProject.load(from: folder)
        check(loaded?.project == project, "project round-trips annotations, layers and frame flag")
        check(loaded?.base.width == 20 && loaded?.base.height == 10, "unannotated base image is restored")
        check(loaded?.layerImages[7]?.width == 6, "layer image is restored")

        var edited = project; edited.framed = false
        try EditorProject.save(edited, base: base, layerImages: [7: layerImage], to: folder)
        check(try EditorProject.load(from: folder)?.project.framed == false, "saving again replaces the previous project")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: projectRoot.path).filter { $0.hasPrefix(".") }
        check(leftovers.isEmpty, "no staging folders are left behind")

        try FileManager.default.removeItem(at: folder.appendingPathComponent("layer-7.png"))
        do { _ = try EditorProject.load(from: folder); check(false, "missing layer image should fail") }
        catch { check((error as? EditorProject.Failure) == .unreadable("layer-7.png"), "missing layer image is reported by name") }

        var future = project; future.version = 99
        try JSONEncoder().encode(future).write(to: folder.appendingPathComponent("project.json"))
        do { _ = try EditorProject.load(from: folder); check(false, "newer project version should fail") }
        catch { check((error as? EditorProject.Failure) == .unsupportedVersion(99), "a newer project version is refused, not misread") }
    }
    try? FileManager.default.removeItem(at: projectRoot)
} catch {
    check(false, "editor project threw: \(error)")
}

// MARK: Snap guides
let snapCanvas = CGSize(width: 1000, height: 600)
let nearCentre = SnapGuides.snap(CGRect(x: 446, y: 200, width: 100, height: 50), to: [], canvas: snapCanvas, threshold: 6)
check(nearCentre.rect.midX == 500, "rect snaps its centre to the canvas centre line (got \(nearCentre.rect.midX))")
check(nearCentre.guides.contains { $0.axis == .vertical && $0.position == 500 }, "centre snap reports a vertical guide")
check(!nearCentre.guides.contains { $0.axis == .horizontal }, "an axis that didn't snap draws no guide")

let farAway = SnapGuides.snap(CGRect(x: 300, y: 200, width: 100, height: 50), to: [], canvas: snapCanvas, threshold: 6)
check(farAway.rect == CGRect(x: 300, y: 200, width: 100, height: 50) && farAway.guides.isEmpty, "nothing within threshold leaves the rect alone")

let neighbour = CGRect(x: 600, y: 100, width: 200, height: 80)
let alignedTop = SnapGuides.snap(CGRect(x: 100, y: 103, width: 120, height: 60), to: [neighbour], canvas: snapCanvas, threshold: 6)
check(alignedTop.rect.minY == 100, "top edge snaps to a neighbour's top edge")
if let guide = alignedTop.guides.first(where: { $0.axis == .horizontal && $0.position == 100 }) {
    check(guide.from == 100 && guide.to == 800, "guide spans from the moving rect to the neighbour (got \(guide.from)…\(guide.to))")
} else { check(false, "neighbour alignment reports a horizontal guide") }

let edge = SnapGuides.snap(CGRect(x: 3, y: 596 - 50, width: 80, height: 50), to: [], canvas: snapCanvas, threshold: 6)
check(edge.rect.minX == 0 && edge.rect.maxY == 600, "rect snaps to canvas left and bottom edges together")
let closest = SnapGuides.snap(CGRect(x: 0, y: 0, width: 10, height: 10), to: [CGRect(x: 14, y: 300, width: 5, height: 5), CGRect(x: 12, y: 400, width: 5, height: 5)],
                              canvas: CGSize(width: 2000, height: 2000), threshold: 6)
check(closest.rect.minX == 0, "an exact match beats a nearby candidate")
let zeroThreshold = SnapGuides.snap(CGRect(x: 1, y: 1, width: 10, height: 10), to: [], canvas: snapCanvas, threshold: 0)
check(zeroThreshold.rect.origin == CGPoint(x: 1, y: 1), "zero threshold disables snapping")

// MARK: Saved styles and restyle-all
var saved = SavedStyles()
let red = AnnotationStyle(colorHex: "#FF0000"), green = AnnotationStyle(colorHex: "#00FF00")
check(saved.styles(for: .arrow).isEmpty, "no saved styles to begin with")
saved.add(red, for: .arrow); saved.add(green, for: .arrow)
check(saved.styles(for: .arrow) == [green, red], "newest saved style comes first")
check(saved.styles(for: .rect).isEmpty, "styles are kept per tool")
saved.add(red, for: .arrow)
check(saved.styles(for: .arrow) == [red, green], "re-saving a style moves it to the front without duplicating")
for i in 0..<20 { saved.add(AnnotationStyle(colorHex: "#0000\(String(format: "%02d", i))"), for: .arrow) }
check(saved.styles(for: .arrow).count == SavedStyles.limitPerTool, "saved styles are capped per tool")
saved.remove(saved.styles(for: .arrow)[0], for: .arrow)
check(saved.styles(for: .arrow).count == SavedStyles.limitPerTool - 1, "a saved style can be removed")
if let data = try? JSONEncoder().encode(saved), let back = try? JSONDecoder().decode(SavedStyles.self, from: data) {
    check(back == saved, "saved styles round-trip through JSON")
} else { check(false, "saved styles encode") }

var typeDoc = AnnotationDocument()
typeDoc.add(.arrow, start: .zero, end: CGPoint(x: 5, y: 5))
typeDoc.add(.arrow, start: .zero, end: CGPoint(x: 9, y: 9), colorHex: "#00FF00")
typeDoc.add(.rect, start: .zero, end: CGPoint(x: 9, y: 9))
check(typeDoc.restyleAll(of: .arrow, to: green) == 1, "restyle-all counts only the annotations that changed")
check(typeDoc.items.filter { $0.tool == .arrow }.allSatisfy { $0.colorHex == "#00FF00" }, "every arrow gets the style")
check(typeDoc.items.first { $0.tool == .rect }?.colorHex == "#FF3B30", "other tools are untouched")
check(typeDoc.restyleAll(of: .step, to: green) == 0, "restyle-all with no matches changes nothing")

// MARK: Canvas expansion
let base100 = CGSize(width: 100, height: 80)
check(LayerPlacement.expansion(canvas: base100, fitting: [CGRect(x: 10, y: 10, width: 20, height: 20)]) == nil,
      "content inside the canvas needs no expansion")
check(LayerPlacement.expansion(canvas: base100, fitting: []) == nil, "no layers needs no expansion")
if let grow = LayerPlacement.expansion(canvas: base100, fitting: [CGRect(x: 90, y: 10, width: 40, height: 20)], padding: 10) {
    check(grow.size == CGSize(width: 140, height: 80) && grow.offset == CGVector(dx: 0, dy: 0),
          "overflow on the right grows width only, plus padding (got \(grow))")
} else { check(false, "right overflow expands") }
if let grow = LayerPlacement.expansion(canvas: base100, fitting: [CGRect(x: -30, y: -5, width: 20, height: 20)]) {
    check(grow.size == CGSize(width: 130, height: 85) && grow.offset == CGVector(dx: 30, dy: 5),
          "overflow left/top grows and shifts existing content (got \(grow))")
} else { check(false, "left/top overflow expands") }
let beside = LayerPlacement.besideRect(size: CGSize(width: 50, height: 120), canvas: base100, gap: 16)
check(beside == CGRect(x: 116, y: 0, width: 50, height: 120), "combined image sits to the right, top-aligned")
if let grow = LayerPlacement.expansion(canvas: base100, fitting: [beside]) {
    check(grow.size == CGSize(width: 166, height: 120), "canvas grows to hold the combined image")
}
if let small = renderSolid(width: 10, height: 10), let big = ImageOps.expanded(small, to: CGSize(width: 30, height: 20), offset: CGVector(dx: 5, dy: 4)) {
    check(big.width == 30 && big.height == 20, "expanded canvas has the new size")
} else { check(false, "expand canvas renders") }
if let small = renderSolid(width: 10, height: 10) {
    check(ImageOps.expanded(small, to: CGSize(width: 5, height: 5), offset: .zero) == nil, "shrinking via expand is refused")
}

// MARK: Rounded corners
func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
    var pixel = [UInt8](repeating: 0, count: 4)
    guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return 0 }
    ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return pixel[3]
}
if let square = renderSolid(width: 40, height: 40), let rounded = ImageOps.roundedCorners(square, radius: 12) {
    check(alpha(rounded, x: 0, y: 0) == 0, "rounded corner pixel is transparent")
    check(alpha(rounded, x: 20, y: 20) == 255, "centre stays opaque")
    check(alpha(rounded, x: 20, y: 0) == 255, "edge midpoint stays opaque")
    check(ImageOps.roundedCorners(square, radius: 0).map { alpha($0, x: 0, y: 0) } == 255, "zero radius leaves corners square")
    check(ImageOps.roundedCorners(square, radius: 500)?.width == 40, "huge radius is clamped, size unchanged")
}
if let legacy = try? JSONDecoder().decode(EditorProject.self, from: Data(#"{"version":1,"doc":{"items":[],"nextID":1,"nextStep":1},"layers":[],"framed":false}"#.utf8)) {
    check(legacy.cornerRadius == nil, "projects saved before rounded corners still load")
} else { check(false, "legacy project decodes") }

// MARK: Thumbnails
do {
    let thumbDir = FileManager.default.temporaryDirectory.appendingPathComponent("snapverify-thumb-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: thumbDir) }
    func writeFixture(_ name: String, width: Int, height: Int) -> URL? {
        let url = thumbDir.appendingPathComponent(name)
        guard let image = renderSolid(width: width, height: height),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? url : nil
    }
    if let wide = writeFixture("wide.png", width: 3000, height: 1500) {
        let thumb = Thumbnail.make(at: wide, maxPixelSize: 600)
        check(thumb?.width == 600 && thumb?.height == 300, "thumbnail fits the longest side, keeping aspect (got \(thumb?.width ?? 0)x\(thumb?.height ?? 0))")
        if let thumb, let full = renderSolid(width: 3000, height: 1500) {
            check(Thumbnail.byteCost(of: thumb) * 20 < Thumbnail.byteCost(of: full), "thumbnail costs a fraction of the full decode")
        }
        check(Thumbnail.make(at: wide, maxPixelSize: 0) == nil, "zero size is rejected")
    }
    if let tall = writeFixture("tall.png", width: 400, height: 2000) {
        check(Thumbnail.make(at: tall, maxPixelSize: 500)?.height == 500, "tall images are limited by height")
    }
    if let small = writeFixture("small.png", width: 120, height: 80) {
        let thumb = Thumbnail.make(at: small, maxPixelSize: 600)
        check(thumb?.width == 120 && thumb?.height == 80, "small images are never upscaled")
    }
    check(Thumbnail.make(at: thumbDir.appendingPathComponent("missing.png"), maxPixelSize: 600) == nil, "missing file returns nil")
    let notImage = thumbDir.appendingPathComponent("notes.txt")
    try Data("hello".utf8).write(to: notImage)
    check(Thumbnail.make(at: notImage, maxPixelSize: 600) == nil, "non-image file returns nil")
} catch {
    check(false, "thumbnail fixtures threw: \(error)")
}

// MARK: Capture formats
check(CaptureFormat(fileExtension: "JPG") == .jpeg && CaptureFormat(fileExtension: "jpeg") == .jpeg, "jpg and jpeg map to JPEG")
check(CaptureFormat(fileExtension: "png") == .png && CaptureFormat(fileExtension: "heic") == .heic, "png and heic are recognised")
check(CaptureFormat(fileExtension: "gif") == nil && CaptureFormat(fileExtension: "") == nil, "unsupported extensions are rejected")
check(CaptureFormat.jpeg.fileExtension == "jpg" && CaptureFormat.heic.fileExtension == "heic", "file extensions are conventional")
check(!CaptureFormat.jpeg.supportsTransparency && CaptureFormat.png.supportsTransparency, "only JPEG lacks transparency")

func decodeFormat(_ data: Data) -> String? {
    CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
}
func decodePixel(_ data: Data, x: Int, y: Int) -> [UInt8]? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    var pixel = [UInt8](repeating: 0, count: 4)
    guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return pixel
}
if let solid = renderSolid(width: 64, height: 48) {
    let png = CaptureEncoder.data(solid, format: .png)
    let jpeg = CaptureEncoder.data(solid, format: .jpeg)
    let heic = CaptureEncoder.data(solid, format: .heic)
    check(png.flatMap(decodeFormat) == "public.png", "PNG encodes as PNG")
    check(jpeg.flatMap(decodeFormat) == "public.jpeg", "JPEG encodes as JPEG")
    if let heic { check(decodeFormat(heic) == "public.heic", "HEIC encodes as HEIC") }
    else { print("skip - HEIC encoder unavailable on this machine") }
    if let jpeg, let p = decodePixel(jpeg, x: 30, y: 20), let ref = png.flatMap({ decodePixel($0, x: 30, y: 20) }) {
        let drift = zip(p.prefix(3), ref.prefix(3)).map { abs(Int($0) - Int($1)) }.max() ?? 255
        check(drift <= 6, "JPEG keeps colours within compression error of PNG (jpeg \(p) vs png \(ref))")
    }

    if let low = CaptureEncoder.data(solid, format: .jpeg, quality: 0.1), let high = CaptureEncoder.data(solid, format: .jpeg, quality: 1) {
        check(low.count <= high.count, "lower JPEG quality never makes a bigger file (\(low.count) vs \(high.count) bytes)")
    }
    check(CaptureEncoder.data(solid, format: .jpeg, quality: -5) != nil && CaptureEncoder.data(solid, format: .jpeg, quality: 9) != nil,
          "out-of-range quality is clamped, not rejected")
}
if let square = renderSolid(width: 40, height: 40), let rounded = ImageOps.roundedCorners(square, radius: 12) {
    if let jpeg = CaptureEncoder.data(rounded, format: .jpeg), let corner = decodePixel(jpeg, x: 0, y: 0) {
        check(corner[0] > 240 && corner[1] > 240 && corner[2] > 240, "transparent corners become white in JPEG, not black (got \(corner))")
    } else { check(false, "rounded image encodes as JPEG") }
    if let png = CaptureEncoder.data(rounded, format: .png), let corner = decodePixel(png, x: 0, y: 0) {
        check(corner[3] == 0, "PNG keeps transparent corners")
    }
}
do {
    let formatDir = FileManager.default.temporaryDirectory.appendingPathComponent("snapverify-format-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: formatDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: formatDir) }
    if let solid = renderSolid(width: 20, height: 20) {
        let target = formatDir.appendingPathComponent("shot.jpg")
        check(CaptureEncoder.write(solid, format: .jpeg, to: target), "write reports success")
        check((try? Data(contentsOf: target)).flatMap(decodeFormat) == "public.jpeg", "written file is a real JPEG")
        check(!CaptureEncoder.write(solid, format: .png, to: formatDir.appendingPathComponent("missing/dir/x.png")),
              "write into a missing folder reports failure")
    }
}

// MARK: Library query (dashboard filters)
let day: TimeInterval = 86_400
let qBase = Date(timeIntervalSince1970: 1_700_000_000)
let qImage = CaptureRecord(id: "a", kind: .image, fileName: "a.png", createdAt: qBase, width: 100, height: 100, ocrText: "Invoice 42", title: "beta")
let qShot = CaptureRecord(id: "b", kind: .image, fileName: "b.jpg", createdAt: qBase + day, width: 300, height: 200, ocrText: "  \n", title: "Alpha", isFavorite: true)
let qVideo = CaptureRecord(id: "c", kind: .video, fileName: "c.mp4", createdAt: qBase + 2 * day, width: 50, height: 50, title: "clip 10")
let qMeeting = CaptureRecord(id: "d", kind: .video, fileName: "d.mp4", createdAt: qBase + 3 * day, width: 60, height: 60, ocrText: "standup notes", title: "clip 9")
let qAll = [qImage, qShot, qVideo, qMeeting]
let hasNotesForQuery: (CaptureRecord) -> Bool = { $0.id == "d" }
@MainActor func ids(_ f: CaptureFilter, _ s: CaptureSort = .newest, _ q: String = "") -> [String] {
    LibraryQuery.apply(qAll, filter: f, sort: s, query: q, hasMeetingNotes: hasNotesForQuery).map(\.id)
}
check(ids(.all) == ["d", "c", "b", "a"], "All shows everything, newest first")
check(ids(.images) == ["b", "a"], "Images shows only images")
check(ids(.videos) == ["d", "c"], "Videos shows only videos")
check(ids(.text) == ["d", "a"], "Text (OCR) shows captures with recognised text, ignoring whitespace-only text")
check(ids(.meetings) == ["d"], "Meetings shows only recordings with notes")
check(ids(.favorites) == ["b"], "Favorites shows starred captures")
check(ids(.all, .oldest) == ["a", "b", "c", "d"], "oldest first")
check(ids(.all, .name) == ["b", "a", "d", "c"], "name sort is case-insensitive and numeric-aware (clip 9 before clip 10)")
check(ids(.all, .largest).first == "b", "largest sorts by pixel area")
check(ids(.all, .newest, "invoice") == ["a"], "search matches OCR text")
check(ids(.images, .newest, "standup").isEmpty, "search and filter combine")
check(LibraryQuery.apply([], filter: .all, sort: .newest, query: "", hasMeetingNotes: hasNotesForQuery).isEmpty, "empty library stays empty")
check(LibraryQuery.greeting(hour: 5) == "Good morning" && LibraryQuery.greeting(hour: 11) == "Good morning", "morning is 5–11")
check(LibraryQuery.greeting(hour: 12) == "Good afternoon" && LibraryQuery.greeting(hour: 16) == "Good afternoon", "afternoon is 12–16")
check(LibraryQuery.greeting(hour: 17) == "Good evening" && LibraryQuery.greeting(hour: 2) == "Good evening", "evening covers late night")
check(LibraryQuery.firstName("Rahul Raj") == "Rahul" && LibraryQuery.firstName("  Ana ") == "Ana", "first name from full name")
check(LibraryQuery.firstName("") == nil && LibraryQuery.firstName("   ") == nil, "blank name gives nil")

// MARK: Capture settings
if let store = UserDefaults(suiteName: "snapverify.capture.\(UUID().uuidString)") {
    check(CaptureSettings.current(in: store) == CaptureSettings(includeCursor: false, windowShadow: true),
          "defaults: no cursor, window shadow on")
    store.set(true, forKey: CaptureSettings.cursorKey); store.set(false, forKey: CaptureSettings.shadowKey)
    check(CaptureSettings.current(in: store) == CaptureSettings(includeCursor: true, windowShadow: false),
          "saved capture settings are read back")
}
check(AfterCaptureAction(rawValue: "openEditor") == .openEditor && AfterCaptureAction(rawValue: "bogus") == nil,
      "after-capture action round-trips by raw value")
check(Set(AfterCaptureAction.allCases.map(\.title)).count == AfterCaptureAction.allCases.count, "after-capture titles are distinct")

// MARK: Redaction rendering (blur tool)
check(RedactRenderer.blockSize(for: CGSize(width: 200, height: 20)) == 10, "a single text line gets 10 px blocks, not 2")
check(RedactRenderer.blockSize(for: CGSize(width: 900, height: 600)) == 64, "large areas cap at 64 px blocks")
check(RedactRenderer.blockSize(for: CGSize(width: 5, height: 5)) == 10, "tiny areas still get a hiding block size")
check(RedactRenderer.blurRadius(for: CGSize(width: 200, height: 20)) >= 10, "blur radius is strong enough for a text line")

/// A striped image standing in for text: alternating black/white 2 px rows.
func stripes(width: Int, height: Int) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    for y in stride(from: 0, to: height, by: 2) {
        ctx.setFillColor(CGColor(gray: (y / 2) % 2 == 0 ? 0 : 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: y, width: width, height: 2))
    }
    return ctx.makeImage()
}
/// Spread between the darkest and lightest grey values — high means the detail is still visible.
func contrast(_ image: CGImage) -> Int {
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return 255 }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var lo = 255, hi = 0
    for y in 2..<(h - 2) { for x in 2..<(w - 2) { let v = Int(pixels[(y * w + x) * 4]); lo = min(lo, v); hi = max(hi, v) } }
    return hi - lo
}
if let text = stripes(width: 200, height: 24) {
    check(contrast(text) > 200, "fixture has full contrast before redaction")
    for style in RedactStyle.allCases {
        if let out = RedactRenderer.render(text, rect: CGRect(x: 0, y: 0, width: 200, height: 24), style: style) {
            check(out.width == 200 && out.height == 24, "\(style.title) keeps the region size")
            check(contrast(out) < 90, "\(style.title) hides fine detail in a text-sized area (contrast \(contrast(out)))")
        } else { check(false, "\(style.title) renders") }
    }
    check(RedactRenderer.render(text, rect: CGRect(x: 500, y: 500, width: 20, height: 20), style: .blur) == nil,
          "a rect outside the image renders nothing")
    check(RedactRenderer.render(text, rect: CGRect(x: 190, y: 0, width: 40, height: 24), style: .pixelate)?.width == 10,
          "a rect hanging off the edge is clipped to the image")
}

// MARK: Redaction style on annotations
var redactDoc = AnnotationDocument()
let pix = redactDoc.add(.blur, start: .zero, end: CGPoint(x: 10, y: 10))
check(pix.redactStyle == .pixelate, "new blur defaults to pixelate")
let solidBlur = redactDoc.add(.blur, start: .zero, end: CGPoint(x: 10, y: 10), redactStyle: .solid)
check(solidBlur.redactStyle == .solid, "blur keeps the chosen style")
check(redactDoc.add(.rect, start: .zero, end: CGPoint(x: 1, y: 1), redactStyle: .solid).redactStyle == nil,
      "non-blur annotations carry no redaction style")
redactDoc.restyle(id: pix.id, to: AnnotationStyle(redactStyle: .blur))
check(redactDoc.items.first { $0.id == pix.id }?.redactStyle == .blur, "restyling switches a blur's style")
check(redactDoc.insertCopy(of: solidBlur).redactStyle == .solid, "copies keep the redaction style")
if let legacy = try? JSONDecoder().decode(AnnotationStyle.self, from: Data(##"{"colorHex":"#FF0000","thickness":3,"filled":false,"opacity":1,"stepStyle":"number","lineStyle":"solid","startHead":"none","endHead":"arrow","arrowSize":"medium"}"##.utf8)) {
    check(legacy.redactStyle == nil, "styles saved before this release still load")
} else { check(false, "legacy saved style decodes") }

// MARK: Text Arrow compatibility and geometry
let oldCalloutJSON = ##"{"version":1,"doc":{"items":[{"id":4,"tool":"callout","start":[20,30],"end":[240,102],"text":"Legacy label","colorHex":"#007AFF","thickness":4,"filled":true,"opacity":1,"stepStyle":"number","lineStyle":"solid","startHead":"none","endHead":"arrow","arrowSize":"medium","points":[]}],"nextID":5,"nextStep":1},"layers":[],"framed":false}"##
do {
    let legacy = try JSONDecoder().decode(EditorProject.self, from: Data(oldCalloutJSON.utf8))
    let fixtureFolder = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-callout-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: fixtureFolder) }
    if let base = renderSolid(width: 400, height: 200) {
        try EditorProject.save(legacy, base: base, layerImages: [:], to: fixtureFolder)
        let reopened = try EditorProject.load(from: fixtureFolder)
        check(reopened?.project == legacy, "populated v1 project reopens from disk without conversion")
    } else { check(false, "legacy fixture base image creation") }
    let old = legacy.doc.items[0]
    check(old.pointerTip == nil && old.text == "Legacy label", "populated v1 callout keeps legacy rendering discriminator and text")
    check(old.start == CGPoint(x: 20, y: 30) && old.end == CGPoint(x: 240, y: 102), "v1 body geometry unchanged")
    check(AnnotationHandle.handles(for: old).count == 4, "legacy callout retains four handles")
    var modernDoc = legacy.doc
    let modern = CalloutGeometry.create(old, target: CGPoint(x: 320, y: 65))
    modernDoc.update(id: old.id) { $0 = modern }
    let copy = modernDoc.duplicate(id: old.id)!
    check(copy.id == 5 && modernDoc.items.count == 2, "callout duplicate is one object and preserves legacy nextID")
    check(copy.pointerTip == CGPoint(x: 336, y: 81) && copy.text == old.text, "duplicate moves body and pointer together")
    let tipMoved = AnnotationHandle.pointerTip.dragged(modern, to: CGPoint(x: -50, y: 60))
    check(tipMoved.start == modern.start && tipMoved.end == modern.end, "tip drag leaves text body fixed")
    let resized = AnnotationHandle.bottomRight.dragged(modern, to: CGPoint(x: 280, y: 140))
    check(resized.pointerTip == modern.pointerTip, "body resize preserves target")
    var transformed = modern
    transformed.transform { CGPoint(x: $0.x * 2, y: $0.y * 2) }
    check(transformed.pointerTip == CGPoint(x: 640, y: 130), "image transform includes callout target")
    let project = EditorProject(doc: modernDoc, layers: [], framed: false)
    let decoded = try JSONDecoder().decode(EditorProject.self, from: JSONEncoder().encode(project))
    check(decoded == project && decoded.version == EditorProject.currentVersion, "current project round-trips editable callouts")
    check(decoded.doc.items[0].pointerTip == modern.pointerTip, "pointer survives project round trip")
    modernDoc.restyle(id: modern.id, to: AnnotationStyle(colorHex: "#123456"))
    check(modernDoc.items[0].pointerTip == modern.pointerTip && modernDoc.items[0].text == old.text, "restyle preserves text and geometry")
    for target in [CGPoint(x: 340, y: 65), CGPoint(x: -100, y: 65), CGPoint(x: 80, y: -100), CGPoint(x: 80, y: 250)] {
        let arrow = CalloutGeometry.create(old, target: target)
        let path = CalloutGeometry.path(arrow)
        check(path.contains(CGPoint(x: 100, y: 60)), "arrow body hit for each target direction")
        check(CalloutGeometry.hit(target, on: arrow, tolerance: 8), "pointer has generous hit tolerance")
        check(CalloutGeometry.bounds(arrow).contains(target), "bounds contain pointer")
        check(!CalloutGeometry.hit(CGPoint(x: 1000, y: 1000), on: arrow, tolerance: 8), "distant point misses")
    }
    let rightArrow = CalloutGeometry.create(old, target: CGPoint(x: 400, y: 66))
    let rightPath = CalloutGeometry.path(rightArrow)
    check(rightPath.contains(CGPoint(x: 300, y: 66)), "slim arrow shaft connects body and head")
    check(!rightPath.contains(CGPoint(x: 300, y: 40)), "shaft stays slim instead of extending full body width")
    check(rightPath.contains(CGPoint(x: 375, y: 79)), "arrowhead has distinct wings")
    check(!rightPath.contains(CGPoint(x: 395, y: 79)), "arrowhead tapers to target")
    let referenceArrow = Annotation(id: 99, tool: .callout,
        start: CGPoint(x: 55, y: 55), end: CGPoint(x: 176, y: 120),
        pointerTip: CGPoint(x: 19, y: 14))
    let referencePath = CalloutGeometry.path(referenceArrow)
    check(referencePath.contains(CGPoint(x: 115, y: 85)), "rounded callout retains its text region")
    check(referencePath.contains(CGPoint(x: 50, y: 40)), "diagonal shaft reaches toward reference target")
    check(referencePath.contains(CGPoint(x: 32, y: 34)), "diagonal arrowhead has a clean shoulder")
    check(!referencePath.contains(CGPoint(x: 32, y: 44)), "diagonal arrow avoids a broad triangular tail")
    check(CalloutGeometry.bounds(referenceArrow).contains(CGPoint(x: 19, y: 14)), "diagonal bounds include target")
    let tiny = CalloutGeometry.create(old, target: old.start)
    check(CalloutGeometry.body(tiny).width >= 104 && tiny.pointerTip != old.start, "short drag produces usable body and visible tip")
    var overlapping = modern; overlapping.pointerTip = CGPoint(x: 60, y: 60)
    check(CalloutGeometry.path(overlapping).contains(CGPoint(x: 100, y: 60)), "overlapping tip retains valid body path")
} catch { check(false, "Text Arrow regression threw: \(error)") }

// MARK: Callout shape, appearance and saved-style compatibility
for shape in CalloutShape.allCases {
    var appearance = CalloutAppearance()
    appearance.shape = shape
    appearance.textColorHex = "#102030"
    appearance.fontFamily = "Georgia"
    appearance.fontSize = 24
    appearance.borderWidth = 2
    appearance.alignment = .center
    appearance.shadow = true
    var shapes = AnnotationDocument()
    let seed = shapes.add(.callout, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 260, y: 120), text: "Hello\nworld")
    shapes.update(id: seed.id) {
        $0.calloutAppearance = appearance
        $0.pointerTip = CGPoint(x: 340, y: 80)
    }
    let shapeAnnotation = shapes.items[0]
    check(CalloutGeometry.path(shapeAnnotation).contains(CGPoint(x: 150, y: 80)), "each callout shape contains its text body")
    check(AnnotationHandle.handles(for: shapeAnnotation).count == (shape == .blockArrow ? 9 : (shape.hasPointer ? 6 : 5)), "only shapes with tails expose pointer handle")
    if !shape.hasPointer {
        check(!CalloutGeometry.hit(CGPoint(x: 340, y: 80), on: shapeAnnotation, tolerance: 3), "hidden tail cannot be selected")
    }
    let storedStyle = AnnotationStyle(of: shapeAnnotation)
    var styleLibrary = SavedStyles()
    styleLibrary.add(storedStyle, for: .callout)
    do {
        let restoredStyles = try JSONDecoder().decode(SavedStyles.self, from: JSONEncoder().encode(styleLibrary))
        check(restoredStyles.styles(for: .callout) == [storedStyle], "My Styles preserves all callout properties")
        let project = EditorProject(doc: shapes, layers: [], framed: false)
        let reopened = try JSONDecoder().decode(EditorProject.self, from: JSONEncoder().encode(project))
        check(reopened == project && reopened.doc.items[0].calloutAppearance == appearance, "shape and appearance survive project round trip")
        let duplicate = shapes.duplicate(id: seed.id)!
        check(duplicate.calloutAppearance == appearance && duplicate.text == seed.text, "duplication preserves shape typography and contents")
        var replacement = storedStyle
        replacement.calloutAppearance?.shape = shape == .bubble ? .arrow : .bubble
        shapes.restyle(id: seed.id, to: replacement)
        check(shapes.items[0].pointerTip == shapeAnnotation.pointerTip, "shape changes retain pointer target")
        check(shapes.items[1].calloutAppearance == appearance, "restyling one callout leaves duplicate untouched")
        var modernArrow = AnnotationDocument()
        let v2 = modernArrow.add(.callout, start: .zero, end: CGPoint(x: 220, y: 72), thickness: 5)
        modernArrow.update(id: v2.id) { $0.pointerTip = CGPoint(x: 300, y: 36) }
        var oldProject = EditorProject(doc: modernArrow, layers: [], framed: false)
        oldProject.version = 2
        let decodedV2 = try JSONDecoder().decode(EditorProject.self, from: JSONEncoder().encode(oldProject))
        check(decodedV2.doc.items[0].calloutAppearance == nil && decodedV2.doc.items[0].resolvedCalloutAppearance.fontSize == 25,
              "v2 arrows retain original thickness-based text size")
    } catch { check(false, "callout styles round trip: \(error)") }
}
var extremeAppearance = CalloutAppearance()
extremeAppearance.fontSize = 1000; extremeAppearance.padding = -10; extremeAppearance.borderWidth = -1
check(extremeAppearance.normalized().fontSize == 96 && extremeAppearance.normalized().padding == 4
      && extremeAppearance.normalized().borderWidth == 0, "appearance normalizes unsafe dimensions")

// MARK: Native preferences must store property-list-compatible Data
let appearanceSuite = "snapverify-callout-settings-\(UUID().uuidString)"
if let defaults = UserDefaults(suiteName: appearanceSuite) {
    defer { defaults.removePersistentDomain(forName: appearanceSuite) }
    check(CalloutAppearancePreferences.load(in: defaults) == CalloutAppearance(), "missing appearance uses defaults")
    for shape in CalloutShape.allCases {
        var appearance = CalloutAppearance()
        appearance.shape = shape
        appearance.textColorHex = "#172B4D"
        appearance.fontSize = 27
        CalloutAppearancePreferences.save(appearance, in: defaults)
        check(defaults.object(forKey: "pref.calloutAppearance") is Data, "appearance writes Data accepted by UserDefaults")
        check(CalloutAppearancePreferences.load(in: defaults) == appearance, "each shape survives the actual preferences boundary")
    }
    defaults.set(Data("bad JSON".utf8), forKey: "pref.calloutAppearance")
    check(CalloutAppearancePreferences.load(in: defaults) == CalloutAppearance(), "corrupt appearance settings recover safely")
    defaults.set("old value", forKey: "pref.calloutAppearance")
    check(CalloutAppearancePreferences.load(in: defaults) == CalloutAppearance(), "old preference type recovers safely")
} else { check(false, "preferences test suite creation") }

var blockAppearance = CalloutAppearance(); blockAppearance.shape = .blockArrow
let textBlock = Annotation(id: 100, tool: .callout, start: CGPoint(x: 20, y: 30),
    end: CGPoint(x: 240, y: 102), text: "Type inside this arrow", pointerTip: CGPoint(x: 400, y: 66),
    calloutAppearance: blockAppearance)
let textBlockPath = CalloutGeometry.path(textBlock)
check(textBlockPath.contains(CGPoint(x: 300, y: 40)), "block arrow shaft continues at full text-body width")
let headGeometry = BlockArrowGeometry(textBlock)
let headWing = headGeometry.headHandle
// Use positive weights for all three triangle vertices: strictly inside, not on an edge.
let headInterior = CGPoint(x: headWing.x * 0.8 + headGeometry.tip.x * 0.1 + headGeometry.headCenter.x * 0.1,
                           y: headWing.y * 0.8 + headGeometry.tip.y * 0.1 + headGeometry.headCenter.y * 0.1)
let shoulderDistance = (headInterior.x - headGeometry.headCenter.x) * headGeometry.headNormal.x
    + (headInterior.y - headGeometry.headCenter.y) * headGeometry.headNormal.y
check(textBlockPath.contains(headInterior) && shoulderDistance > headGeometry.halfWidth,
      "block arrow has wide shoulders")
check(!textBlockPath.contains(CGPoint(x: 395, y: 115)), "block arrow head converges to target")
check(textBlockPath.contains(CGPoint(x: 100, y: 66)), "block arrow includes editable text region")
check(CalloutGeometry.bounds(textBlock).maxY > CalloutGeometry.body(textBlock).maxY, "block arrow bounds include wide head")
for tip in [CGPoint(x: -100, y: 66), CGPoint(x: 130, y: -100), CGPoint(x: 130, y: 250)] {
    var turned = textBlock; turned.pointerTip = tip
    check(CalloutGeometry.path(turned).contains(CGPoint(x: 130, y: 66)), "block arrow retains text region in each direction")
    check(CalloutGeometry.hit(tip, on: turned, tolerance: 6), "block arrow pointer selectable in each direction")
}

// MARK: Curved block-arrow direct controls and legacy rectangle availability
check(CalloutShape.availableCases.filter { $0.title == "Rectangle" } == [.roundedLabel],
      "one rounded Rectangle is offered")
check(!CalloutShape.availableCases.contains(.rectangle), "square legacy Rectangle is hidden without removing Codable support")
let blockControls = AnnotationHandle.handles(for: textBlock)
check(blockControls.map(\.0).contains(.shaftWidth) && blockControls.map(\.0).contains(.arrowheadSize)
      && blockControls.map(\.0).contains(.arrowBend), "block arrow exposes three direct geometry controls")
let initialBlockGeometry = BlockArrowGeometry(textBlock)
let widerPoint = CGPoint(x: initialBlockGeometry.shaftCenter.x + initialBlockGeometry.shaftNormal.x * initialBlockGeometry.halfWidth * 1.4,
    y: initialBlockGeometry.shaftCenter.y + initialBlockGeometry.shaftNormal.y * initialBlockGeometry.halfWidth * 1.4)
let widerArrow = AnnotationHandle.shaftWidth.dragged(textBlock, to: widerPoint)
check(BlockArrowGeometry(widerArrow).halfWidth > initialBlockGeometry.halfWidth, "shaft control thickens the curved shaft")
check(widerArrow.text == textBlock.text && widerArrow.pointerTip == textBlock.pointerTip, "shaft drag preserves label and target")
let largerHeadPoint = CGPoint(x: initialBlockGeometry.headCenter.x + initialBlockGeometry.headNormal.x * initialBlockGeometry.headHalfWidth * 1.2,
    y: initialBlockGeometry.headCenter.y + initialBlockGeometry.headNormal.y * initialBlockGeometry.headHalfWidth * 1.2)
let largerHead = AnnotationHandle.arrowheadSize.dragged(textBlock, to: largerHeadPoint)
check(largerHead.resolvedCalloutAppearance.pointerScale > textBlock.resolvedCalloutAppearance.pointerScale,
      "head control enlarges head independently")
check(BlockArrowGeometry(largerHead).halfWidth == initialBlockGeometry.halfWidth, "head size does not change shaft thickness")
let bendPoint = initialBlockGeometry.point(initialBlockGeometry.controlX, initialBlockGeometry.crossSize * 0.6 - initialBlockGeometry.halfWidth - 18)
let curvedArrow = AnnotationHandle.arrowBend.dragged(textBlock, to: bendPoint)
check(abs((curvedArrow.resolvedCalloutAppearance.blockArrowBend ?? 0) - 0.6) < 0.001, "bend handle adjusts quadratic shaft")
check(BlockArrowGeometry(curvedArrow).textOffset.dy > initialBlockGeometry.textOffset.dy,
      "inline text region follows curve")
check(curvedArrow.start == textBlock.start && curvedArrow.end == textBlock.end && curvedArrow.pointerTip == textBlock.pointerTip,
      "bend drag preserves body and tip coordinates")
var controlDoc = AnnotationDocument()
let controlSeed = controlDoc.add(.callout, start: curvedArrow.start, end: curvedArrow.end, text: curvedArrow.text)
controlDoc.update(id: controlSeed.id) { a in
    a.calloutAppearance = curvedArrow.calloutAppearance
    a.pointerTip = curvedArrow.pointerTip
}
let curveCopy = controlDoc.duplicate(id: controlSeed.id)!
check(curveCopy.calloutAppearance == curvedArrow.calloutAppearance, "duplicate retains bend and shaft proportions")
do {
    let project = EditorProject(doc: controlDoc, layers: [], framed: false)
    let decoded = try JSONDecoder().decode(EditorProject.self, from: JSONEncoder().encode(project))
    check(decoded == project, "curved arrow and controls survive project round trip")
    let defaultsData = try JSONEncoder().encode(CalloutAppearance())
    let legacyAppearance = try JSONDecoder().decode(CalloutAppearance.self, from: defaultsData)
    check(legacyAppearance.blockArrowBend == nil && legacyAppearance.blockArrowShaftScale == nil,
          "styles without control fields retain optional defaults")
} catch { check(false, "block arrow controls round trip: \(error)") }

// MARK: Free-direction arrow geometry and tangent-aligned text
for target in [CGPoint(x: 450, y: -100), CGPoint(x: -300, y: -80), CGPoint(x: -200, y: 250), CGPoint(x: 430, y: 230)] {
    var angled = textBlock; angled.pointerTip = target
    let geometry = BlockArrowGeometry(angled)
    let desiredX = target.x - geometry.body.midX, desiredY = target.y - geometry.body.midY
    let distance = hypot(desiredX, desiredY)
    check(abs(geometry.forward.x - desiredX / distance) < 0.000001 && abs(geometry.forward.y - desiredY / distance) < 0.000001,
          "arrow points freely instead of choosing a cardinal axis")
    let endNormal = geometry.normal(1)
    let alignment = endNormal.x * geometry.headNormal.x + endNormal.y * geometry.headNormal.y
    check(abs(alignment - 1) < 0.000001, "head follows the final shaft tangent without a right-angle elbow")
    check(abs(geometry.textAngle) <= .pi / 2, "text remains upright for left-facing arrows")
    check(abs(geometry.textAngle) > 0.01, "diagonal shaft has diagonal inline text")
    let middle = geometry.center(0.5)
    let shifted = CGPoint(x: geometry.body.midX + geometry.textOffset.dx, y: geometry.body.midY + geometry.textOffset.dy)
    check(hypot(middle.x - shifted.x, middle.y - shifted.y) < 0.000001, "text center stays on curve")
    check(CalloutGeometry.hit(target, on: angled, tolerance: 5), "freely angled head remains selectable")
    let bounds = CalloutGeometry.bounds(angled)
    check(bounds.width.isFinite && bounds.height.isFinite, "offset curve bounds stay finite")
}
var automaticText = CalloutAppearance()
automaticText.shape = .blockArrow
automaticText.blockArrowAutoTextSize = true
do {
    let data = try JSONEncoder().encode(automaticText)
    check(try JSONDecoder().decode(CalloutAppearance.self, from: data).blockArrowAutoTextSize == true,
          "automatic text sizing survives styles and projects")
} catch { check(false, "automatic text style round trip: \(error)") }

// MARK: Shape library, whole-object rotation and multiple targets
for shape in [CalloutShape.ellipse, .cloud, .thought, .burst] {
    var appearance = CalloutAppearance(); appearance.shape = shape
    let a = Annotation(id: 200, tool: .callout, start: CGPoint(x: 50, y: 60), end: CGPoint(x: 290, y: 200),
        text: "Wrapped label", pointerTip: CGPoint(x: 380, y: 170), calloutAppearance: appearance)
    let core = CalloutGeometry.textBody(a), path = CalloutGeometry.path(a)
    for point in [CGPoint(x: core.minX + 1, y: core.minY + 1), CGPoint(x: core.maxX - 1, y: core.maxY - 1)] {
        check(path.contains(point), "shape-specific text rectangle lies inside its outline")
    }
    check(path.boundingBoxOfPath.width.isFinite, "new shape has finite geometry")
    let rotated = AnnotationHandle.rotation.dragged(a, to: CGPoint(x: 400, y: 130))
    check(abs(rotated.resolvedCalloutAppearance.rotationDegrees ?? 0) > 1, "rotation handle changes whole-object rotation")
    let p = CGPoint(x: 135, y: 100)
    let roundTrip = CalloutGeometry.rotate(CalloutGeometry.rotate(p, on: rotated), on: rotated, inverse: true)
    check(hypot(roundTrip.x - p.x, roundTrip.y - p.y) < 0.00001, "rotation round trip preserves document coordinates")
}
var multiStyle = CalloutAppearance(); multiStyle.shape = .bubble; multiStyle.rotationDegrees = 35
var multi = Annotation(id: 300, tool: .callout, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 320, y: 200),
    pointerTip: CGPoint(x: 400, y: 150), calloutAppearance: multiStyle,
    additionalPointerTips: [CGPoint(x: 200, y: 300), CGPoint(x: 30, y: 120)])
check(AnnotationHandle.handles(for: multi).filter { if case .additionalPointer = $0.0 { return true }; return false }.count == 2,
      "each additional tail is independently manipulable")
let movedExtra = AnnotationHandle.additionalPointer(0).dragged(multi, to: CGPoint(x: 450, y: 350))
let worldExtra = CalloutGeometry.rotate(movedExtra.additionalPointerTips![0], on: movedExtra)
check(hypot(worldExtra.x - 450, worldExtra.y - 350) < 0.0001, "extra-tail drag respects object rotation")
let oldWorldTip = CalloutGeometry.rotate(multi.pointerTip!, on: multi)
let resizedMulti = AnnotationHandle.bottomRight.dragged(multi, to: CGPoint(x: 380, y: 300))
let newWorldTip = CalloutGeometry.rotate(resizedMulti.pointerTip!, on: resizedMulti)
check(hypot(oldWorldTip.x - newWorldTip.x, oldWorldTip.y - newWorldTip.y) < 0.0001, "rotated body resize does not move pointer target")
multi.translate(dx: 10, dy: 20)
check(multi.additionalPointerTips![0] == CGPoint(x: 210, y: 320), "whole-object move includes additional targets")

// MARK: Step shapes retain sequencing and project/style compatibility
var markers = AnnotationDocument()
for _ in 0..<12 { markers.add(.step, start: CGPoint(x: 100, y: 100), end: .zero) }
check(markers.items[9].stepLabel == "10" && markers.items[11].stepLabel == "12", "multi-digit marker sequence remains intact")
markers.remove(id: markers.items[0].id)
check(markers.items.first?.stepNumber == 2, "deleting marker does not renumber remaining steps")
var expectedCopiedStep = 13
for shape in StepShape.allCases {
    var appearance = StepAppearance(); appearance.shape = shape
    markers.update(id: markers.items[0].id) { $0.stepAppearance = appearance }
    let marker = markers.items[0]
    check(StepGeometry.path(marker).contains(marker.start), "each step shape contains its sequence label")
    check(AnnotationHandle.handles(for: marker).count == (shape == .pin ? 1 : 0), "only pin markers expose a target handle")
    let clone = markers.duplicate(id: marker.id)!
    check(clone.stepNumber == expectedCopiedStep && clone.stepAppearance == appearance, "marker copy keeps shape and advances sequence")
    expectedCopiedStep += 1
    markers.remove(id: clone.id)
    var style = AnnotationStyle(of: marker); style.colorHex = "#123456"
    markers.restyle(id: marker.id, to: style)
    check(markers.items[0].stepNumber == 2, "marker restyling preserves sequence identity")
}
markers.update(id: markers.items[0].id) { $0.text = "Start" }
check(markers.items[0].stepLabel == "Start" && markers.items[0].stepNumber == 2, "manual marker label preserves stored sequence number")
check(StepStyle.upper.label(for: 27) == "AA", "alphabetic markers continue beyond Z")
if let solid = renderSolid(width: 80, height: 60) {
    let sampled = SimplifySampling.surroundingColorHex(solid, region: CGRect(x: 20, y: 20, width: 20, height: 20))
    check(sampled.hasPrefix("#") && sampled.count == 7, "Simplify background sample returns a stored RGB color")
}
var extendedDoc = AnnotationDocument()
let extended = extendedDoc.add(.callout, start: multi.start, end: multi.end, text: "Two targets")
extendedDoc.update(id: extended.id) { $0.calloutAppearance = multi.calloutAppearance; $0.pointerTip = multi.pointerTip; $0.additionalPointerTips = multi.additionalPointerTips }
let regionBlock = extendedDoc.add(.rect, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 100, y: 60), filled: true)
extendedDoc.update(id: regionBlock.id) { $0.simplifyCornerRadius = 8 }
do {
    let project = EditorProject(doc: extendedDoc, layers: [], framed: false)
    let decoded = try JSONDecoder().decode(EditorProject.self, from: JSONEncoder().encode(project))
    check(decoded == project && decoded.doc.items[0].additionalPointerTips?.count == 2, "multiple tails and editable Simplify blocks round trip")
    let defaults = UserDefaults(suiteName: "step-test-\(UUID().uuidString)")!
    StepAppearancePreferences.save(StepAppearance(), in: defaults)
    check(defaults.data(forKey: "pref.stepAppearance") != nil, "step preferences use supported Data storage")
    defaults.removeObject(forKey: "pref.stepAppearance")
} catch { check(false, "expanded annotations round trip: \(error)") }

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
