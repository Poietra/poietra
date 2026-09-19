///|
priv suberror ProjectFailure {
  ProjectFailure(String)
}

///|
fn native_error(error : Error) -> @core.Any {
  match error {
    ProjectFailure(message) =>
      @core.new(@core.global_this()._get("Error"), [@core.any(message)])
    @core.ThrowError(value) => value
    _ => @core.any(error)
  }
}

///|
fn[T] native_errors(promise : @core.Promise[T]) -> @core.Promise[T] {
  promise.catch_(fn(error) {
    @core.Promise::reject(native_error(error)).to_any().cast()
  })
}

///|
fn check_abort(signal : @core.Any) -> Unit raise {
  if !@core.is_nullish(signal) {
    @core.throwable(fn() { signal._call("throwIfAborted", []) }) |> ignore
  }
}

///|
async fn host_call(
  value : @core.Any,
  name : String,
  args : FixedArray[@core.Any],
) -> @core.Any {
  let pending : @core.Promise[@core.Any] = @core.throwable(fn() {
    @core.Promise::resolve(value._call(name, args))
  })
  pending.wait()
}

///|
priv enum AssetSlot {
  Raster(@core.Any, @scene.ImageAsset)
  Clip(@core.Any, @scene.MediaAsset)
}

///|
fn AssetSlot::source(self : AssetSlot) -> String {
  match self {
    Raster(_, asset) => asset.src
    Clip(_, asset) => asset.src
  }
}

///|
fn image_slot(object : @core.Any) -> AssetSlot raise {
  let image = @boundary.read_image_asset(object._get("image")) catch {
    _ =>
      raise ProjectFailure(
        "画像の参照やサイズ情報が正しくありません。",
      )
  }
  Raster(object, image)
}

///|
fn media_slot(asset : @core.Any) -> AssetSlot raise {
  let decoded = @boundary.read_media_asset(asset) catch {
    _ =>
      raise ProjectFailure(
        "音声・動画の参照や形式情報が正しくありません。",
      )
  }
  Clip(asset, decoded)
}

///|
fn object_slots(objects : FixedArray[@core.Any]) -> Array[AssetSlot] raise {
  let slots = []
  for object in objects {
    if !@core.is_nullish(object._get("image")) {
      slots.push(image_slot(object))
    }
    if !@core.is_nullish(object._get("media")) {
      slots.push(media_slot(object._get("media")))
    }
  }
  slots
}

///|
fn project_slots(
  project : @core.Any,
  seed_audio : Bool,
) -> Array[AssetSlot] raise {
  let slots = []
  let scenes = project._get("scenes")
  for id in @core.object_keys(scenes) {
    let scene = scenes._get(id)
    let objects : FixedArray[@core.Any] = @core.global_this()
      ._get("Object")
      ._call("values", [scene._get("objects")])
      .cast()
    slots.append(object_slots(objects))
    let tracks = scene._get("audioTracks")
    if @core.is_nullish(tracks) {
      if seed_audio {
        scene._set("audioTracks", @core.new_object())
      }
    } else {
      for id in @core.object_keys(tracks) {
        slots.push(media_slot(tracks._get(id)._get("asset")))
      }
    }
  }
  slots
}

///|
fn check_metadata(slots : Array[AssetSlot]) -> Unit raise {
  // Reject contradictory references before downloading or uploading any bytes.
  let known : @collection.JsMap[String, AssetSlot] = @collection.JsMap::new()
  for slot in slots {
    let source = slot.source()
    if known.get(source) is Some(previous) {
      match (previous, slot) {
        (Raster(_, a), Raster(_, b)) =>
          if a.width != b.width || a.height != b.height {
            raise ProjectFailure(
              "画像のサイズ情報が一致しません。元の画像を追加し直してください。",
            )
          }
        (Clip(_, a), Clip(_, b)) =>
          if !@assets.same_media_metadata(a, b) {
            raise ProjectFailure(
              "音声・動画の長さや形式情報が一致しません。素材を追加し直してください。",
            )
          }
        _ =>
          raise ProjectFailure(
            "素材の形式情報が一致しません。素材を追加し直してください。",
          )
      }
    } else {
      known.set(source, slot) |> ignore
    }
  }
}

///|
pub fn portable_project(
  project : @core.Any,
  signal : @core.Any,
  io : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    check_abort(signal)
    let snapshot = @core.throwable(fn() {
      @core.global_this()._call("structuredClone", [project])
    })
    let text : String = @core.throwable(fn() {
      @core.global_this()._get("JSON")._call("stringify", [snapshot]).cast()
    })
    let mut size = @boundary.bounded_utf8_size(text, 134217728)
    if size > 134217728 {
      raise ProjectFailure(
        "保存する素材や Scene を減らして、128 MB 以下にしてください。",
      )
    }
    let slots = project_slots(snapshot, false)
    check_metadata(slots)
    let sources : @collection.JsMap[String, String] = @collection.JsMap::new()
    for slot in slots {
      check_abort(signal)
      let source = slot.source()
      let embedded = match sources.get(source) {
        Some(value) => value
        None => {
          let value = if source.has_prefix("data:") {
            source
          } else {
            let blob = match slot {
              Raster(_, _) =>
                host_call(io, "imageBlob", [@core.any(source), signal])
              Clip(_, asset) => {
                let blob = host_call(io, "mediaBlob", [
                  @core.any(source),
                  signal,
                ])
                if !@core.equal(blob._get("type"), @core.any(asset.mime)) {
                  raise ProjectFailure(
                    "素材の形式情報が一致しません。素材を追加し直してください。",
                  )
                }
                blob
              }
            }
            check_abort(signal)
            host_call(io, "blobDataUrl", [blob]).cast()
          }
          sources.set(source, value) |> ignore
          value
        }
      }
      check_abort(signal)
      size += embedded.length() - source.length()
      if size > 134217728 {
        raise ProjectFailure(
          "保存する素材や Scene を減らして、128 MB 以下にしてください。",
        )
      }
      match slot {
        Raster(object, _) =>
          object._get("image")._set("src", @core.any(embedded))
        Clip(asset, _) => asset._set("src", @core.any(embedded))
      }
    }
    snapshot
  })
  |> native_errors
}
