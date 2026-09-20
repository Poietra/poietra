///|
/// A view keeps its props while the values it displays stay unchanged. The
/// Context adapter still observes every edit; expensive panel content does not.
priv struct PresentationProps {
  inputs : Array[@core.Any]
  props : @core.Any
}

///|
fn same_presentation_inputs(a : Array[@core.Any], b : Array[@core.Any]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for index, value in a {
    if !@core.equal(value, b[index]) {
      return false
    }
  }
  true
}

///|
fn use_presentation_props(
  inputs : Array[@core.Any],
  props : () -> @core.Any,
) -> @core.Any {
  let previous = @react.use_ref((None : PresentationProps?))
  if previous.get_current() is Some(before) &&
    same_presentation_inputs(before.inputs, inputs) {
    before.props
  } else {
    let next = { inputs, props: props(), }
    previous.set_current(Some(next))
    next.props
  }
}

///|
/// Event handlers always call the latest owner even if its view stayed cached.
fn use_latest_action(action : @core.Any) -> @core.Any {
  let current = @react.use_ref(Some(action))
  current.set_current(Some(action))
  @react.use_memo(
    fn() {
      @core.any(fn(value : @core.Any) {
        current.get_current().unwrap()._invoke([value]) |> ignore
      })
    },
    [],
  )
}

///|
fn editor_presentation_inputs(editor : @core.Any) -> Array[@core.Any] {
  let inputs = [editor._get("scene")._get("id")]
  for
    key in [
      "store", "compositionId", "playing", "viewingPlayback", "select", "notify",
      "setSelectedIds", "appendComposition", "seek", "play", "previous", "next",
    ] {
    inputs.push(editor._get(key))
  }
  let selection = editor._get("selection")
  inputs.append([selection._get("kind"), selection._get("id")])
  let selected : FixedArray[String] = editor._get("selectedIds").cast()
  inputs.push(@core.any(selected.length()))
  for id in selected {
    inputs.push(@core.any(id))
  }
  inputs
}

///|
fn composition_presentation_inputs(
  scene : @core.Any,
  timing : Bool,
) -> Array[@core.Any] {
  let order : FixedArray[String] = scene._get("compositionOrder").cast()
  let inputs = [@core.any(order.length())]
  for id in order {
    let composition = scene._get("compositions")._get(id)
    inputs.append([@core.any(id), composition._get("name")])
    if timing {
      inputs.append([composition._get("duration"), composition._get("accent")])
    }
  }
  inputs
}
