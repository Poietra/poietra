///|
pub(all) enum Provider {
  Google
  GitHub
} derive(Eq)

///|
pub fn provider(value : String) -> Provider? {
  match value {
    "google" => Some(Google)
    "github" => Some(GitHub)
    _ => None
  }
}

///|
pub fn Provider::name(self : Provider) -> String {
  match self {
    Google => "google"
    GitHub => "github"
  }
}

///|
pub fn Provider::authorize(self : Provider) -> String {
  match self {
    Google => "https://accounts.google.com/o/oauth2/v2/auth"
    GitHub => "https://github.com/login/oauth/authorize"
  }
}

///|
pub fn Provider::token_url(self : Provider) -> String {
  match self {
    Google => "https://oauth2.googleapis.com/token"
    GitHub => "https://github.com/login/oauth/access_token"
  }
}

///|
pub fn Provider::user_url(self : Provider) -> String {
  match self {
    Google => "https://openidconnect.googleapis.com/v1/userinfo"
    GitHub => "https://api.github.com/user"
  }
}

///|
pub fn Provider::scope(self : Provider) -> String {
  match self {
    Google => "openid profile"
    GitHub => "read:user"
  }
}

///|
pub(all) struct User {
  id : String
  name : String
  provider : Provider
}

///|
pub(all) struct Project {
  room : String
  name : String
  updated : Double
}

///|
/// A personal shortcut, never ownership of the shared room. A dismissal is
/// retained so automatic visits cannot undo the user's removal on another device.
pub(all) enum LibraryEntry {
  Listed(Project)
  Dismissed(String)
}

///|
pub fn LibraryEntry::room(self : LibraryEntry) -> String {
  match self {
    Listed(project) => project.room
    Dismissed(room) => room
  }
}

///|
pub(all) struct Flow {
  provider : Provider
  browser_hash : String
  verifier : String
  origin : String
  return_to : String
  expires : Double
}

///|
pub(all) struct Session {
  user : User
  expires : Double
}

///|
pub(all) enum Record {
  Flow(Flow)
  Session(Session)
}

///|
pub fn Record::expires(self : Record) -> Double {
  match self {
    Flow(value) => value.expires
    Session(value) => value.expires
  }
}

///|
pub let flow_ttl : Double = 600000.0

///|
pub let session_ttl : Double = 604800000.0

///|
pub let project_limit : Int = 500

///|
pub fn valid_token(token : String) -> Bool {
  token.length() == 43 &&
  token
  .iter()
  .all(fn(c) {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_' ||
    c == '-'
  })
}

///|
pub fn is_auth_path(path : String) -> Bool {
  path.has_prefix("/api/auth/") ||
  path == "/api/projects" ||
  path.has_prefix("/api/projects/")
}

///|
pub fn cookie_name(secure : Bool, kind : String) -> String {
  (if secure { "__Host-" } else { "" }) + "poietra_" + kind
}

///|
pub fn cookie(
  secure : Bool,
  kind : String,
  value : String,
  max_age : Int,
) -> String {
  cookie_name(secure, kind) +
  "=" +
  value +
  "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" +
  max_age.to_string() +
  (if secure { "; Secure" } else { "" })
}

///|
pub fn read_cookie(header : String, name : String) -> String? {
  let prefix = name + "="
  let mut result = None
  let mut found = false
  for part in header.split(";") {
    let part = @editor.trim_text(part.to_owned())
    if part.has_prefix(prefix) {
      if found {
        return None
      }
      found = true
      let token = part[prefix.length():].to_owned()
      if valid_token(token) {
        result = Some(token)
      }
    }
  }
  result
}

///|
pub fn safe_return_input(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 2048 &&
  value.has_prefix("/") &&
  !value.has_prefix("//") &&
  value.iter().all(fn(c) { c != '\\' && c.to_int() > 32 && c.to_int() != 127 })
}

///|
pub fn safe_decoded_return(value : String) -> Bool {
  value.iter().all(fn(c) { c != '\\' && c.to_int() >= 32 && c.to_int() != 127 })
}

///|
pub fn user_name(raw : String, provider : Provider) -> String {
  let text = StringBuilder()
  for c in raw.iter() {
    if c.to_int() >= 32 && c.to_int() != 127 {
      text.write_char(c)
    }
  }
  let clean = @editor.trim_text(text.to_string()).to_owned()
  let name = clean[:clean.length().min(120)].to_owned()
  if name.is_empty() {
    provider.name() + " user"
  } else {
    name
  }
}
