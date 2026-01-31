// MARK: - File: ModelAdapter.swift
//--------------------------------------------------
import UIKit
import ImageIO

struct ModelInputMedia {
    let data: Data
    let mimeType: String
    
    init?(heic image: UIImage, compressionQuality: CGFloat = 0.7) {
        guard let cgImage = image.cgImage else { return nil }
        
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.heic" as CFString, 1, nil) else {
            return nil
        }
        
        let orientationVal = Self.exifOrientation(for: image.imageOrientation)
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality,
            kCGImagePropertyOrientation: orientationVal
        ]
        
        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        
        self.data = out as Data
        self.mimeType = "image/heic"
    }
    
    private static func exifOrientation(for uiOrient: UIImage.Orientation) -> Int {
        switch uiOrient {
        case .up: return 1
        case .down: return 3
        case .left: return 8
        case .right: return 6
        case .upMirrored: return 2
        case .downMirrored: return 4
        case .leftMirrored: return 5
        case .rightMirrored: return 7
        @unknown default: return 1
        }
    }
}

final class LLMProviderService {
    
    func streamResponse(prompt: String, media: [ModelInputMedia]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = URLRequest(url: URL(string: "https://api.provider.com/v1/generate")!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    let payload: [String: Any] = [
                        "prompt": prompt,
                        "media": media.map {
                            ["mimeType": $0.mimeType, "base64": $0.data.base64EncodedString()]
                        }
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
                    
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        
                        let jsonText = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        if jsonText == "[DONE]" { break }
                        
                        if let chunk = parseChunk(jsonText) {
                            continuation.yield(chunk)
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func parseChunk(_ jsonLine: String) -> String? {
        guard let data = jsonLine.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        
        if let dict = obj as? [String: Any] {
            if let text = dict["text"] as? String { return text }
            if let delta = dict["delta"] as? String { return delta }
            
            if let choices = dict["choices"] as? [[String: Any]],
               let first = choices.first {
                if let text = first["text"] as? String { return text }
                if let deltaDict = first["delta"] as? [String: Any],
                   let content = deltaDict["content"] as? String {
                    return content
                }
            }
        }
        return nil
    }
}
