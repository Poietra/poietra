///|
priv enum ImportPhase {
  ReadAsset
  ReadWaveform
  TransferAsset
  SaveAsset
}

///|
priv struct ImportProgress {
  name : String
  index : Int
  count : Int
  phase : ImportPhase
  progress : Double
}

///|
priv struct ImportJob {
  input : @core.Any
  request : @core.Any
  scene : String
  composition : String
  images_only : Bool
}

///|
priv struct ImportSession {
  mut input : @core.Any
  mut mounted : Bool
  mut job : ImportJob?
  image : @react.ReactRef[@core.Any]
  media : @react.ReactRef[@core.Any]
  image_progress : (Bool) -> Unit
  progress : (ImportProgress?) -> Unit
  error : (String) -> Unit
}

///|
fn import_scene_id(input : @core.Any) -> @core.Any {
  let scene = input._get("scene")
  if @core.is_nullish(scene) {
    @core.undefined()
  } else {
    scene._get("id")
  }
}

///|
fn ImportSession::owns(self : ImportSession, job : ImportJob) -> Bool {
  self.mounted &&
  self.job.map(fn(current) { physical_equal(current, job) }).unwrap_or(false)
}

///|
fn ImportSession::current(self : ImportSession, job : ImportJob) -> Bool {
  self.owns(job) &&
  !ui_aborted(job.request._get("controller")._get("signal")) &&
  @core.equal(self.input._get("store"), job.input._get("store")) &&
  @core.equal(import_scene_id(self.input), @core.any(job.scene)) &&
  @core.equal(self.input._get("compositionId"), @core.any(job.composition)) &&
  !truthy(self.input._get("playing")) &&
  !truthy(self.input._get("transportView"))
}

///|
fn ImportSession::release(self : ImportSession, job : ImportJob) -> Unit {
  if !self.owns(job) {
    return
  }
  self.job = None
  let slot = if job.images_only { self.image } else { self.media }
  if slot
    .get_current()
    .map(fn(value) { @core.equal(value, job.request) })
    .unwrap_or(false) {
    slot.set_current(None)
  }
  (self.image_progress)(false)
  (self.progress)(None)
}

///|
fn ImportSession::cancel(self : ImportSession) -> Unit {
  let previous = self.job
  self.job = None
  for slot in [self.image, self.media] {
    if slot.get_current() is Some(request) {
      slot.set_current(None)
      request._get("controller")._call("abort", []) |> ignore
    }
  }
  if self.mounted {
    (self.image_progress)(false)
    (self.progress)(None)
    if previous is Some(job) && !job.images_only {
      key_callback(self.input, "notify", [
        @core.any("素材の追加を中止しました"),
      ])
    }
  }
}

///|
fn ImportSession::report(
  self : ImportSession,
  job : ImportJob,
  name : String,
  index : Int,
  count : Int,
  value : @core.Any,
) -> Unit {
  if !self.current(job) {
    return
  }
  let phase : String = value._get("phase").cast()
  (self.progress)(
    Some({
      name,
      index,
      count,
      phase: match phase {
        "waveform" => ReadWaveform
        "uploading" => TransferAsset
        "saving" => SaveAsset
        _ => ReadAsset
      },
      progress: value._get("progress").cast(),
    }),
  )
}

