///|
/// A view keeps its props while the values it displays stay unchanged. The
/// Context adapter still observes every edit; expensive panel content does not.
priv struct PresentationProps[T] {
  inputs : Array[@core.Any]
  props : T
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
fn[T] use_presentation_props(inputs : Array[@core.Any], props : () -> T) -> T {
  let previous = @react.use_ref((None : PresentationProps[T]?))
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
fn[T] use_latest_callback(action : (T) -> Unit) -> (T) -> Unit {
  let current = @react.use_ref(Some(action))
  current.set_current(Some(action))
  @react.use_memo(
    fn() { fn(value) { current.get_current().unwrap()(value) } },
    [],
  )
}

///|
fn use_latest_procedure(action : () -> Unit) -> () -> Unit {
  let current = @react.use_ref(Some(action))
  current.set_current(Some(action))
  @react.use_memo(fn() { fn() { current.get_current().unwrap()() } }, [])
}

///|
fn editor_presentation_inputs(editor : EditorView) -> Array[@core.Any] {
  let inputs = [
    editor.scene._get("id"),
    editor.store,
    @core.any(editor.composition_id),
    @core.any(editor.playing),
    @core.any(editor.viewing_playback),
    @core.any(editor.actions),
  ]
  let selection = editor.selection
  inputs.append([
    @core.any(selection is TransitionSelection(_)),
    @core.any(selection.id()),
  ])
  let selected : FixedArray[String] = editor.selected_ids
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
