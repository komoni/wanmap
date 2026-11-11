import AVFoundation
import Observation
import UIKit

/// 完了フィードバックの実行役（デザイン・気持ちよさ第一弾）
/// - 鳴らすのは「予定の保存が本当に成功した時」と「今ここ配置が成功した時」
///   だけ。呼び出し側は Store の保存結果（Bool）が成功の時だけ呼ぶこと。
///   ボタンのタップ時点・失敗・削除・自動処理では呼ばない。
/// - 失敗の触覚は error()（第2単位、2026-11-12）：本人が始めた操作
///   （保存・削除・明示した現在地取得）が最終的に失敗し、次の対応が
///   要る時だけ .error を1回。音は出さない。途中経過・自動再試行・
///   再表示での再通知では呼ばない（線引きは DESIGN_PRINCIPLES.md）。
/// - 音は同梱の短い合成音1種類（Resources/Sounds/completion.wav）を
///   AVAudioPlayer で再生する。AVAudioSession は .ambient なので
///   サイレントスイッチが入っていれば鳴らず、他アプリの音楽も止めない。
/// - 触覚は UINotificationFeedbackGenerator の .success を1回だけ。
/// - 同時再生は1本まで、約150msの最小間隔を空ける（連打分を後から
///   まとめて鳴らすことはしない）。
@Observable
final class FeedbackService {

    private let settings: FeedbackSettings

    /// 音源プレーヤー（初回再生時に用意し、使い回す。タップ毎の生成はしない）
    private var player: AVAudioPlayer?
    private let successGenerator = UINotificationFeedbackGenerator()
    private let errorGenerator = UINotificationFeedbackGenerator()
    private var lastCompletionAt: Date = .distantPast
    private var lastErrorAt: Date = .distantPast
    private static let minimumInterval: TimeInterval = 0.15

    init(settings: FeedbackSettings) {
        self.settings = settings
    }

    /// 保存・配置の成功時に呼ぶ完了フィードバック。
    /// 設定がOFFのものは出さない。音と触覚は独立に判定する。
    func completion() {
        let now = Date()
        guard now.timeIntervalSince(lastCompletionAt) >= Self.minimumInterval else { return }
        lastCompletionAt = now
        if settings.soundEnabled { playSound() }
        if settings.hapticsEnabled {
            successGenerator.notificationOccurred(.success)
            successGenerator.prepare()
        }
    }

    /// 操作の最終失敗時に呼ぶ失敗フィードバック（触覚のみ・音なし）。
    /// 設定で触覚がOFFなら出さない。連打・再通知の重複は最小間隔で抑える。
    func error() {
        let now = Date()
        guard now.timeIntervalSince(lastErrorAt) >= Self.minimumInterval else { return }
        lastErrorAt = now
        if settings.hapticsEnabled {
            errorGenerator.notificationOccurred(.error)
            errorGenerator.prepare()
        }
    }

    /// 設定画面の「効果を試す」。トグルの状態にかかわらず音と触覚を
    /// 1回だけ出し、本人が判断材料にできるようにする
    /// （試聴もサイレントスイッチには従う）。
    func preview() {
        playSound()
        successGenerator.notificationOccurred(.success)
        successGenerator.prepare()
    }

    private func playSound() {
        // .ambient：サイレントスイッチと画面ロックで消音され、
        // 他アプリの音楽と混在できるカテゴリ。システム音量には従い、
        // アプリ側から音量を上げることはしない。
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default)
        try? session.setActive(true)

        if player == nil {
            guard let url = Bundle.main.url(forResource: "completion", withExtension: "wav") else { return }
            player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
        }
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }
}
