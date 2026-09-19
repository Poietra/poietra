///|
pub fn asset_kind(value : String) -> AssetKind? {
  match value {
    "images" => Some(Image)
    "media" => Some(Media)
    _ => None
  }
}

///|
pub fn AssetKind::name(self : AssetKind) -> String {
  match self {
    Image => "images"
    Media => "media"
  }
}

///|
pub fn AssetKind::file_limit(self : AssetKind) -> Int {
  match self {
    Image => image_limit
    Media => media_limit
  }
}

///|
pub fn AssetKind::room_limit(self : AssetKind) -> Int {
  match self {
    Image => 67108864
    Media => 134217728
  }
}

///|
pub fn valid_digest(value : String) -> Bool {
  value.length() == 64 &&
  value.iter().all(fn(c) { (c >= 'a' && c <= 'f') || (c >= '0' && c <= '9') })
}

///|
pub(all) struct AssetRoute {
  room : String
  kind : AssetKind
  digest : String?
}

///|
pub fn asset_route(path : String) -> AssetRoute? {
  let parts = path.split("/").map(fn(s) { s.to_owned() }).to_array()
  guard (parts.length() == 5 || parts.length() == 6) &&
    parts[0] == "" &&
    parts[1] == "api" &&
    parts[2] == "rooms" &&
    valid_room(parts[3]) &&
    asset_kind(parts[4]) is Some(kind) else {
    return None
  }
  let digest = if parts.length() == 6 {
    if !valid_digest(parts[5]) {
      return None
    }
    Some(parts[5])
  } else {
    None
  }
  Some({ room: parts[3], kind, digest, })
}

///|
/// Only generated room-scoped UUID v4 keys can be retired by a room.
pub fn storage_key_kind(key : String) -> AssetKind? {
  let parts = key.split("/").map(fn(s) { s.to_owned() }).to_array()
  guard parts.length() == 4 && parts[0] == "rooms" && valid_room(parts[1]) else {
    return None
  }
  let uuid = parts[3]
  guard uuid.length() == 36 &&
    uuid[14:15] == "4" &&
    ["8", "9", "a", "b"].contains(uuid[19:20].to_owned()) else {
    return None
  }
  for index = 0; index < 36; index = index + 1 {
    let c = uuid.code_unit_at(index)
    if [8, 13, 18, 23].contains(index) {
      if c != 45 {
        return None
      }
    } else if !((c >= 97 && c <= 102) || (c >= 48 && c <= 57)) {
      return None
    }
  }
  asset_kind(parts[2])
}
