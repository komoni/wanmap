#if DEBUG
import Foundation

/// UIテスト専用：隔離した永続保存先（愛ハス定例デモの「再起動しても残る」証明用）
///
/// 背景：従来の UI テスト経路（PlanStore(samplePlans:)）は端末ファイルへ書かない
/// ため、アプリを終了→再起動しても予定が残ることを証明できない。
/// この経路では本番の保存先（Documents/plans.json）とは別ディレクトリの
/// ファイルを PlanStore(fileURL:) で読み書きし、2回目の起動でも同じ保存先を
/// 読む。本番データには一切混ざらない（起動引数を付けた時だけ有効で、
/// 通常起動ではこのファイルのコードは使われない）。
enum UITestingPersistentStore {
    /// この引数がある時だけ、隔離した永続保存先で起動する
    static let launchArgument = "-UITestingPersistentPlans"
    /// この引数も併せて渡した起動では、保存先を空にしてから始める
    /// （テストの初回起動専用。再起動側の起動では付けない）
    static let resetArgument = "-UITestingPersistentPlansReset"

    /// 隔離先ディレクトリ（Documents/WanMapUITesting）
    static var directoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WanMapUITesting", isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent("plans.json")
    }

    /// 保存先を空にする（テスト初回起動の再現性のため）
    static func reset() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    /// 保存先ディレクトリを用意してファイルURLを返す。
    /// PlanStore の atomic write は親ディレクトリの存在を前提とするため、先に作る。
    static func prepareFileURL() -> URL {
        try? FileManager.default.createDirectory(at: directoryURL,
                                                 withIntermediateDirectories: true)
        return fileURL
    }
}
#endif
