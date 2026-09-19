///|
priv struct GuardedWrite {
  path : Array[String]
  value : @core.Any
  parent : @core.Any
}

///|
priv struct CompositionAppend {
  ids : Array[String]
  order : @core.Any
}

///|
priv struct ValidatedProposal {
  changes : Array[GuardedWrite]
  appends : Array[CompositionAppend]
}

///|
fn check_guard(
  doc : @core.Any,
  condition : @core.Any,
  yjs : @core.Any,
) -> Array[String] {
  let path = string_array(condition._get("path"))
  if !valid_path(path) {
    return fail("編集案に無効な対象が含まれています。")
  }
  let current = value(doc, path, yjs)
  let identity = condition._get("parentIdentity")
  let existed = condition._get("existed")
  if (
      !@core.is_undefined(identity) &&
      !same_identity(parent_identity(doc, path, yjs), identity)
    ) ||
    !same_identity(@core.any(!@core.is_undefined(current)), existed) ||
    (truthy(existed) && !same_value(current, condition._get("expected"))) {
    return fail(
      "提案後に対象が変更されました。今の状態でもう一度依頼してください。",
    )
  }
  path
}

///|
fn read_appends(
  doc : @core.Any,
  project : @core.Any,
  input : @core.Any,
  changes : Array[GuardedWrite],
  originals : FixedArray[@core.Any],
  yjs : @core.Any,
) -> Array[CompositionAppend] {
  let result = []
  if !@core.is_nullish(input) &&
    (!is_array(input) || (input._get("length").cast() : Int) > 1) {
    return fail("Composition の追加順序が無効です。")
  }
  let entries : FixedArray[@core.Any] = if @core.is_nullish(input) {
    []
  } else {
    input.cast()
  }
  let indexed : Map[String, Int] = Map([])
  for index, change in changes {
    let key = path_key(change.path)
    if !indexed.contains(key) {
      indexed[key] = index
    }
  }
  let appended_paths : Set[String] = Set([])
  let incoming_paths : Set[String] = Set([])
  for entry in entries {
    if @core.is_nullish(entry) ||
      @core.typeof_(entry) != "object" ||
      @core.object_keys(entry)
      .iter()
      .any(fn(key) {
        key != "sceneId" && key != "compositionIds" && key != "orderIdentity"
      }) ||
      @core.typeof_(entry._get("sceneId")) != "string" ||
      @core.typeof_(entry._get("orderIdentity")) != "string" {
      return fail("Composition の追加順序が無効です。")
    }
    let scene_id : String = entry._get("sceneId").cast()
    let ids = string_array(entry._get("compositionIds"))
    if ids.is_empty() || ids.length() > 4 {
      return fail("Composition の追加順序が無効です。")
    }
    let scene = if @core.is_nullish(project) {
      @core.undefined()
    } else {
      project._get("scenes")._get(scene_id)
    }
    let order = shared(doc, ["scenes", scene_id, "compositionOrder"], yjs)
    if !truthy(scene) ||
      !instance_of(order, yjs._get("Array")) ||
      !same_identity(
        @core.any(array_identity(order, yjs)),
        entry._get("orderIdentity"),
      ) {
      return fail(
        "提案後に Composition の順序が変更されました。今の状態でもう一度依頼してください。",
      )
    }
    let current = string_array(scene._get("compositionOrder"))
    let unique : Set[String] = Set([])
    for id in ids {
      unique.add(id)
    }
    if unique.length() != ids.length() || current.length() + ids.length() > 100 {
      return fail("Composition の追加順序が無効です。")
    }
    let mut previous = if current.is_empty() {
      @core.undefined()
    } else {
      @core.any(current[current.length() - 1])
    }
    for id in ids {
      let path = ["scenes", scene_id, "compositions", id]
      let index = match indexed.get(path_key(path)) {
        Some(index) => index
        None => return fail("追加する Composition が無効です。")
      }
      let composition = changes[index].value
      if !valid_path(path) ||
        truthy(originals[index]._get("existed")) ||
        !truthy(composition) ||
        !same_identity(composition._get("id"), @core.any(id)) ||
        truthy(composition._get("deleted")) ||
        !truthy(composition._get("incomingTransitionId")) {
        return fail("追加する Composition が無効です。")
      }
      valid_duration(composition._get("duration")) |> ignore
      let transition_id : String = composition
        ._get("incomingTransitionId")
        .cast()
      let transition_path = ["scenes", scene_id, "transitions", transition_id]
      let transition_key = path_key(transition_path)
      let index = match indexed.get(transition_key) {
        Some(index) => index
        None =>
          return fail("追加する Transition の参照が無効です。")
      }
      let transition = changes[index].value
      if truthy(originals[index]._get("existed")) ||
        !truthy(transition) ||
        !same_identity(transition._get("id"), @core.any(transition_id)) ||
        !same_identity(transition._get("fromId"), previous) ||
        !same_identity(transition._get("toId"), @core.any(id)) ||
        incoming_paths.contains(transition_key) {
        return fail("追加する Transition の参照が無効です。")
      }
      appended_paths.add(path_key(path))
      incoming_paths.add(transition_key)
      previous = @core.any(id)
    }
    result.push({ ids, order, })
  }
  for change in changes {
    let path = change.path
    if path.length() == 4 && path[0] == "scenes" {
      if path[2] == "compositions" && !appended_paths.contains(path_key(path)) {
        return fail("Composition の追加情報が見つかりません。")
      }
      if path[2] == "transitions" && !incoming_paths.contains(path_key(path)) {
        return fail("Transition の追加情報が見つかりません。")
      }
    }
  }
  result
}

