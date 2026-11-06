//
//  DailyBriefPalette.swift
//  Dayflow
//
//  Gradients from the Daily Figma file. Avatars and document thumbnails get a
//  random-looking gradient that stays the same for the same name, so a
//  person's avatar doesn't change color between renders.
//

import SwiftUI

struct DailyBriefGradient: Hashable {
  let top: String
  let bottom: String

  var linear: LinearGradient {
    LinearGradient(
      colors: [Color(hex: top), Color(hex: bottom)],
      startPoint: .top,
      endPoint: .bottom
    )
  }
}

enum DailyBriefPalette {
  /// "Avatar gradients" frame: 30 gradients, linear, top to bottom.
  static let avatarGradients: [DailyBriefGradient] = [
    .init(top: "D0FFE3", bottom: "FFDDCD"),  // Mint → Peach
    .init(top: "D8DEFF", bottom: "FFD86D"),  // Periwinkle → Sunflower
    .init(top: "CDF6E2", bottom: "FFE07A"),  // Mint → Yellow
    .init(top: "A5F8E9", bottom: "DFFA9F"),  // Seafoam → Lime
    .init(top: "FFF5BF", bottom: "B5EDCB"),  // Butter → Mint
    .init(top: "FFFDC7", bottom: "95F0F5"),  // Cream → Aqua
    .init(top: "D4F8C0", bottom: "85DDF2"),  // Green → Cyan
    .init(top: "FFCF9C", bottom: "7FD9C8"),  // Orange → Teal
    .init(top: "FFDADF", bottom: "9EF4D9"),  // Blush → Mint
    .init(top: "DDF1FF", bottom: "84EAD8"),  // Ice → Teal
    .init(top: "C4DBFF", bottom: "95E6BE"),  // Sky → Mint
    .init(top: "E5DFF9", bottom: "A4EBF6"),  // Lavender → Aqua
    .init(top: "FFC9E3", bottom: "8FD6FF"),  // Pink → Cyan
    .init(top: "FFC297", bottom: "9EC5FF"),  // Orange → Sky
    .init(top: "FFCA9F", bottom: "A3D3FF"),  // Apricot → Sky
    .init(top: "FFF1B8", bottom: "BAC1FF"),  // Cream → Periwinkle
    .init(top: "D0F4E2", bottom: "CEC3FF"),  // Mint → Lavender
    .init(top: "B0F0FA", bottom: "A6A6FF"),  // Cyan → Indigo
    .init(top: "D2EAFF", bottom: "C2AFFF"),  // Sky → Violet
    .init(top: "B5EEFF", bottom: "F2A6E8"),  // Cyan → Fuchsia
    .init(top: "FFCFB7", bottom: "E5B6FF"),  // Peach → Orchid
    .init(top: "D4DEFF", bottom: "FFAFC8"),  // Periwinkle → Rose
    .init(top: "B8CFFF", bottom: "FFDCD5"),  // Cornflower → Blush
    .init(top: "BFE3FF", bottom: "FFC2A1"),  // Sky → Peach
    .init(top: "D6DCFF", bottom: "FFAD7A"),  // Periwinkle → Orange
    .init(top: "FFD3EA", bottom: "FFC266"),  // Pink → Mango
    .init(top: "FFA777", bottom: "FFE88A"),  // Orange → Lemon
    .init(top: "FFF2B3", bottom: "FFCA6E"),  // Lemon → Mango
    .init(top: "E7FFC6", bottom: "FFBC8C"),  // Pistachio → Apricot
    .init(top: "FFF3C4", bottom: "FFB4A6"),  // Lemon → Coral
  ]

