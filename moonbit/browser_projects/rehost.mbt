///|
priv enum StoredAsset {
  StoredImage(@scene.ImageAsset)
  StoredMedia(@scene.MediaAsset)
}

///|
async fn copy_image(
  asset : @scene.ImageAsset,
  room : String,
  signal : @core.Any,
  io : @core.Any,
) -> StoredAsset {
  let blob = host_call(io, "imageBlob", [@core.any(asset.src), signal])
  check_abort(signal)
  let global = @core.global_this()
  let urls = global._get("URL")
  let url = @core.throwable(fn() { urls._call("createObjectURL", [blob]) })
  defer urls._call("revokeObjectURL", [url]) |> ignore
  let decoded = @core.throwable(fn() { @core.new(global._get("Image"), []) })
  defer decoded._set("src", @core.any(""))
  let abort = fn() { decoded._set("src", @core.any("")) }
  if !@core.is_nullish(signal) {
    signal._call("addEventListener", [
      @core.any("abort"),
      @core.any(abort),
      @core.from_entries([("once", @core.any(true))]),
    ])
    |> ignore
  }
  defer (if !@core.is_nullish(signal) {
    signal._call("removeEventListener", [@core.any("abort"), @core.any(abort)])
    |> ignore
  })
  check_abort(signal)
  @core.throwable(fn() { decoded._set("src", url) })
  host_call(decoded, "decode", []) |> ignore
  check_abort(signal)
  let width : Double = decoded._get("naturalWidth").cast()
  let height : Double = decoded._get("naturalHeight").cast()
  if width != asset.width || height != asset.height {
    raise ProjectFailure(
      "画像のサイズ情報が一致しません。元の画像を追加し直してください。",
    )
  }
  let src : String = host_call(io, "uploadImage", [
    @core.any(room),
    blob,
    signal,
  ]).cast()
  check_abort(signal)
  StoredImage({ src, width, height, })
}

///|
async fn copy_media(
  asset : @scene.MediaAsset,
  room : String,
  signal : @core.Any,
  io : @core.Any,
) -> StoredAsset {
  let blob = host_call(io, "mediaBlob", [@core.any(asset.src), signal])
  check_abort(signal)
  let file = @core.throwable(fn() {
    @core.new(@core.global_this()._get("File"), [
      @core.any(([blob] : FixedArray[@core.Any])),
      @core.any("shared-media"),
      @core.from_entries([("type", @core.any(asset.mime))]),
    ])
  })
  let active = if @core.is_nullish(signal) {
    @core.new(@core.global_this()._get("AbortController"), [])._get("signal")
  } else {
    signal
  }
  let prepared = host_call(io, "prepareMedia", [file, active])
  check_abort(signal)
  let native_asset = @core.global_this()
    ._get("Object")
    ._call("assign", [
      @core.new_object(),
      prepared._get("asset"),
      @core.from_entries([("src", @core.any(asset.src))]),
    ])
  let decoded = @boundary.read_media_asset(native_asset) catch {
    _ =>
      raise ProjectFailure(
        "音声・動画の長さや形式情報が一致しません。素材を追加し直してください。",
      )
  }
  if !@assets.same_media_metadata(decoded, asset) {
    raise ProjectFailure(
      "音声・動画の長さや形式情報が一致しません。素材を追加し直してください。",
    )
  }
  let src : String = host_call(io, "uploadMedia", [
    @core.any(room),
    prepared._get("blob"),
    signal,
  ]).cast()
  check_abort(signal)
  StoredMedia({ ..decoded, src, })
}

///|
async fn rehost(
  slots : Array[AssetSlot],
  room : String,
  signal : @core.Any,
  io : @core.Any,
) -> Unit {
  check_abort(signal)
  check_metadata(slots)
  let sources : @collection.JsMap[String, StoredAsset] = @collection.JsMap::new()
  let changes : Array[(AssetSlot, StoredAsset)] = []
  for slot in slots {
    check_abort(signal)
    let source = slot.source()
    if source.has_prefix("/api/rooms/" + room + "/") {
      continue
    }
    let stored = match sources.get(source) {
      Some(stored) => stored
      None => {
        let stored = match slot {
          Raster(_, asset) => copy_image(asset, room, signal, io)
          Clip(_, asset) => copy_media(asset, room, signal, io)
        }
        sources.set(source, stored) |> ignore
        stored
      }
    }
    changes.push((slot, stored))
  }
  // Commit references only when the complete batch succeeded and is still current.
  check_abort(signal)
  for change in changes {
    match change {
      (Raster(object, _), StoredImage(asset)) =>
        object._set("image", @boundary.write_image_asset(asset))
      (Clip(target, _), StoredMedia(asset)) =>
        @core.global_this()
        ._get("Object")
        ._call("assign", [target, @boundary.write_media_asset(asset)])
        |> ignore
      _ => ()
    }
  }
}

///|
pub fn store_project_images(
  project : @core.Any,
  room : String,
  signal : @core.Any,
  io : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    check_abort(signal)
    let snapshot = @core.throwable(fn() {
      @core.global_this()._call("structuredClone", [project])
    })
    let slots = project_slots(snapshot, true)
    rehost(slots, room, signal, io)
    snapshot
  })
  |> native_errors
}

///|
pub fn rehost_image_assets(
  objects : FixedArray[@core.Any],
  room : String,
  signal : @core.Any,
  io : @core.Any,
) -> @core.Promise[Unit] {
  @core.from_async(async fn() {
    check_abort(signal)
    rehost(object_slots(objects), room, signal, io)
  })
  |> native_errors
}
