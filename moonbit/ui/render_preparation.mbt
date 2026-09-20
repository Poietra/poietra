///|
/// Resource preparation depends on text and visible image assets, not poses,
/// colors, animation timing or the identity of the whole immutable Scene.
priv struct RenderPreparation {
  inputs : Array[@core.Any]
}

///|
fn RenderPreparation::same(
  self : RenderPreparation,
  other : RenderPreparation,
) -> Bool {
  same_presentation_inputs(self.inputs, other.inputs)
}

///|
fn render_preparation(scene : @core.Any) -> RenderPreparation {
  let inputs : Array[@core.Any] = []
  if !truthy(scene) {
    return { inputs, }
  }
  let objects = scene._get("objects")
  let compositions = scene._get("compositions")
  let composition_ids = @core.object_keys(compositions)
  for id in @core.object_keys(objects) {
    let object = objects._get(id)
    let kind : String = object._get("kind").cast()
    if kind == "image" {
      let visible = composition_ids
        .iter()
        .any(fn(cid) {
          let state = compositions._get(cid)._get("states")._get(id)
          truthy(state) && truthy(state._get("visible"))
        })
      if visible {
        // Asset records are immutable. Keeping their identity also preserves
        // validation of missing/malformed image metadata by the renderer.
        inputs.append([
          @core.any(kind),
          object._get("image"),
          object._get("name"),
        ])
      }
    } else if kind == "text" || kind == "equation" {
      for cid in composition_ids {
        let state = compositions._get(cid)._get("states")._get(id)
        if truthy(state) {
          inputs.append([@core.any(kind), state._get("text")])
        }
      }
    }
  }
  { inputs, }
}

///|
fn use_render_preparation(scene : @core.Any) -> RenderPreparation {
  let previous = @react.use_ref((None : RenderPreparation?))
  @react.use_memo(
    fn() {
      let next = render_preparation(scene)
      if previous.get_current() is Some(before) && before.same(next) {
        before
      } else {
        previous.set_current(Some(next))
        next
      }
    },
    [scene],
  )
}
