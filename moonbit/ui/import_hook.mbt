///|
pub fn use_editor_imports(input : @core.Any) -> @core.Any {
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
    [input._get("store")],
  )
  @react.use_effect(
    fn() {
      for slot in [image, media] {
        if slot.get_current() is Some(request) &&
          (
            !@core.equal(request._get("sceneId"), import_scene_id(input)) ||
            !@core.equal(
              request._get("compositionId"),
              input._get("compositionId"),
            ) ||
            truthy(input._get("playing")) ||
            truthy(input._get("transportView"))
          ) {
          session.cancel()
          break
        }
      }
      fn() { () }
    },
    [
      import_scene_id(input),
      input._get("compositionId"),
      input._get("playing"),
      input._get("transportView"),
    ],
  )
  let import_files = fn(files : FixedArray[@core.Any], point : @core.Any) {
    session.start(files, point, false)
  }
  host_record({
    "imageRequest": image.as_any(),
    "mediaRequest": media.as_any(),
    "importingImage": @core.any(importing_image),
    "setImportingImage": @core.any(set_image),
    "importError": @core.any(error),
    "setImportError": @core.any(set_error),
    "mediaImport": match progress {
      None => @core.null()
      Some(progress) =>
        host_record({
          "name": @core.any(progress.name),
          "index": @core.any(progress.index),
          "count": @core.any(progress.count),
          "progress": @core.any(progress.progress),
          "phase": @core.any(
            match progress.phase {
              ReadAsset => "reading"
              ReadWaveform => "waveform"
              TransferAsset => "uploading"
              SaveAsset => "saving"
            },
          ),
        })
    },
    "importImages": @core.any(fn(
      files : FixedArray[@core.Any],
      point : @core.Any,
    ) {
      session.start(files, point, true)
    }),
    "importMediaFiles": @core.any(import_files),
    "importFiles": @core.any(import_files),
    "cancel": @core.any(fn() { session.cancel() }),
  })
}
