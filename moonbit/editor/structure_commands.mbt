///|
pub(all) enum StructureKind {
  SceneList
  CompositionList
}

///|
pub(all) enum StructureCreationError {
  SceneLimit
  CompositionLimit
  EmptyPalette
} derive(Eq, Debug)

///|
pub fn check_structure_capacity(
  kind : StructureKind,
  count : Int,
) -> Result[Unit, StructureCreationError] {
  if count < 100 {
    Ok(())
  } else {
    Err(
      match kind {
        SceneList => SceneLimit
        CompositionList => CompositionLimit
      },
    )
  }
}

///|
pub(all) struct SceneAppend {
  value : @scene.Scene
  retained_id : String?
}

///|
pub fn plan_scene_append(
  order : Array[String],
  allocate : (String) -> String,
) -> Result[SceneAppend, StructureCreationError] {
  if check_structure_capacity(SceneList, order.length()) is Err(error) {
    return Err(error)
  }
  let id = allocate("scene")
  Ok({
    value: @scene.blank_scene(id, "Scene " + (order.length() + 1).to_string()),
    retained_id: order.get(0),
  })
}

///|
/// State payloads stay in the immutable snapshot until the host copies them to
/// fresh shared maps. Planning needs only the source identity and object IDs.
pub(all) struct CompositionAppend {
  value : @scene.Composition
  source_id : String?
  incoming : @scene.Transition?
}

///|
pub fn plan_composition_append(
  count : Int,
  source_id : String?,
  objects : Array[String],
  palette : Array[String],
  allocate : (String) -> String,
) -> Result[CompositionAppend, StructureCreationError] {
  if check_structure_capacity(CompositionList, count) is Err(error) {
    return Err(error)
  }
  if palette.is_empty() {
    return Err(EmptyPalette)
  }
  let id = allocate("comp")
  let tid = allocate("transition")
  Ok({
    value: @scene.empty_composition(
      id,
      "Composition " + (count + 1).to_string(),
      1000.0,
      palette[count % palette.length()],
    ),
    source_id,
    incoming: source_id.map(fn(from_id) {
      @scene.implicit_transition(tid, from_id, id, 800.0, objects)
    }),
  })
}
