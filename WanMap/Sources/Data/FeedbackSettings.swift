import Foundation
import Observation

/// 「音と触覚」の設定（デザイン・気持ちよさ第一弾）
/// - 効果音・触覚フィードバックはどちらも既定ON（本人の決定。
///   効果音はサイレントスイッチ尊重が前提で、マナーモード時は鳴らない）。
/// - 未保存のキーを既定ONとして読むため、bool(forKey:) の暗黙の false に
///   ならないよう register(defaults:) で既定値を明示する。
/// - 実際の再生・振動は FeedbackService が担い、ここは設定の保持だけ。
@Observable
final class FeedbackSettings {

    private static let soundEnabledKey = "wanmap.feedback.soundEnabled"
    private static let hapticsEnabledKey = "wanmap.feedback.hapticsEnabled"

    private let defaults: UserDefaults

    /// 完了音を鳴らすか（既定ON）。変更したら即 UserDefaults に保存する
    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Self.soundEnabledKey) }
    }

    /// WanMapが追加する触覚フィードバックを出すか（既定ON）。
    /// OS標準部品が元々出す触覚までは止めない（設定説明にもその旨を書く）
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Self.hapticsEnabledKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Self.soundEnabledKey: true,
            Self.hapticsEnabledKey: true,
        ])
        soundEnabled = defaults.bool(forKey: Self.soundEnabledKey)
        hapticsEnabled = defaults.bool(forKey: Self.hapticsEnabledKey)
    }
}
