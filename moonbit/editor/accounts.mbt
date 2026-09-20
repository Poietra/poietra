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

///|
pub(all) enum ProjectListOrder {
  RecentlyUpdated
  ProjectName
} derive(Eq)

///|
/// A local view of private shortcuts. Sorting must never mutate the server
/// snapshot or turn a search into a write to the shared document.
pub fn account_project_view(
  projects : Array[AccountProject],
  query : String,
  order : ProjectListOrder,
) -> Array[AccountProject] {
  let query = trim_text(query).to_lower()
  let rows = projects
    .map(fn(project) { (project, project.name.to_lower()) })
    .filter(fn(entry) { query.is_empty() || entry.1.contains(query) })
  rows.sort_by(fn(left, right) {
    let compared = match order {
      RecentlyUpdated => right.0.updated_at.compare(left.0.updated_at)
      ProjectName => left.1.lexical_compare(right.1)
    }
    if compared != 0 {
      compared
    } else {
      left.0.room_id.lexical_compare(right.0.room_id)
    }
  })
  rows.map(fn(entry) { entry.0 })
}
