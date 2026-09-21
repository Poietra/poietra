///|
pub fn bounded_utf8_size(text : String, limit : Int) -> Int {
  @project_codec.bounded_utf8_size(text, limit)
}

///|
pub fn parse_project_file(text : String) -> @core.Any {
  @project_codec.parse_project_file(text)
}
