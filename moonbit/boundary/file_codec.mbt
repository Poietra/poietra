///|
pub fn read_keyframe(value : @core.Any) -> @scene.Keyframe {
  @project_codec.read_keyframe(value)
}

///|
pub fn write_keyframe(value : @scene.Keyframe) -> @core.Any {
  @project_codec.write_keyframe(value)
}

///|
pub fn validate_keyframe(value : @core.Any) -> Unit {
  @project_codec.validate_keyframe(value)
}

///|
pub fn valid_document_id(value : String) -> Bool {
  @project_codec.valid_document_id(value)
}
