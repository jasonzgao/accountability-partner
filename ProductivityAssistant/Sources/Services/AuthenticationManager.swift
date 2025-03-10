import Foundation
import Security
import Combine
import os.log

/// Protocol for managing authentication and credentials
protocol AuthenticationManagerProtocol {
    /// Stores a credential securely
    func storeCredential(_ credential: String, for service: String, account: String) -> AnyPublisher<Bool, Error>
    
    /// Retrieves a credential
    func getCredential(for service: String, account: String) -> AnyPublisher<String?, Error>
    
    /// Deletes a credential
    func deleteCredential(for service: String, account: String) -> AnyPublisher<Bool, Error>
    
    /// Stores an API key securely
    func storeAPIKey(_ apiKey: String, for service: String) -> AnyPublisher<Bool, Error>
    
    /// Retrieves an API key
    func getAPIKey(for service: String) -> AnyPublisher<String?, Error>
    
    /// Deletes an API key
    func deleteAPIKey(for service: String) -> AnyPublisher<Bool, Error>
    
    /// Stores OAuth tokens securely
    func storeOAuthTokens(accessToken: String, refreshToken: String?, expiresAt: Date?, for service: String) -> AnyPublisher<Bool, Error>
    
    /// Retrieves OAuth tokens
    func getOAuthTokens(for service: String) -> AnyPublisher<OAuthTokens?, Error>
    
    /// Refreshes an OAuth token if needed
    func refreshOAuthTokenIfNeeded(for service: String) -> AnyPublisher<OAuthTokens?, Error>
}

/// Represents OAuth tokens
struct OAuthTokens: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        // Consider token expired 5 minutes before actual expiration
        return Date().addingTimeInterval(5 * 60) > expiresAt
    }
}

/// Error types for authentication operations
enum AuthenticationError: Error {
    case keychainError(OSStatus)
    case dataConversionError
    case noCredentialFound
    case refreshFailed
    case unknown
    
    var localizedDescription: String {
        switch self {
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .dataConversionError:
            return "Failed to convert data"
        case .noCredentialFound:
            return "No credential found"
        case .refreshFailed:
            return "Failed to refresh token"
        case .unknown:
            return "An unknown authentication error occurred"
        }
    }
}

/// Implementation of AuthenticationManager using Keychain
final class KeychainAuthenticationManager: AuthenticationManagerProtocol {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.productivityassistant", category: "Authentication")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Initialization
    
    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Public Methods
    