///|
fn validate(
  doc : @core.Any,
  proposal : @core.Any,
  yjs : @core.Any,
) -> ValidatedProposal {
  let inputs : FixedArray[@core.Any] = proposal._get("changes").cast()
  let paths = inputs
    .iter()
    .map(fn(input) { check_guard(doc, input, yjs) })
    .to_array()
  let targets : Set[String] = Set([])
  for path in paths {
    targets.add(path_key(path))
  }
  for path in paths {
    for length in 1..<path.length() {
      // Resolved native parents belong to the current document. Replacing one
      // and then writing below it would update a detached map, not the new map.
      if targets.contains(path_key(path[:length].to_owned())) {
        return fail(
          "親と子への編集が重複しています。編集案を作り直してください。",
        )
      }
    }
  }
  let guards = proposal._get("guards")
  if !@core.is_nullish(guards) {
    for condition in (guards.cast() : FixedArray[@core.Any]) {
      check_guard(doc, condition, yjs) |> ignore
    }
  }
  let project = @boundary.read_project(doc, yjs)
  let changes = []
  for index, path in paths {
    if path[0] == "scenes" &&
      (
        @core.is_nullish(project) ||
        path.length() < 2 ||
        !truthy(project._get("scenes")._get(path[1]))
      ) {
      return fail(
        "編集対象の Scene が削除されています。今の状態でもう一度依頼してください。",
      )
    }
    let parent = shared(doc, path[:path.length() - 1].to_owned(), yjs)
    if !instance_of(parent, yjs._get("Map")) {
      return fail(
        "編集対象が削除されています。今の状態でもう一度依頼してください。",
      )
    }
    if path.length() > 2 && path[2] == "compositionOrder" {
      return fail(
        "Composition の順序は既存の配列へ追加してください。",
      )
    }
    changes.push({ path, value: inputs[index]._get("value"), parent, })
  }
  let appends = read_appends(
    doc,
    project,
    proposal._get("compositionAppends"),
    changes,
    inputs,
    yjs,
  )
  check_projected_timing(doc, changes, yjs)
  { changes, appends, }
}
