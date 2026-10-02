///|
fn canvas_settings(controller : InspectorController) -> @react.Element {
  let store = controller.store
  let scene_id = controller.scene_id
  let current = fn() {
    let scene = store._call("project", [])._get("scenes")._get(scene_id)
    if truthy(scene) {
      Some(export_source_size(scene))
    } else {
      None
    }
  }
  let change = fn(width : Double?, height : Double?) {
    if current() is None {
      return
    }
    let patch = @core.new_object()
    if width is Some(width) {
      patch._set("width", @core.any(width))
    }
    if height is Some(height) {
      patch._set("height", @core.any(height))
    }
    store._call("setScene", [@core.any(scene_id), patch]) |> ignore
  }
  typed_component(canvas_settings_component, {
    size: export_source_size(controller.scene),
    change,
    swap: fn() {
      if current() is Some(size) {
        change(Some(size.height), Some(size.width))
      }
    },
  })
}
