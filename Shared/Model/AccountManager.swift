import Foundation
import Combine
import ValorantAPI
import UserDefault
import HandyOperators
import WidgetKit

@MainActor
final class AccountManager: ObservableObject {
	let keychain: any Keychain
	@Published var multifactorPrompt: MultifactorPrompt?
	
	@Published var activeAccount: StoredAccount? = nil {
		didSet {
			storage.activeAccount = activeAccount?.id
			updateClientVersion()
		}
	}
	
	@Published var storedAccounts: [User.ID] {
		didSet {
			storage.storedAccounts = storedAccounts
		}
	}
	
	@Published var clientVersion: String? {
		didSet {
			storage.clientVersion = clientVersion
			updateClientVersion()
		}
	}
	
	var requiresAction: Bool {
		activeAccount?.session.hasExpired != false
	}
	
	private(set) var accountLoadError: String?
	
	@Published private var storage: Storage
	
	init() {
		self.keychain = .standard
		
		let storage = Storage()
		self.storage = storage // can't use @Published's value before self is initialized, so we'll go this way instead
		
		self.storedAccounts = storage.storedAccounts
		self.clientVersion = storage.clientVersion
		if let accountID = storage.activeAccount {
			do {
				self.activeAccount = try loadAccount(for: accountID)
			} catch {
				print("Could not load active account!")
				print(error.localizedDescription)
				dump(error)
				accountLoadError = error.localizedDescription
			}
		}
	}
	
#if DEBUG
	static let mocked = AccountManager(mockAccounts: [.init()], activeAccount: .mocked)
	static let mockEmpty = AccountManager(mockAccounts: [])
	
	@_disfavoredOverload
	init(mockAccounts: [User.ID] = [], activeAccount: StoredAccount? = nil) {
		self.keychain = MockKeychain()
		self.storage = .init()
		self.activeAccount = activeAccount
		self.storedAccounts = mockAccounts
		if let activeAccount, !self.storedAccounts.contains(activeAccount.id) {
			self.storedAccounts.append(activeAccount.id)
		}
	}
#endif
	
	func loadAccount(for id: User.ID) throws -> StoredAccount {
		try .init(loadingFor: id, using: context)
	}
	
	func addAccount(using credentials: Credentials) async throws {
		let activeSession = activeAccount?.session
		let session = try await APISession(
			credentials: credentials,
			withCookiesFrom: activeSession?.credentials.username == credentials.username ? activeSession : nil,
			multifactorHandler: handleMultifactor(info:)
		)
		if !storedAccounts.contains(session.userID) {
			storedAccounts.append(session.userID)
		}
		activeAccount = try StoredAccount(session: session, context: context)
	}
	
	func toggleActive(_ id: User.ID) throws {
		if activeAccount?.id == id {
			activeAccount = nil
		} else {
			try setActive(id)
		}
	}
	
	func setActive(_ id: User.ID) throws {
		guard activeAccount?.id != id else { return }
		activeAccount = try loadAccount(for: id)
		WidgetCenter.shared.reloadAllTimelines() // some widgets might be based on the active user
	}
	
	func clear() {
		activeAccount = nil
		storedAccounts = []
	}
	
	private var context: StoredAccount.Context {
		.init(keychain: keychain)
	}
	
	func updateClientVersion() {
		guard let clientVersion else { return }
		activeAccount?.setClientVersion(clientVersion)
	}
	
	private struct Storage {
		@UserDefault("AccountManager.activeAccount", migratingTo: .shared)
		var activeAccount: User.ID?
		@UserDefault("AccountManager.storedAccounts", migratingTo: .shared)
		var storedAccounts: [User.ID] = []
		@UserDefault("AccountManager.clientVersion", migratingTo: .shared)
		var clientVersion: String?
	}
	
	func handleMultifactor(info: MultifactorInfo) async throws -> String {
		defer { multifactorPrompt = nil }
		let code = try await withRobustThrowingContinuation { completion in
			// really shouldn't need this but here we are…
			Task {
				await MainActor.run {
					multifactorPrompt = .init(info: info, completion: completion)
				}
			}
		}
		return code
	}
	
	enum MultifactorPromptError: Error, LocalizedError {
		case cancelled
		
		var errorDescription: String? {
			switch self {
			case .cancelled:
				return "Multifactor Prompt Cancelled." // never actually shown to users
			}
		}
	}
}

struct MultifactorPrompt: Identifiable {
	let id = UUID()
	let info: MultifactorInfo
	let completion: (Result<String, Error>) -> Void
}

final class StoredAccount: ObservableObject, Identifiable {
	let context: Context
	
	@Published private(set) var session: APISession {
		didSet { trySave() }
	}
	
	private(set) lazy var client = ValorantClient(session: session) <- {
		sessionUpdateListener = $0.onSessionUpdate { [weak self] session in
			guard let self else { return }
			print("storing updated session")
			self.session = session
		}
	}
	private var sessionUpdateListener: AnyCancellable?
	
	var id: User.ID { session.userID }
	
	var location: Location { session.location }
	
	fileprivate init(session: APISession, context: Context) throws {
		self.context = context
		self.session = session
#if DEBUG
		if context.keychain is MockKeychain { return }
#endif
		try save()
	}
	
	fileprivate init(loadingFor id: User.ID, using context: Context) throws {
		self.context = context
		let stored = try context.keychain.loadData(forKey: id.rawID.description)
		??? LoadingError.noStoredSession
		self.session = try JSONDecoder().decode(APISession.self, from: stored)
	}
	
	func trySave() {
		do {
			try save()
			print("saved account for \(id)")
		} catch {
			print("error saving account for \(id):", error.localizedDescription)
		}
	}
	
	private func save() throws {
		try context.keychain.store(
			try! JSONEncoder().encode(session),
			forKey: id.rawID.description
		)
	}
	
	func setClientVersion(_ version: String) {
		client.clientVersion = version
		trySave()
	}
	
	enum LoadingError: Error, LocalizedError {
		case noStoredSession
		
		var errorDescription: String? {
			switch self {
			case .noStoredSession:
				return String(localized: "Missing session for account!\nIf you have Pro, add an account using the same credentials to replace the account with a working version.", table: "Errors", comment: #"Should not happen anymore, but you never know ¯\_(ツ)_/¯"#)
			}
		}
	}
	
	#if DEBUG
	static let mocked = try! StoredAccount(session: .mocked, context: .init(keychain: MockKeychain()))
	#endif
	
	struct Context {
		var keychain: any Keychain
	}
}

extension ObjectID: DefaultsValueConvertible where RawID: Codable {
	public typealias DefaultsRepresentation = Data // use codable
}
