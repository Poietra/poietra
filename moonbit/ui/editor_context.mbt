///|
#module("#poietra/ui-host")
extern "js" fn editor_context_runtime() -> @core.Any = "editorContextRuntime"

///|
pub fn use_editor() -> @core.Any {
  let value : @core.Any = @react.use_context(editor_context_runtime().cast())
  if !truthy(value) {
    ui_throw(
      @core.new(@core.global_this()._get("Error"), [
        @core.any("Editor context is missing"),
      ]),
    )
  }
  value
}
