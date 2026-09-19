///|
/// Deletion is an operation, not a nullable document value.
pub(all) enum Mutation[T] {
  Put(T)
  Remove
}

///|
pub(all) struct Change[T] {
  path : Array[String]
  mutation : Mutation[T]
}

///|
pub(all) struct ResolvedChange[Parent, Value] {
  parent : Parent
  key : String
  mutation : Mutation[Value]
}

///|
pub(all) enum EditError {
  InvalidPath
  MissingParent(Array[String])
}

///|
/// Yjs cannot roll back a transaction. Resolve *all* parents before any write.
/// A later write must still compare its leaf after preceding writes have applied.
pub fn[P, V] resolve_changes(
  changes : Array[Change[V]],
  resolve : (Array[String]) -> P?,
) -> Result[Array[ResolvedChange[P, V]], EditError] {
  let result : Array[ResolvedChange[P, V]] = []
  for change in changes {
    if change.path.is_empty() ||
      change.path.any(fn(key) {
        key == "__proto__" || key == "constructor" || key == "prototype"
      }) {
      return Err(InvalidPath)
    }
    let parent_path = change.path[:change.path.length() - 1].to_owned()
    guard resolve(parent_path) is Some(parent) else {
      return Err(MissingParent(change.path))
    }
    result.push({
      parent,
      key: change.path[change.path.length() - 1],
      mutation: change.mutation,
    })
  }
  Ok(result)
}

///|
/// Leaf edits don't affect automatic track parents. Only structural mutations
/// invalidate the authoritative migration, avoiding a full scan on every cursor edit.
pub fn invalidates_automatic_tracks(
  path : Array[String],
  keys : Array[String],
) -> Bool {
  let changed = fn(key) { keys.contains(key) }
  if path.is_empty() {
    return changed("scenes")
  }
  if path[0] != "scenes" {
    return false
  }
  match path.length() {
    1 => true
    2 => changed("objects") || changed("transitions")
    3 => path[2] == "objects" || path[2] == "transitions"
    4 => path[2] == "transitions" && changed("tracks")
    5 => path[2] == "transitions" && path[4] == "tracks"
    _ => false
  }
}
