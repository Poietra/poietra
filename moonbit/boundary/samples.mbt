///|
pub fn make_blank_scene(id : String, name : String) -> @core.Any {
  @project_codec.encode_Scene(@scene.blank_scene(id, name))
}

///|
fn encode_project(value : @scene.Project) -> @core.Any {
  @core.from_entries([
    ("version", @core.any(value.version)),
    ("name", @core.any(value.name)),
    ("sceneOrder", @project_codec.encode_array(value.sceneOrder, @core.any)),
    (
      "scenes",
      @project_codec.encode_map(value.scenes, @project_codec.encode_Scene),
    ),
  ])
}

///|
pub fn make_demo_project() -> @core.Any {
  encode_project(@samples.demo_project())
}

///|
pub fn make_calculus_project() -> @core.Any {
  encode_project(@samples.calculus_project())
}
