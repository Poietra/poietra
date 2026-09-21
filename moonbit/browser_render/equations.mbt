///|
pub fn prepare_equations(
  sources : FixedArray[String],
  load : () -> @core.Promise[@core.Any],
) -> @core.Promise[Unit] {
  @math_render.prepare_equations(sources, load)
}

///|
pub fn get_equation(source : String) -> @core.Any {
  @math_render.get_equation(source)
}
