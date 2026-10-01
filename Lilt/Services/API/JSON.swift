import Foundation

/// Tiny helpers for walking untyped InnerTube JSON.
enum JSON {
    static func dict(_ any: Any?) -> [String: Any]? { any as? [String: Any] }
    static func array(_ any: Any?) -> [Any]? { any as? [Any] }
    static func string(_ any: Any?) -> String? { any as? String }

    /// Follows a path of `String` keys and `Int` indices.
    static func value(at path: [Any], in root: Any?) -> Any? {
        var current = root
        for step in path {
            switch step {
            case let key as String:
                current = dict(current)?[key]
            case let index as Int:
                guard let arr = array(current), arr.indices.contains(index) else { return nil }
                current = arr[index]
            default:
                return nil
            }
            if current == nil { return nil }
        }
        return current
    }

    /// Depth-first collection of every dictionary stored under `key`, in document order.
    static func findAll(key: String, in root: Any) -> [[String: Any]] {
        var found: [[String: Any]] = []
        func walk(_ node: Any) {
            if let d = dict(node) {
                for (k, v) in d {
                    if k == key, let match = dict(v) { found.append(match) }
                    walk(v)
                }
            } else if let a = array(node) {
                a.forEach(walk)
            }
        }
        walk(root)
        return found
    }
}
