import Foundation
import CoreGraphics
import CoreText
import CoreVideo
import CoreMedia
import UIKit

/// PiP 화면에 그릴 한 줄
struct RenderLine {
    var text: String
    /// 세로 공간 비율 (클수록 큰 글자)
    var share: CGFloat
    var color: UIColor
    var weight: UIFont.Weight = .bold
}

/// 시계 문자열을 CVPixelBuffer → CMSampleBuffer 로 그려서 PiP 레이어에 넣을 수 있게 만듭니다.
/// PiP 창의 모양(비율)은 이 버퍼 크기를 따라갑니다.
final class ClockFrameRenderer {
    let size: CGSize
    private var pool: CVPixelBufferPool?
    private var formatDescription: CMVideoFormatDescription?

    init(size: CGSize) {
        self.size = size
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
    }

    /// 줄들을 위에서 아래로 share 비율대로 나눠 가운데 정렬로 그림
    func makeSampleBuffer(lines: [RenderLine], pts: CMTime) -> CMSampleBuffer? {
        guard let pool else { return nil }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let pixelBuffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        // 위아래 여백 6%
        let pad = size.height * 0.06
        let usable = size.height - pad * 2
        let total = max(lines.reduce(0) { $0 + $1.share }, 0.001)
        var top = size.height - pad          // CGContext 는 좌하단 원점
        for line in lines {
            let h = usable * line.share / total
            let rect = CGRect(x: 0, y: top - h, width: size.width, height: h)
            drawCentered(line.text, height: h, weight: line.weight, color: line.color, in: rect, ctx: ctx)
            top -= h
        }

        if formatDescription == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer,
                                                         formatDescriptionOut: &formatDescription)
        }
        guard let formatDescription else { return nil }

        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: pts,
                                        decodeTimeStamp: .invalid)
        var sb: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer,
                                                 formatDescription: formatDescription,
                                                 sampleTiming: &timing, sampleBufferOut: &sb)
        if let sb, let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sb
    }

    /// 높이에 맞춘 글자 크기로 그리되, 폭을 넘으면 비율대로 줄임 (고정폭 숫자라 숫자가 바뀌어도 흔들리지 않음)
    private func drawCentered(_ string: String, height: CGFloat, weight: UIFont.Weight,
                              color: UIColor, in rect: CGRect, ctx: CGContext) {
        func makeLine(_ size: CGFloat) -> CTLine {
            let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            return CTLineCreateWithAttributedString(
                NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]))
        }
        var fontSize = max(6, height * 0.78)
        var line = makeLine(fontSize)
        var bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let maxWidth = rect.width * 0.94
        if bounds.width > maxWidth {
            fontSize = max(6, fontSize * maxWidth / bounds.width)
            line = makeLine(fontSize)
            bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        }
        let x = rect.midX - bounds.width / 2 - bounds.minX
        let y = rect.midY - bounds.height / 2 - bounds.minY
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }
}
