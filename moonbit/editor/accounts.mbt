///|
pub(all) enum AuthProvider {
  Google
  GitHub
} derive(Eq)

///|
pub(all) struct AccountUser {
  id : String
  name : String
  provider : AuthProvider
}

///|
pub(all) struct AccountSession {
  user : AccountUser?
  google : Bool
  github : Bool
}

///|
pub(all) struct AccountProject {
  room_id : String
  name : String
  updated_at : Double
}

///|
pub(all) struct AccountRoom {
  account : String
  room : String
} derive(Eq)

///|
pub(all) struct AccountSave {
  account : String
  room : String
  name : String
} derive(Eq)

///|
pub(all) enum AccountOperation {
  VisitProject(String, String)
  RememberProject(String, String)
  RemoveProject(String)
  SignOut
}

///|
pub fn account_operation_key(operation : AccountOperation) -> String {
  match operation {
    VisitProject(_, _) | RememberProject(_, _) => "save"
    RemoveProject(id) => "remove:" + id
    SignOut => "logout"
  }
}

///|
pub fn auth_provider_name(provider : AuthProvider) -> String {
  match provider {
    Google => "google"
    GitHub => "github"
  }
}
