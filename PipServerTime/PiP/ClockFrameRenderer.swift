import Foundation
import CoreGraphics
import CoreText
import CoreVideo
import CoreMedia
import UIKit

/// 시계 문자열을 CVPixelBuffer → CMSampleBuffer 로 그려서 PiP 레이어에 넣을 수 있게 만듭니다.
final class ClockFrameRenderer {
    let size: CGSize
    private var pool: CVPixelBufferPool?
    private var formatDescription: CMVideoFormatDescription?

    init(size: CGSize = CGSize(width: 1200, height: 200)) {
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

    func makeSampleBuffer(text: String, subtitle: String?, highlight: Bool, pts: CMTime) -> CMSampleBuffer? {
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

        // 배경
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        // 본문 (고정폭 숫자라 숫자가 바뀌어도 글자가 흔들리지 않음)
        let mainHeight = subtitle == nil ? size.height : size.height * 0.75
        drawCentered(text,
                     font: UIFont.monospacedDigitSystemFont(ofSize: mainHeight * 0.55, weight: .bold),
                     color: highlight ? UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1) : UIColor(white: 0.85, alpha: 1),
                     in: CGRect(x: 0, y: size.height - mainHeight, width: size.width, height: mainHeight),
                     ctx: ctx)
        if let subtitle {
            drawCentered(subtitle,
                         font: UIFont.systemFont(ofSize: size.height * 0.13, weight: .medium),
                         color: UIColor(white: 0.55, alpha: 1),
                         in: CGRect(x: 0, y: 0, width: size.width, height: size.height - mainHeight),
                         ctx: ctx)
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

    /// CGContext 는 좌하단 원점이므로 rect 의 y 는 아래에서부터
    private func drawCentered(_ string: String, font: UIFont, color: UIColor, in rect: CGRect, ctx: CGContext) {
        var fontSize = font.pointSize
        var line: CTLine
        var bounds: CGRect
        // 폭에 맞게 글자 크기 자동 축소
        repeat {
            let f = font.withSize(fontSize)
            let attr = NSAttributedString(string: string, attributes: [.font: f, .foregroundColor: color])
            line = CTLineCreateWithAttributedString(attr)
            bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            fontSize -= 2
        } while bounds.width > rect.width * 0.94 && fontSize > 8

        let x = rect.midX - bounds.width / 2 - bounds.minX
        let y = rect.midY - bounds.height / 2 - bounds.minY
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }
}