    func storeCredential(_ credential: String, for service: String, account: String) -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(AuthenticationError.unknown))
                return
            }
            
            // Convert string to data
            guard let credentialData = credential.data(using: .utf8) else {
                self.logger.error("Failed to convert credential to data")
                promise(.failure(AuthenticationError.dataConversionError))
                return
            }
            
            // Create query dictionary
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: credentialData
            ]
            
            // Delete any existing credential
            SecItemDelete(query as CFDictionary)
            
            // Add the new credential
            let status = SecItemAdd(query as CFDictionary, nil)
            
            if status == errSecSuccess {
                self.logger.info("Successfully stored credential for \(service)/\(account)")
                promise(.success(true))
            } else {
                self.logger.error("Failed to store credential: \(status)")
                promise(.failure(AuthenticationError.keychainError(status)))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getCredential(for service: String, account: String) -> AnyPublisher<String?, Error> {
        return Future<String?, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(AuthenticationError.unknown))
                return
            }
            
            // Create query dictionary
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            
            // Search for the credential
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            
            if status == errSecSuccess, let data = item as? Data, let credential = String(data: data, encoding: .utf8) {
                self.logger.debug("Successfully retrieved credential for \(service)/\(account)")
                promise(.success(credential))
            } else if status == errSecItemNotFound {
                self.logger.debug("No credential found for \(service)/\(account)")
                promise(.success(nil))
            } else {
                self.logger.error("Failed to retrieve credential: \(status)")
                promise(.failure(AuthenticationError.keychainError(status)))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func deleteCredential(for service: String, account: String) -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(AuthenticationError.unknown))
                return
            }
            
            // Create query dictionary
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            
            // Delete the credential
            let status = SecItemDelete(query as CFDictionary)
            
            if status == errSecSuccess || status == errSecItemNotFound {
                self.logger.info("Successfully deleted credential for \(service)/\(account)")
                promise(.success(true))
            } else {
                self.logger.error("Failed to delete credential: \(status)")
                promise(.failure(AuthenticationError.keychainError(status)))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func storeAPIKey(_ apiKey: String, for service: String) -> AnyPublisher<Bool, Error> {
        return storeCredential(apiKey, for: service, account: "apikey")
    }
    
    func getAPIKey(for service: String) -> AnyPublisher<String?, Error> {
        return getCredential(for: service, account: "apikey")
    }
    
    func deleteAPIKey(for service: String) -> AnyPublisher<Bool, Error> {
        return deleteCredential(for: service, account: "apikey")
    }
    
    func storeOAuthTokens(accessToken: String, refreshToken: String?, expiresAt: Date?, for service: String) -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(AuthenticationError.unknown))
                return
            }
            
            // Create tokens object
            let tokens = OAuthTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt
            )
            
            // Convert to JSON data
            do {
                let tokensData = try self.encoder.encode(tokens)
                
                // Create query dictionary
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: "oauth",
                    kSecValueData as String: tokensData
                ]
                
                // Delete any existing tokens
                SecItemDelete(query as CFDictionary)
                
                // Add the new tokens
                let status = SecItemAdd(query as CFDictionary, nil)
                
                if status == errSecSuccess {
                    self.logger.info("Successfully stored OAuth tokens for \(service)")
                    promise(.success(true))
                } else {
                    self.logger.error("Failed to store OAuth tokens: \(status)")
                    promise(.failure(AuthenticationError.keychainError(status)))
                }
            } catch {
                self.logger.error("Failed to encode OAuth tokens: \(error.localizedDescription)")
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getOAuthTokens(for service: String) -> AnyPublisher<OAuthTokens?, Error> {
        return Future<OAuthTokens?, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(AuthenticationError.unknown))
                return
            }
            
            // Create query dictionary
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "oauth",
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            
            // Search for the tokens
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            
            if status == errSecSuccess, let data = item as? Data {
                do {
                    let tokens = try self.decoder.decode(OAuthTokens.self, from: data)
                    self.logger.debug("Successfully retrieved OAuth tokens for \(service)")
                    promise(.success(tokens))
                } catch {
                    self.logger.error("Failed to decode OAuth tokens: \(error.localizedDescription)")
                    promise(.failure(error))
                }
            } else if status == errSecItemNotFound {
                self.logger.debug("No OAuth tokens found for \(service)")
                promise(.success(nil))
            } else {
                self.logger.error("Failed to retrieve OAuth tokens: \(status)")
                promise(.failure(AuthenticationError.keychainError(status)))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func refreshOAuthTokenIfNeeded(for service: String) -> AnyPublisher<OAuthTokens?, Error> {
        return getOAuthTokens(for: service)
            .flatMap { [weak self] tokens -> AnyPublisher<OAuthTokens?, Error> in
                guard let self = self else {
                    return Fail(error: AuthenticationError.unknown).eraseToAnyPublisher()
                }
                
                guard let tokens = tokens else {
                    return Just(nil).setFailureType(to: Error.self).eraseToAnyPublisher()
                }
                
                // If token is not expired, return it
                if !tokens.isExpired {
                    return Just(tokens).setFailureType(to: Error.self).eraseToAnyPublisher()
                }
                
                // If token is expired but no refresh token, return nil
                guard let refreshToken = tokens.refreshToken else {
                    self.logger.warning("OAuth token expired but no refresh token available for \(service)")
                    return Just(nil).setFailureType(to: Error.self).eraseToAnyPublisher()
                }
                
                // Implement token refresh logic here
                // This would typically involve making a network request to the OAuth provider
                // For now, we'll just return a failure
                self.logger.warning("Token refresh not implemented for \(service)")
                return Fail(error: AuthenticationError.refreshFailed).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
} 