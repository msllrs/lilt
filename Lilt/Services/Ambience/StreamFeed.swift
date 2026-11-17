import Foundation

/// The feeds the drawer offers, so a listener can pick an airport rather than find a mount: a
/// handful of busy ones, each the mount itself. The field beside the list still takes any URL.
enum StreamFeed: String, CaseIterable, Identifiable {
    case tokyoHaneda, tokyoNarita, jfk, sanFrancisco, atlanta, losAngeles, hongKong

    var id: String { rawValue }

    var name: String {
        switch self {
        case .tokyoHaneda: "Tokyo Haneda"
        case .tokyoNarita: "Tokyo Narita"
        case .jfk: "New York JFK"
        case .sanFrancisco: "San Francisco"
        case .atlanta: "Atlanta"
        case .losAngeles: "Los Angeles"
        case .hongKong: "Hong Kong"
        }
    }

    /// The LiveATC mount behind the feed, on the stream host that serves mounts directly.
    var mount: String {
        switch self {
        case .tokyoHaneda: "rjtt_app"
        case .tokyoNarita: "rjaa_twr"
        case .jfk: "kjfk9_twr"
        case .sanFrancisco: "ksfo_twr"
        case .atlanta: "katl_twr"
        case .losAngeles: "klax_twr"
        case .hongKong: "vhhh5"
        }
    }

    /// What the field shows after a pick: the address `StreamAddress` takes as it is.
    var url: String { "https://d.liveatc.net/\(mount)" }
}
