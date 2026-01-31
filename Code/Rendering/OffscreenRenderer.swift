// MARK: - File: OffscreenRenderer.swift
//--------------------------------------------------
import UIKit

final class OffscreenRenderer {
    
    func runBatch(
        viewer: VTKViewController,
        states: [[String: Any]],
        outputSizePoints: CGSize,
        onFrame: @escaping (Int, UIImage?) -> Void,
        completion: @escaping () -> Void
    ) {
        let offscreenWindow = UIWindow(frame: CGRect(origin: .zero, size: outputSizePoints))
        offscreenWindow.isHidden = false
        
        let hostVC = VTKViewController()
        offscreenWindow.rootViewController = hostVC
        
        hostVC.shareDataCache(from: viewer)
        
        var currentIndex = 0
        
        func processNext() {
            guard currentIndex < states.count else {
                completion()
                return
            }
            
            let state = states[currentIndex]
            let indexForCallbacks = currentIndex
            
            let timeoutSeconds: Double = 1.0
            var advanced = false
            
            func advance(with image: UIImage?) {
                guard !advanced else { return }
                advanced = true
                onFrame(indexForCallbacks, image)
                currentIndex += 1
                processNext()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) {
                advance(with: nil)
            }
            
            hostVC.applyViewerState(state, render: false) {
                guard !advanced else { return }
                hostVC.captureScreenshot { image in
                    advance(with: image)
                }
            }
        }
        
        processNext()
    }
}
