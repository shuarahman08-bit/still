import Foundation
import SwiftUI
import Security
import LocalAuthentication
import AuthenticationServices
import CryptoKit
import AppKit

struct OnlinePlayer: Codable, Identifiable { let id: UUID; let handle: String; let xp: Int; let rank: Int }
struct OnlineFriend: Codable, Identifiable { let id: UUID; let handle: String; let incoming: Bool; let accepted: Bool }
private struct OnlineSession: Codable {
    let access_token: String
    let refresh_token: String
    let expires_in: Double
    let user: User
    struct User: Codable { let id: UUID }
}
struct OnlineAction: Codable {
    let id: UUID
    let action: String
    let archetype: String
    let tier: String
    let seconds: Int
    let user: UUID
}

// No service-role key is shipped. All writes go through scoped, authenticated RPCs.
@MainActor final class OnlineStore: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let base = URL(string: "https://example.invalid")!
    static let key = "YOUR_SUPABASE_PUBLISHABLE_KEY"
    @Published var googleAvailable = false
    @Published var guestAvailable = false
    private var webAuth: ASWebAuthenticationSession?
    @Published var handle = ""
    @Published var friendHandle = ""
    @Published var players: [OnlinePlayer] = []
    @Published var friends: [OnlineFriend] = []
    @Published var signedIn = false
    @Published var confirmSignOut = false
    @Published var busy = false
    @Published var status: String?
    @Published var lastUpdated: Date?
    @Published var friendScope = false
    private var session: OnlineSession?
    private var expiry = Date.distantPast
    private var refreshTask: Task<OnlineSession, Error>?
    private var draining = false
    private var reloadGeneration = 0
    private var reloadInFlight = false
    private var loadingScope: Bool?
    private var providersCheckedAt: Date?
    private var retryTask: Task<Void, Never>?
    private var registered: [String: String] = [:]
    private var queue: [OnlineAction] = []
    private var startupRestoreCancelled = false
    var userID: UUID? { session?.user.id }
    private var service: String { (Bundle.main.bundleIdentifier ?? "com.still.focus") + ".online" }

    override init() {
        super.init()
        registered = UserDefaults.standard.dictionary(forKey: "online.registered") as? [String: String] ?? [:]
        handle = UserDefaults.standard.string(forKey: "online.handle") ?? ""
        if let data = UserDefaults.standard.data(forKey: "online.queue.v1"), let saved = try? JSONDecoder().decode([OnlineAction].self, from: data) { queue = saved }
        let savedService = service
        Task { [weak self] in
            // An updated app may need Keychain approval. Never block local timer startup on it.
            let data: Data? = await Task.detached {
                let context = LAContext(); context.interactionNotAllowed = true
                let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:savedService, kSecAttrAccount as String:"session", kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne, kSecUseAuthenticationContext as String:context]
                var result: CFTypeRef?
                guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
                return result as? Data
            }.value
            guard let self, !self.startupRestoreCancelled, !self.signedIn, let data, let saved = try? JSONDecoder().decode(OnlineSession.self, from:data) else { return }
            self.session = saved; self.signedIn = true
            if !self.queue.isEmpty { await self.drain() }
        }
    }
    private func saveSession(_ value: OnlineSession) throws {
        startupRestoreCancelled = true
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"session"]
        let data = try JSONEncoder().encode(value)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if update == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary,nil) == errSecSuccess else { throw failure("Couldn’t save your sign-in securely.") }
        } else if update != errSecSuccess { throw failure("Couldn’t save your sign-in securely.") }
        session = value; expiry = Date().addingTimeInterval(value.expires_in-60); signedIn = true
    }
    private func failure(_ message: String) -> NSError { NSError(domain:"StillOnline",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
    private func request(_ path: String, _ body: [String:Any], token: String? = nil) async throws -> Data {
        var r = URLRequest(url:URL(string: path, relativeTo: Self.base)!); r.httpMethod="POST"; r.timeoutInterval=20
        r.setValue(Self.key,forHTTPHeaderField:"apikey"); r.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if let token { r.setValue("Bearer " + token,forHTTPHeaderField:"Authorization") }
        r.httpBody=try JSONSerialization.data(withJSONObject:body)
        let (data,response)=try await URLSession.shared.data(for:r)
        guard let http=response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let payload=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
            throw failure(payload?["msg"] as? String ?? payload?["message"] as? String ?? payload?["error_description"] as? String ?? "Couldn’t connect. Try again.")
        }; return data
    }
    private func accessToken() async throws -> String {
        guard let session else { throw failure("Sign in to compete.") }
        if expiry>Date() { return session.access_token }
        if let refreshTask { return try await refreshTask.value.access_token }
        let task=Task { () throws -> OnlineSession in
            let data=try await request("auth/v1/token?grant_type=refresh_token",["refresh_token":session.refresh_token])
            return try JSONDecoder().decode(OnlineSession.self,from:data)
        }
        refreshTask=task
        defer { refreshTask=nil }
        let refreshed=try await task.value; try saveSession(refreshed); return refreshed.access_token
    }
    private func rpc(_ name:String,_ body:[String:Any]) async throws -> Data {
        let token=try await accessToken(); return try await request("rest/v1/rpc/"+name,body,token:token)
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
    }
    func checkProviders() async {
        if let checked = providersCheckedAt, Date().timeIntervalSince(checked) < 300 { return }
        do {
            var r=URLRequest(url:Self.base.appendingPathComponent("auth/v1/settings"))
            r.setValue(Self.key,forHTTPHeaderField:"apikey")
            r.timeoutInterval = 15
            let (data,response)=try await URLSession.shared.data(for:r)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw failure("Couldn’t load sign-in options.") }
            providersCheckedAt = Date()
            let settings=try JSONSerialization.jsonObject(with:data) as? [String:Any]
            let external=settings?["external"] as? [String:Any]
            googleAvailable=external?["google"] as? Bool ?? false
            guestAvailable=external?["anonymous_users"] as? Bool ?? false
        } catch {status="Couldn’t connect. Try again."}
    }
    func joinAsGuest() {
        guard !busy else {return}; busy=true; status=nil
        Task {defer {busy=false}; do {
            let name=handle.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
            guard name.range(of:"^[a-z0-9_]{3,24}$",options:.regularExpression) != nil else {throw failure("Choose 3–24 letters, numbers or underscores.")}
            if !signedIn {
                let data=try await request("auth/v1/signup",[:])
                try saveSession(JSONDecoder().decode(OnlineSession.self,from:data))
            }
            _=try await rpc("still_profile",["p_handle":name]); handle=name
            UserDefaults.standard.set(name,forKey:"online.handle"); await reload()
        } catch {status=error.localizedDescription} }
    }
    func signInWithGoogle() {
        guard !busy else {return}; busy=true; status=nil
        var bytes=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else {busy=false; return}
        func base64url(_ data:Data)->String {data.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")}
        let verifier=base64url(Data(bytes))
        let challenge=base64url(Data(SHA256.hash(data:Data(verifier.utf8))))
        var url=URLComponents(url:Self.base.appendingPathComponent("auth/v1/authorize"),resolvingAgainstBaseURL:false)!
        url.queryItems=[URLQueryItem(name:"provider",value:"google"),URLQueryItem(name:"redirect_to",value:"com.still.focus://auth/callback"),URLQueryItem(name:"code_challenge",value:challenge),URLQueryItem(name:"code_challenge_method",value:"s256")]
        webAuth=ASWebAuthenticationSession(url:url.url!,callbackURLScheme:"com.still.focus") { [weak self] callback,error in
            Task { @MainActor in
                guard let self else {return}; defer {self.busy=false; self.webAuth=nil}
                do {
                    guard let callback, callback.scheme=="com.still.focus",callback.host=="auth",callback.path=="/callback",
                          let code=URLComponents(url:callback,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name=="code"})?.value else {
                        throw self.failure(error == nil ? "Google sign-in wasn’t completed." : "Sign-in cancelled.")
                    }
                    let data=try await self.request("auth/v1/token?grant_type=pkce",["auth_code":code,"code_verifier":verifier])
                    try self.saveSession(JSONDecoder().decode(OnlineSession.self,from:data)); await self.reload()
                } catch {self.status=error.localizedDescription}
            }
        }
        webAuth?.presentationContextProvider=self
        if webAuth?.start() != true {busy=false;webAuth=nil;status="Couldn’t open Google sign-in."}
    }
    func saveProfile() {
        guard !busy else {return}; busy=true
        Task { defer {busy=false}; do {
            _=try await rpc("still_profile",["p_handle":handle.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)])
            UserDefaults.standard.set(handle,forKey:"online.handle"); await reload()
        } catch {status=error.localizedDescription} }
    }
    func reload() async {
        guard signedIn else {return}
        let scope = friendScope
        guard !reloadInFlight || loadingScope != scope else { return }
        reloadGeneration += 1
        let generation = reloadGeneration
        let account = userID
        reloadInFlight = true; loadingScope = scope
        defer { if generation == reloadGeneration { reloadInFlight = false; loadingScope = nil } }
        do {
            status=nil
            await drain()
            let data=try await rpc("still_board",["p_friends":scope])
            let board=try JSONDecoder().decode([OnlinePlayer].self,from:data)
            let requests=try await rpc("still_requests",[:])
            let relationships=try JSONDecoder().decode([OnlineFriend].self,from:requests)
            guard generation == reloadGeneration, signedIn, userID == account, friendScope == scope else { return }
            players=board; friends=relationships
            if let me=board.first(where:{$0.id==account}) {handle=me.handle}
            lastUpdated=Date()
        } catch {
            if generation == reloadGeneration, signedIn, userID == account { status=error.localizedDescription }
        }
    }
    func friend(_ handle:String,action:String) {
        guard !busy else {return}; busy=true
        Task {defer {busy=false}; do {_=try await rpc("still_friend",["p_handle":handle,"p_action":action]); friendHandle=""; await reload()} catch {status=error.localizedDescription}}
    }
    func enqueue(id:UUID,action:String,archetype:FocusArchetype,tier:IntensityTier,seconds:Int) {
        guard let user=userID else {return}
        if action == "start" { registered[id.uuidString] = user.uuidString; UserDefaults.standard.set(registered, forKey: "online.registered") }
        guard registered[id.uuidString] == user.uuidString else { return }
        if let last = queue.last, last.id == id, last.action == action, last.user == user { return }
        queue.append(OnlineAction(id:id,action:action,archetype:archetype.rawValue,tier:tier.rawValue,seconds:seconds,user:user)); saveQueue()
        Task { await drain() }
    }
    private func saveQueue() {UserDefaults.standard.set(try? JSONEncoder().encode(queue),forKey:"online.queue.v1")}
    private func drain() async {
        guard !draining,signedIn else {return}; draining=true; defer {draining=false}
        while let index = queue.firstIndex(where: { $0.user == userID }) {
            let item = queue[index]
            do {
                _=try await rpc("still_session",["p_id":item.id.uuidString,"p_action":item.action,"p_archetype":item.archetype,"p_tier":item.tier,"p_seconds":item.seconds])
                queue.remove(at: index); saveQueue()
                if item.action == "finish" || item.action == "end" {
                    registered.removeValue(forKey: item.id.uuidString); UserDefaults.standard.set(registered, forKey: "online.registered")
                }
            } catch {
                status="Online score pending: " + error.localizedDescription
                if retryTask == nil {
                    retryTask = Task { [weak self] in
                        for delay in [3, 10, 30] {
                            try? await Task.sleep(for: .seconds(delay))
                            guard !Task.isCancelled, let self, self.signedIn, !self.queue.isEmpty else { break }
                            await self.drain()
                        }
                        self?.retryTask = nil
                    }
                }
                return
            }
        }
    }
    func signOut() {
        guard !busy, !draining, !reloadInFlight, refreshTask == nil else { status="Please wait for syncing to finish."; return }
        startupRestoreCancelled = true
        reloadGeneration += 1
        retryTask?.cancel(); retryTask=nil
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"session"]
        SecItemDelete(query as CFDictionary); session=nil; signedIn=false; players=[]; friends=[]; expiry = .distantPast; status=nil
    }
}

struct OnlineJoinView: View {
    @ObservedObject var online: OnlineStore
    var accent: Color
    let motion: SurfaceMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
                Image(systemName: "trophy.fill").font(.system(size: 40, weight: .medium)).foregroundStyle(accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                Text("Find your place.").font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("Choose a name. Earn XP. Climb with your friends.").font(.system(size:12)).foregroundStyle(.secondary)
                TextField("Choose a player name",text:$online.handle).textFieldStyle(.roundedBorder)
                Button {online.joinAsGuest()} label: {
                    HStack {Text("Start competing"); Spacer(); Image(systemName: "arrow.right")}
                        .font(.system(size: 14, weight: .semibold)).padding(16).foregroundStyle(.black).background(accent, in: Capsule())
                }.buttonStyle(SharedPressStyle(motion: motion)).disabled(online.busy || !online.guestAvailable)
                if online.googleAvailable {
                    Button("Continue with Google") {online.signInWithGoogle()}.disabled(online.busy)
                }
                Text("Guest progress stays tied to this Mac.").font(.system(size:11)).foregroundStyle(.secondary)
            if online.busy {ProgressView().controlSize(.small)}
            if let status=online.status {Text(status).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
        }.tint(accent).task {await online.checkProviders()}

    }
}
