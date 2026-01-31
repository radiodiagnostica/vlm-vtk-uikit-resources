// MARK: - File: BatchCaptureManager.swift
//--------------------------------------------------
import UIKit

enum SliceSamplingStrategy {
    case uniform
    case centerBiased(exponent: Double)
}

struct CaptureRequest {
    let seriesID: String
    let mode: RenderingMode
    let samplingCount: Int
    let samplingStrategy: SliceSamplingStrategy
    
    // For .mpr: 0=none, 1=axial, 2=coronal, 3=sagittal
    let orientationIntent: Int
    
    // For .mpr: 0=none, 1=mip, 2=minip, 3=average
    let slabType: Int
    let slabThicknessMm: Double
}

final class BatchCaptureManager {
    
    private let offscreenRenderer = OffscreenRenderer()
    
    func executeBatch(
        requests: [CaptureRequest],
        sourceViewer: VTKViewController,
        outputSizePoints: CGSize,
        onImageGenerated: @escaping (UIImage) -> Void,
        onBatchComplete: @escaping () -> Void
    ) {
        var allStates: [[String: Any]] = []
        
        for r in requests {
            let (samplingKind, exponent) = samplingParams(r.samplingStrategy)
            
            switch r.mode {
            case .slice2D:
                let states = sourceViewer.minimal2DViewerStatesForSeriesID(
                    r.seriesID,
                    maxEntries: r.samplingCount,
                    samplingStrategy: samplingKind,
                    centerBiasExponent: exponent
                ) as? [[String: Any]] ?? []
                allStates.append(contentsOf: states)
                
            case .mpr:
                let states = sourceViewer.mprViewerStatesForSeriesID(
                    r.seriesID,
                    maxEntries: r.samplingCount,
                    orientationIntent: r.orientationIntent,
                    slabType: r.slabType,
                    slabThicknessMm: r.slabThicknessMm,
                    samplingStrategy: samplingKind,
                    centerBiasExponent: exponent
                ) as? [[String: Any]] ?? []
                allStates.append(contentsOf: states)
            }
        }
        
        guard !allStates.isEmpty else { onBatchComplete(); return }
        
        offscreenRenderer.runBatch(
            viewer: sourceViewer,
            states: allStates,
            outputSizePoints: outputSizePoints,
            onFrame: { _, image in if let image { onImageGenerated(image) } },
            completion: onBatchComplete
        )
    }
    
    private func samplingParams(_ s: SliceSamplingStrategy) -> (Int, Double) {
        switch s {
        case .uniform:
            return (0, 0.0)
        case .centerBiased(let exponent):
            return (1, exponent)
        }
    }
}
