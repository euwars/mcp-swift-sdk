import class Foundation.JSONDecoder
import class Foundation.JSONEncoder

/// An error indicating a type mismatch when decoding a pending request response.
struct TypeMismatchError: Swift.Error {}

/// A pending request with a continuation for the result.
struct PendingRequest<T> {
    let continuation: CheckedContinuation<T, Swift.Error>
}

/// A type-erased pending request.
struct AnyPendingRequest: Sendable {
    private let _resume: @Sendable (Result<Any, Swift.Error>) -> Void

    init<T: Sendable & Decodable>(_ request: PendingRequest<T>) {
        _resume = { result in
            switch result {
            case .success(let value):
                if let typedValue = value as? T {
                    request.continuation.resume(returning: typedValue)
                } else if let value = value as? Value,
                    let data = try? JSONEncoder().encode(value)
                {
                    do {
                        request.continuation.resume(returning: try JSONDecoder().decode(T.self, from: data))
                    } catch {
                        request.continuation.resume(
                            throwing: MCPError.parseError("the answer does not read as \(T.self): \(Self.reason(error))"))
                    }
                } else {
                    request.continuation.resume(throwing: TypeMismatchError())
                }
            case .failure(let error):
                request.continuation.resume(throwing: error)
            }
        }
    }

    /// A decoding error in one short line: the field that is missing or wrong.
    private static func reason(_ error: Swift.Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, _):
            return "\(key.stringValue) is missing"
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context),
            DecodingError.dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        default:
            return "\(error)"
        }
    }

    func resume(returning value: Any) {
        _resume(.success(value))
    }

    func resume(throwing error: Swift.Error) {
        _resume(.failure(error))
    }
}