///|
fn ImportSession::start(
  self : ImportSession,
  files : FixedArray[@core.Any],
  point : @core.Any,
  force_image : Bool,
) -> @core.Promise[Unit] {
  @core.from_async(async fn() {
    let input = self.input
    if !self.mounted ||
      @core.is_nullish(input._get("scene")) ||
      files.is_empty() ||
      self.image.get_current() is Some(_) ||
      self.media.get_current() is Some(_) {
      return
    }
    if truthy(input._get("playing")) || truthy(input._get("transportView")) {
      (self.error)(
        "編集する場面に戻ってから素材を追加してください。",
      )
      return
    }
    if files.length() > 8 {
      (self.error)("素材は一度に 8 件まで追加できます。")
      return
    }
    let images_only = force_image ||
      files
      .iter()
      .all(fn(file) {
        let mime : String = file._get("type").cast()
        mime.has_prefix("image/")
      })
    let scene : String = import_scene_id(input).cast()
    let composition : String = input._get("compositionId").cast()
    let controller = new_controller()
    let signal = controller._get("signal")
    let request = host_record({
      "sceneId": @core.any(scene),
      "compositionId": @core.any(composition),
      "controller": controller,
    })
    let job : ImportJob = { input, request, scene, composition, images_only, }
    self.job = Some(job)
    let slot = if images_only { self.image } else { self.media }
    slot.set_current(Some(request))
    (self.error)("")
    (self.image_progress)(images_only)
    defer self.release(job)
    try {
      let store = input._get("store")
      let room : String = store._get("roomId").cast()
      let prepared : Array[@editor.PreparedAsset] = []
      for index, file in files {
        if !self.current(job) {
          return
        }
        let filename : String = file._get("name").cast()
        let mime : String = file._get("type").cast()
        let progress = fn(value : @core.Any) {
          self.report(job, filename, index + 1, files.length(), value)
        }
        if !images_only {
          progress(
            host_record({
              "phase": @core.any("reading"),
              "progress": @core.any(0.0),
            }),
          )
        }
        if force_image || mime.has_prefix("image/") {
          let image = @browser_media.normalize_image(file).wait()
          if !self.current(job) {
            return
          }
          let src = @browser_media.upload_image(
            room,
            image._get("blob"),
            signal,
          ).wait()
          if !self.current(job) {
            return
          }
          let asset = @boundary.read_image_asset(
            host_record({
              "src": @core.any(src),
              "width": image._get("width"),
              "height": image._get("height"),
            }),
          )
          prepared.push(
            @editor.ImportedImage(@editor.asset_name(filename, "Image"), asset),
          )
        } else {
          let media = @browser_media.prepare_media(
            file,
            signal,
            @core.any(progress),
          ).wait()
          if !self.current(job) {
            return
          }
          let src = @browser_media.upload_media(
            room,
            media._get("blob"),
            signal,
            @core.any(progress),
          ).wait()
          if !self.current(job) {
            return
          }
          let native = ui_shallow_copy(media._get("asset"))
          native._set("src", @core.any(src))
          let asset = @boundary.read_media_asset(native)
          let name = @editor.asset_name(filename, "Media")
          let video = @core.equal(media._get("kind"), @core.any("video"))
          prepared.push(
            if video {
              @editor.ImportedVideo(name, asset)
            } else {
              @editor.ImportedAudio(name, asset)
            },
          )
        }
      }
      if !self.current(job) {
        return
      }
      // Prepare all edits first. A single command gives the batch one Undo item.
      let current = @core.throwable(fn() {
        store._call("scene", [@core.any(scene)])
      })
      let point : @scene.Point? = if @core.is_nullish(point) {
        None
      } else {
        Some({ x: point._get("x").cast(), y: point._get("y").cast(), })
      }
      let insertion = @boundary.asset_import_changes(
        current, composition, prepared, point,
      )
      @core.throwable(fn() { store._call("edit", [insertion._get("changes")]) })
      |> ignore
      let latest = self.input
      key_select_composition(latest, composition)
      key_callback(latest, "setSelectedIds", [insertion._get("ids")])
      key_callback(latest, "setTool", [@core.any("select")])
      key_callback(latest, "setRightTab", [@core.any("properties")])
      let has_audio = prepared
        .iter()
        .any(fn(asset) {
          match asset {
            ImportedAudio(_, _) => true
            ImportedVideo(_, asset) => asset.hasAudio
            _ => false
          }
        })
      key_callback(latest, "notify", [
        @core.any(
          if images_only {
            "\{prepared.length()} 枚の画像を追加しました"
          } else {
            "\{prepared.length()} 件の素材を追加しました" +
            (if has_audio {
              "。音声は下の専用トラックで編集できます"
            } else {
              ""
            })
          },
        ),
      ])
    } catch {
      error =>
        if self.current(job) {
          (self.error)(
            error_message(
              ui_native_error(error),
              "素材を追加できませんでした。",
            ),
          )
        }
    }
  })
}
