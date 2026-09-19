///|
fn read_target_transition(value : @core.Any) -> @editor.TargetTransition {
  {
    from_id: string_value(value._get("fromId")),
    to_id: string_value(value._get("toId")),
    object_ids: if truthy(value._get("tracks")) {
      @core.object_keys(value._get("tracks"))
    } else {
      []
    },
  }
}

///|
pub fn read_proposal_targets(
  proposal : @core.Any,
  scene : @core.Any,
) -> Array[@editor.ProposalTarget] {
  let names = fn(values : @core.Any) {
    let result = Map([])
    for key in @core.object_keys(values) {
      result[key] = string_value(values._get(key)._get("name"))
    }
    result
  }
  let transitions = Map([])
  for id in @core.object_keys(scene._get("transitions")) {
    transitions[id] = read_target_transition(scene._get("transitions")._get(id))
  }
  let changes : FixedArray[@core.Any] = proposal._get("changes").cast()
  let writes : Array[@editor.TargetWrite] = []
  for change in changes {
    if !is_array(change._get("path")) {
      continue
    }
    let path : FixedArray[String] = change._get("path").cast()
    let value = change._get("value")
    let object = !@core.is_nullish(value) && @core.typeof_(value) == "object"
    writes.push({
      path: Array::makei(path.length(), fn(i) { path[i] }),
      name: if object && !@core.is_undefined(value._get("name")) {
        Some(string_value(value._get("name")))
      } else {
        None
      },
      transition: if object && path.length() > 2 && path[2] == "transitions" {
        Some(read_target_transition(value))
      } else {
        None
      },
    })
  }
  @editor.proposal_targets(writes, {
    id: scene._get("id").cast(),
    objects: names(scene._get("objects")),
    compositions: names(scene._get("compositions")),
    transitions,
  })
}

///|
pub fn proposal_targets(
  proposal : @core.Any,
  scene : @core.Any,
) -> FixedArray[@core.Any] {
  let targets = read_proposal_targets(proposal, scene)
  FixedArray::makei(targets.length(), fn(i) {
    let target = targets[i]
    let result = @core.from_entries([
      ("selection", write_chat_selection(target.selection)),
      (
        "objectIds",
        @core.any(
          FixedArray::makei(target.object_ids.length(), fn(i) {
            target.object_ids[i]
          }),
        ),
      ),
      ("label", @core.any(target.label)),
    ])
    if target.created {
      result._set("created", @core.any(true))
    }
    result
  })
}