  /// Document thumbnail tints ("Color → neutral" and "Color → color" swatches).
  static let documentTints: [DailyBriefGradient] = [
    .init(top: "FFD6DC", bottom: "FFF4EE"),  // Blush
    .init(top: "ECECEC", bottom: "BFEDE4"),  // Fog → seafoam
    .init(top: "BFD9F2", bottom: "F2F4F7"),  // Glacier
    .init(top: "FFDDC3", bottom: "C3E1FF"),  // Peach → sky
    .init(top: "B7B2F0", bottom: "F3D6DA"),  // Lavender dusk
    .init(top: "DDE8C4", bottom: "FAF8EE"),  // Matcha milk
    .init(top: "ECECEC", bottom: "FFD3D9"),  // Fog → blush
    .init(top: "FFBFB0", bottom: "FFF1E6"),  // Coral mist
    .init(top: "F4C6D0", bottom: "EFE9E4"),  // Rose quartz
    .init(top: "F2B8A0", bottom: "EEE6DD"),  // Terracotta milk
    .init(top: "F6D79A", bottom: "F1ECE2"),  // Honey
    .init(top: "CFE6B8", bottom: "ECEBE5"),  // Pistachio
    .init(top: "B4E4E8", bottom: "ECEDEB"),  // Aqua
    .init(top: "B9D3F5", bottom: "E9E6E1"),  // Powder blue
    .init(top: "BDB4F5", bottom: "ECE8E3"),  // Iris
    .init(top: "E3B9EE", bottom: "EEE8E6"),  // Orchid
    .init(top: "FFC2B4", bottom: "F3EEE8"),  // Melon
    .init(top: "FBEA9E", bottom: "EDEDEA"),  // Lemon chiffon
    .init(top: "B5D6C6", bottom: "E8E2D8"),  // Eucalyptus
    .init(top: "A6BCE0", bottom: "E4E1DC"),  // Denim
    .init(top: "D6B4C8", bottom: "E7E2DC"),  // Mauve
    .init(top: "E0BFA6", bottom: "ECEAE6"),  // Clay
    .init(top: "B3C0F8", bottom: "F2EEE6"),  // Periwinkle → bone
    .init(top: "FFD1B8", bottom: "F6C4E0"),  // Sunset
    .init(top: "FFCCE1", bottom: "C9DDFF"),  // Cotton candy
    .init(top: "BDEBDD", bottom: "BCD3FA"),  // Lagoon
    .init(top: "FFE7A3", bottom: "FFC7B0"),  // Citrus
    .init(top: "D6EDB8", bottom: "FFE6A8"),  // Orchard
    .init(top: "C4C1F7", bottom: "F8C9D6"),  // Twilight
    .init(top: "B8EEDC", bottom: "D4C6F7"),  // Aurora
    .init(top: "F8BFD0", bottom: "FFE2C2"),  // Peony
    .init(top: "B9E5F2", bottom: "E2D4FA"),  // Tide
    .init(top: "FFC4B8", bottom: "FFEFC2"),  // Guava
    .init(top: "FFF1B3", bottom: "C8EBD3"),  // Spring
    .init(top: "C9C8F4", bottom: "BDE3F0"),  // Hydrangea
    .init(top: "FBD3DC", bottom: "E9F1D2"),  // Lychee
    .init(top: "A9CBF6", bottom: "CDEFE4"),  // Marine sky
    .init(top: "DCC0EE", bottom: "FFD8C2"),  // Plum peach
  ]

  static func avatarGradient(for name: String) -> DailyBriefGradient {
    pick(from: avatarGradients, seed: name)
  }

  static func documentTint(for title: String) -> DailyBriefGradient {
    pick(from: documentTints, seed: title)
  }

  /// "JH" for "Jeremy Hong", "M" for "Maggie".
  static func initials(for name: String) -> String {
    let words = name.split(separator: " ").prefix(2)
    return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
  }

  /// A stable pick: Swift's hashValue changes every launch, so use a simple
  /// byte sum instead.
  private static func pick(from gradients: [DailyBriefGradient], seed: String) -> DailyBriefGradient
  {
    let sum = seed.lowercased().utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0x7FFF_FFFF }
    return gradients[sum % gradients.count]
  }
}
