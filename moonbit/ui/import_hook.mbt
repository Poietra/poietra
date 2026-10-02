///|
fn use_import_controls(input : EditorControls) -> ImportView {
  let image = @react.use_ref((None : @core.Any?))
  let media = @react.use_ref((None : @core.Any?))
  let (importing_image, set_image) = @react.use_state(false)
  let (progress, set_progress) = @react.use_state((None : ImportProgress?))
  let (error, set_error) = @react.use_state("")
  let owner = @react.use_ref((None : ImportSession?))
  let session = match owner.get_current() {
    Some(session) => session
    None => {
      let session : ImportSession = {
        input,
        mounted: false,
        job: None,
        image,
        media,
        image_progress: set_image,
        progress: set_progress,
        error: set_error,
      }
      owner.set_current(Some(session))
      session
    }
  }
  session.input = input
  @react.use_effect(
    fn() {
      session.mounted = true
      session.cancel()
      fn() {
        session.mounted = false
        session.cancel()
      }
    },
    [input.store],
  )
  @react.use_effect(
    fn() {
      for slot in [image, media] {
        if slot.get_current() is Some(request) &&
          (
            !@core.equal(request._get("sceneId"), import_scene_id(input)) ||
            !@core.equal(
              request._get("compositionId"),
              @core.any(input.composition_id),
            ) ||
            input.playing ||
            input.viewing_playback
          ) {
          session.cancel()
          break
        }
      }
      fn() { () }
    },
    [
      import_scene_id(input),
      @core.any(input.composition_id),
      @core.any(input.playing),
      @core.any(input.viewing_playback),
    ],
  )
  {
    image_request: image,
    media_request: media,
    importing_image,
    media_import: progress,
    error,
    set_importing_image: set_image,
    set_error,
    import_images: fn(files, point) { session.start(files, point, true) },
    import_files: fn(files, point) { session.start(files, point, false) },
    cancel: fn() { session.cancel() },
  }
}

///|
pub fn use_editor_imports(input : @core.Any) -> @core.Any {
  native_import_view(use_import_controls(read_native_controls(input)))
}
