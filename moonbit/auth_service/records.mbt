///|
pub fn user_value(user : @policy.User) -> @core.Any {
  @core.from_entries([
    ("id", @core.any(user.id)),
    ("name", @core.any(user.name)),
    ("provider", @core.any(user.provider.name())),
  ])
}

///|
pub fn record_value(record : @policy.Record) -> @core.Any {
  match record {
    Flow(flow) =>
      @core.from_entries([
        ("kind", @core.any("flow")),
        ("provider", @core.any(flow.provider.name())),
        ("browserHash", @core.any(flow.browser_hash)),
        ("verifier", @core.any(flow.verifier)),
        ("origin", @core.any(flow.origin)),
        ("returnTo", @core.any(flow.return_to)),
        ("expiresAt", @core.any(flow.expires)),
      ])
    Session(session) =>
      @core.from_entries([
        ("kind", @core.any("session")),
        ("user", user_value(session.user)),
        ("expiresAt", @core.any(session.expires)),
      ])
  }
}

///|
pub fn project_value(project : @policy.Project) -> @core.Any {
  @core.from_entries([
    ("roomId", @core.any(project.room)),
    ("name", @core.any(project.name)),
    ("updatedAt", @core.any(project.updated)),
  ])
}

///|
fn string(value : @core.Any, key : String) -> String? {
  let field = value._get(key)
  if @core.typeof_(field) == "string" {
    Some(field.cast())
  } else {
    None
  }
}

///|
pub fn read_record(value : @core.Any) -> @policy.Record? {
  if @core.is_nullish(value) ||
    @core.typeof_(value) != "object" ||
    @core.typeof_(value._get("expiresAt")) != "number" {
    return None
  }
  let expires : Double = value._get("expiresAt").cast()
  if expires.is_nan() || expires.is_inf() {
    return None
  }
  match string(value, "kind") {
    Some("flow") => {
      guard string(value, "provider").bind(@policy.provider) is Some(provider) &&
        string(value, "browserHash") is Some(browser_hash) &&
        string(value, "verifier") is Some(verifier) &&
        string(value, "origin") is Some(origin) &&
        string(value, "returnTo") is Some(return_to) else {
        return None
      }
      Some(
        @policy.Flow({
          provider,
          browser_hash,
          verifier,
          origin,
          return_to,
          expires,
        }),
      )
    }
    Some("session") => {
      let user = value._get("user")
      guard !@core.is_nullish(user) &&
        @core.typeof_(user) == "object" &&
        string(user, "provider").bind(@policy.provider) is Some(provider) &&
        string(user, "id") is Some(id) &&
        string(user, "name") is Some(name) else {
        return None
      }
      Some(@policy.Session({ user: { id, name, provider, }, expires, }))
    }
    _ => None
  }
}

///|
pub fn read_project(value : @core.Any) -> @policy.Project {
  {
    room: value._get("roomId").cast(),
    name: value._get("name").cast(),
    updated: value._get("updatedAt").cast(),
  }
}
