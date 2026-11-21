import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import Foundation
import Observation

/// サーバーアカウント（フェーズ2単位2-3）。
/// - Apple ID で Firebase Auth へサインインする
/// - 初回サインイン時に users/{uid} を作り、表示ID（wan-xxxxxx）を
///   displayIds コレクションで一意に採番する
/// - サインインは友達・共有機能のためのもの。未サインインでも
///   端末内の機能は従来どおり使える（アプリをゲートしない）
/// - アカウント削除の再開処理は単位2-7でここへ足す
@MainActor
@Observable
final class AuthService {

    /// Firebase Auth の uid（未サインインなら nil）
    private(set) var uid: String?
    /// サーバー表示ID（wan-xxxxxx）。プロフィール読み込み前は nil
    private(set) var displayId: String?
    /// サーバーに保存した表示名（Apple の氏名。未提供なら空）
    private(set) var serverDisplayName: String?
    /// サインイン処理中
    private(set) var isBusy = false
    /// 設定画面へ出す失敗メッセージ（成功時は nil）
    var errorMessage: String?

    var isSignedIn: Bool { uid != nil }

    @ObservationIgnored private var authListener: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var currentNonce: String?
    @ObservationIgnored private var ensuringProfile = false

    init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                self.uid = user?.uid
                if let user {
                    await self.ensureProfile(uid: user.uid, appleDisplayName: nil)
                } else {
                    self.displayId = nil
                    self.serverDisplayName = nil
                }
            }
        }
    }

    // MARK: - Apple サインイン

    /// SignInWithAppleButton の onRequest から呼ぶ。nonce を発行して保持し、
    /// ハッシュ化したものを Apple へ渡す（Firebase の作法）。
    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName]
        request.nonce = Self.sha256(nonce)
    }

    /// SignInWithAppleButton の onCompletion から呼ぶ。
    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            // 本人のキャンセルはエラーとして見せない
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "サインインできませんでした。通信状態を確認してもう一度お試しください"
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = "サインイン情報を確認できませんでした。もう一度お試しください"
                return
            }
            currentNonce = nil
            isBusy = true
            defer { isBusy = false }
            do {
                let oauthCredential = OAuthProvider.credential(providerID: "apple.com",
                                                               idToken: idToken,
                                                               rawNonce: nonce)
                let authResult = try await Auth.auth().signIn(with: oauthCredential)
                let appleName = credential.fullName.map {
                    PersonNameComponentsFormatter().string(from: $0)
                }
                await ensureProfile(uid: authResult.user.uid, appleDisplayName: appleName)
            } catch {
                errorMessage = "サインインできませんでした。通信状態を確認してもう一度お試しください"
            }
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            errorMessage = nil
        } catch {
            errorMessage = "サインアウトできませんでした"
        }
    }

    // MARK: - プロフィール（users ドキュメントと表示IDの採番）

    /// users/{uid} があれば読み、無ければ表示IDを採番して作る。
    /// 採番は displayIds への create（ルールで create のみ許可・上書き不可）と
    /// users 作成を1つのバッチにまとめる。万一同じ候補が同時に出ても、
    /// 後からのバッチは displayIds 側が更新扱いでルールに弾かれ、
    /// バッチごと失敗するので、別候補で再試行する。
    private func ensureProfile(uid: String, appleDisplayName: String?) async {
        guard !ensuringProfile else { return }
        ensuringProfile = true
        defer { ensuringProfile = false }

        let db = Firestore.firestore()
        let userRef = db.collection("users").document(uid)
        do {
            let snapshot = try await userRef.getDocument()
            if let data = snapshot.data() {
                displayId = data["displayId"] as? String
                serverDisplayName = data["displayName"] as? String
                return
            }
        } catch {
            errorMessage = "プロフィールを読み込めませんでした"
            return
        }

        let name = appleDisplayName ?? ""
        for _ in 0..<8 {
            let candidate = DisplayID.generate()
            let batch = db.batch()
            batch.setData(["uid": uid],
                          forDocument: db.collection("displayIds").document(candidate))
            batch.setData([
                "displayId": candidate,
                "displayName": name,
                "createdAt": FieldValue.serverTimestamp(),
                "schemaVersion": 1,
            ], forDocument: userRef)
            do {
                try await batch.commit()
                displayId = candidate
                serverDisplayName = name
                errorMessage = nil
                return
            } catch {
                continue // 候補の衝突など。別候補で再試行する
            }
        }
        errorMessage = "表示IDを発行できませんでした。時間をおいてもう一度お試しください"
    }

    // MARK: - nonce

    private static func randomNonce(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var rng = SystemRandomNumberGenerator()
        result.reserveCapacity(length)
        for _ in 0..<length {
            result.append(charset[Int.random(in: 0..<charset.count, using: &rng)])
        }
        return result
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
