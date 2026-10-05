import Foundation

enum PlayMode: Int, CaseIterable {
    case fastest1080, fastest720, uhd60, fastest1440
    var width: Int32 { self == .uhd60 ? 3840 : self == .fastest1440 ? 2560 : self == .fastest720 ? 1280 : 1920 }
    var height: Int32 { width * 9 / 16 }
    var title: String {
        switch self {
        case .fastest1080: return "1080p · Highest FPS"
        case .fastest720: return "720p · Highest FPS"
        case .uhd60: return "4K · 60 FPS"
        case .fastest1440: return "1440p · Highest FPS"
        }
    }
}

struct ModeCandidate {
    let formatIndex: Int
    let rangeIndex: Int
    let width: Int32
    let height: Int32
    let minimumFPS: Double
    let maximumFPS: Double
    let isNV12: Bool
}

struct ModeChoice {
    let candidate: ModeCandidate
    let fps: Double
}

func chooseMode(_ mode: PlayMode, candidates: [ModeCandidate]) -> ModeChoice? {
    let choices = candidates.compactMap { candidate -> ModeChoice? in
        guard candidate.width == mode.width, candidate.height == mode.height,
              candidate.maximumFPS.isFinite, candidate.minimumFPS.isFinite,
              candidate.maximumFPS > 0, candidate.minimumFPS > 0,
              candidate.minimumFPS <= candidate.maximumFPS else { return nil }
        if mode == .uhd60 {
            // Both 59.94 and 60 are legitimate 4K60 capture timings. Never label 4K30 as 4K60.
            guard candidate.maximumFPS >= 59.9, candidate.minimumFPS <= 60.01 else { return nil }
            return ModeChoice(candidate: candidate, fps: min(max(60, candidate.minimumFPS), candidate.maximumFPS))
        }
        return ModeChoice(candidate: candidate, fps: candidate.maximumFPS)
    }
    return choices.sorted { a, b in
        if a.fps != b.fps { return a.fps > b.fps }
        if a.candidate.isNV12 != b.candidate.isNV12 { return a.candidate.isNV12 }
        return a.candidate.formatIndex < b.candidate.formatIndex
    }.first
}

func verifyModePolicy() {
    func mode(_ index: Int, _ width: Int32, _ min: Double, _ max: Double, _ nv12: Bool = true) -> ModeCandidate {
        ModeCandidate(formatIndex: index, rangeIndex: 0, width: width, height: width * 9 / 16,
                      minimumFPS: min, maximumFPS: max, isNV12: nv12)
    }
    let formats = [mode(0, 1920, 60, 60), mode(1, 1920, 120, 120, false),
                   mode(2, 3840, 30, 30), mode(3, 3840, 60, 120), mode(4, 1280, 240, 240)]
    precondition(chooseMode(.fastest1080, candidates: formats)?.fps == 120)
    precondition(chooseMode(.fastest720, candidates: formats)?.fps == 240)
    precondition(chooseMode(.uhd60, candidates: formats)?.fps == 60)
    precondition(chooseMode(.uhd60, candidates: [mode(0, 3840, 30, 30)]) == nil)
    precondition(chooseMode(.uhd60, candidates: [mode(0, 1920, 60, 60)]) == nil)
    precondition(chooseMode(.uhd60, candidates: [mode(0, 3840, 120, 120)]) == nil)
    precondition(abs(chooseMode(.uhd60, candidates: [mode(0, 3840, 59.94, 59.94)])!.fps - 59.94) < 0.001)
    precondition(chooseMode(.fastest1080, candidates: [mode(1, 1920, 60, 60, false), mode(2, 1920, 60, 60)])?.candidate.formatIndex == 2)
    precondition(chooseMode(.fastest1080, candidates: []) == nil)
    precondition(chooseMode(.fastest1440, candidates: [mode(0, 2560, 30, 30)])?.fps == 30)
    // Boundary cases and a strict frame-rate ordering prevent a near-tie from violating
    // the highest-FPS contract or the sort comparator's transitivity.
    precondition(chooseMode(.fastest1080, candidates: [mode(0, 1920, 60, 60), mode(1, 1920, 60.006, 60.006, false)])?.fps == 60.006)
    let invalid = [mode(0, 1920, .nan, 60), mode(1, 1920, 60, .infinity),
                   mode(2, 1920, 0, 60), mode(3, 1920, 120, 60), mode(4, 1920, -1, -1)]
    precondition(chooseMode(.fastest1080, candidates: invalid) == nil)
    let wrongHeight = ModeCandidate(formatIndex: 0, rangeIndex: 0, width: 1920, height: 1200, minimumFPS: 60, maximumFPS: 60, isNV12: true)
    precondition(chooseMode(.fastest1080, candidates: [wrongHeight]) == nil)
    for seed in 0..<100 {
        let rates = (0..<20).map { 60.0 + Double(($0 * 17 + seed * 11) % 97) / 1000 }
        let shuffled = rates.enumerated().map { mode($0.offset, 1920, $0.element, $0.element, $0.offset % 2 == 0) }
        precondition(chooseMode(.fastest1080, candidates: shuffled)?.fps == rates.max())
        precondition(chooseMode(.fastest1080, candidates: Array(shuffled.reversed()))?.fps == rates.max())
    }
    print("Mode policy passed: highest FPS, resolution matching, NV12 tie-break, 4K60/59.94, unsupported mode rejection.")
}
