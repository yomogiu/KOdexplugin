import Foundation
import CoreGraphics
import Vision

struct Ink: Decodable { let width: Int; let height: Int; let strokes: [[[Double]]] }
enum InvalidInk: Error { case invalid }
func recognize(_ data: Data) throws -> [String: Any] {
    guard data.count <= 800_000 else { throw InvalidInk.invalid }
    let ink = try JSONDecoder().decode(Ink.self, from: data)
    guard (64...2048).contains(ink.width), (64...2048).contains(ink.height),
          (1...1000).contains(ink.strokes.count) else { throw InvalidInk.invalid }
    var count = 0
    for stroke in ink.strokes {
        guard !stroke.isEmpty else { throw InvalidInk.invalid }
        count += stroke.count
        for p in stroke {
            guard p.count == 2, p[0].isFinite, p[1].isFinite,
                  p[0] >= 0, p[0] < Double(ink.width),
                  p[1] >= 0, p[1] < Double(ink.height) else { throw InvalidInk.invalid }
        }
    }
    guard count <= 20_000 else { throw InvalidInk.invalid }
    guard let ctx = CGContext(data: nil, width: ink.width, height: ink.height,
        bitsPerComponent: 8, bytesPerRow: ink.width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw InvalidInk.invalid }
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: ink.width, height: ink.height))
    ctx.translateBy(x: 0, y: CGFloat(ink.height)); ctx.scaleBy(x: 1, y: -1)
    ctx.setStrokeColor(gray: 0, alpha: 1); ctx.setFillColor(gray: 0, alpha: 1)
    ctx.setLineWidth(4); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    for stroke in ink.strokes {
        let first = stroke[0]
        if stroke.count == 1 {
            ctx.fillEllipse(in: CGRect(x: first[0]-2, y: first[1]-2, width: 4, height: 4))
        } else {
            ctx.beginPath(); ctx.move(to: CGPoint(x: first[0], y: first[1]))
            for p in stroke.dropFirst() { ctx.addLine(to: CGPoint(x: p[0], y: p[1])) }
            ctx.strokePath()
        }
    }
    guard let image = ctx.makeImage() else { throw InvalidInk.invalid }
    let request = VNRecognizeTextRequest()
    request.revision = VNRecognizeTextRequestRevision3
    request.recognitionLevel = .accurate
    request.usesCPUOnly = true
    request.recognitionLanguages = ["en-US", "fr-FR"]
    request.usesLanguageCorrection = true
    request.minimumTextHeight = 0.015
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])
    let observations = (request.results ?? []).sorted {
        if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.015 {
            return $0.boundingBox.midY > $1.boundingBox.midY
        }
        return $0.boundingBox.minX < $1.boundingBox.minX
    }
    let candidates = observations.compactMap { $0.topCandidates(1).first }
    let text = String(candidates.map { $0.string }.joined(separator: "\n").prefix(16_000))
    let confidence = candidates.isEmpty ? 0 : candidates.reduce(0.0) { $0 + Double($1.confidence) } / Double(candidates.count)
    return ["text": text, "confidence": confidence]
}

// Bounded stdin only: no paths, URLs, image files, or network clients.
do {
    let data = FileHandle.standardInput.readData(ofLength: 800_001)
    let result = try recognize(data)
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result))
} catch {
    if CommandLine.arguments.contains("--diagnose") {
        FileHandle.standardError.write(Data("Local OCR diagnostic: \(error)\n".utf8))
    }
    FileHandle.standardOutput.write(Data("{\"error\":\"Local handwriting recognition failed\"}".utf8))
    exit(1)
}
