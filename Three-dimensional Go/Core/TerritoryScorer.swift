import Foundation

/// 计分结果的胜负判定。
nonisolated enum ScoreOutcome: Hashable, Sendable {
    /// 指定一方胜。
    case win(Stone)
    /// 双方半目总分相同。
    case draw
}

/// 一次三维面积计分的完整明细。
///
/// 全部分数以半目为单位的整数保存和比较，不使用浮点。
nonisolated struct AreaScoreBreakdown: Hashable, Sendable {
    /// 盘上黑棋颗数。
    let blackStones: UInt32
    /// 盘上白棋颗数。
    let whiteStones: UInt32
    /// 归黑的空点数。
    let blackEmptyPoints: UInt32
    /// 归白的空点数。
    let whiteEmptyPoints: UInt32
    /// 中立空点数。
    let neutralPoints: UInt32
    /// 白方贴目半目数。
    let komiHalfPoints: UInt16
    /// 黑方半目总分。
    let blackScoreHalfPoints: UInt32
    /// 白方半目总分。
    let whiteScoreHalfPoints: UInt32
    /// 胜负或和棋。
    let outcome: ScoreOutcome
}

/// 三维面积计分器。
///
/// 遍历每个六向连通空区：只邻接一种颜色即归该方，同时邻接双方或不邻接任何棋子为中立。
/// 有限棋盘的外表面是天然边界，接触外表面不改变空区归属。
nonisolated enum TerritoryScorer {
    /// 任何合法配置下半目总分的上界：满盘棋子加上最大贴目，仍远小于 `UInt32.max`。
    static let maximumScoreHalfPoints: UInt32 =
        2
        * UInt32(Board.maximumDimension * Board.maximumDimension * Board.maximumDimension)
        + UInt32(UInt16.max)

    /// 对棋盘计分。
    ///
    /// - Parameters:
    ///   - board: 待计分棋盘。
    ///   - deadStones: 调用方约定的死棋坐标，计分前移除；缺省为空。
    ///   - komiHalfPoints: 白方贴目半目数。
    /// - Returns: 完整计分明细。
    static func score(
        board: Board,
        removingDeadStones deadStones: Set<GridPosition> = [],
        komiHalfPoints: UInt16
    ) -> AreaScoreBreakdown {
        var scored = board
        for position in deadStones where scored.contains(position) {
            scored[position] = nil
        }

        var blackStones: UInt32 = 0
        var whiteStones: UInt32 = 0
        var blackEmptyPoints: UInt32 = 0
        var whiteEmptyPoints: UInt32 = 0
        var neutralPoints: UInt32 = 0
        var visited = Set<GridPosition>()

        for position in scored.canonicalPositions {
            switch scored[position] {
            case .black:
                blackStones += 1
                continue
            case .white:
                whiteStones += 1
                continue
            case .none:
                break
            }
            guard visited.insert(position).inserted else { continue }

            let region = emptyRegion(on: scored, from: position, visited: &visited)
            switch (region.touchesBlack, region.touchesWhite) {
            case (true, false):
                blackEmptyPoints += region.size
            case (false, true):
                whiteEmptyPoints += region.size
            default:
                neutralPoints += region.size
            }
        }

        let blackScoreHalfPoints = 2 * (blackStones + blackEmptyPoints)
        let whiteScoreHalfPoints = 2 * (whiteStones + whiteEmptyPoints) + UInt32(komiHalfPoints)
        assert(blackScoreHalfPoints <= maximumScoreHalfPoints)
        assert(whiteScoreHalfPoints <= maximumScoreHalfPoints)

        let outcome: ScoreOutcome
        if blackScoreHalfPoints > whiteScoreHalfPoints {
            outcome = .win(.black)
        } else if whiteScoreHalfPoints > blackScoreHalfPoints {
            outcome = .win(.white)
        } else {
            outcome = .draw
        }

        return AreaScoreBreakdown(
            blackStones: blackStones,
            whiteStones: whiteStones,
            blackEmptyPoints: blackEmptyPoints,
            whiteEmptyPoints: whiteEmptyPoints,
            neutralPoints: neutralPoints,
            komiHalfPoints: komiHalfPoints,
            blackScoreHalfPoints: blackScoreHalfPoints,
            whiteScoreHalfPoints: whiteScoreHalfPoints,
            outcome: outcome
        )
    }

    /// 从一个空点出发迭代扩散出完整六向连通空区。
    ///
    /// - Returns: 空区大小，以及它是否邻接黑棋、是否邻接白棋。
    private static func emptyRegion(
        on board: Board,
        from origin: GridPosition,
        visited: inout Set<GridPosition>
    ) -> (size: UInt32, touchesBlack: Bool, touchesWhite: Bool) {
        var pending = [origin]
        var size: UInt32 = 0
        var touchesBlack = false
        var touchesWhite = false
        while let current = pending.popLast() {
            size += 1
            for neighbor in board.neighbors(of: current) {
                switch board[neighbor] {
                case .black:
                    touchesBlack = true
                case .white:
                    touchesWhite = true
                case .none:
                    if visited.insert(neighbor).inserted {
                        pending.append(neighbor)
                    }
                }
            }
        }
        return (size, touchesBlack, touchesWhite)
    }
}
