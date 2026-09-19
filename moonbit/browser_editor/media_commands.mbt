///|
fn insert_media(
  store : @core.Any,
  scene_id : String,
  composition_id : String,
  asset : @core.Any,
  kind : String,
  name : String,
  start : Double,
  point : @core.Any,
) -> @core.Any raise {
  let scene = current_scene(store, scene_id)
  let asset = @boundary.read_media_asset(asset)
  let composition = scene._get("compositions")._get(composition_id)
  if !truthy(composition) {
    @core.throwable(fn() {
      @core.throw_error("追加先の場面が削除されました。")
    })
  }
  if (kind == "audio" || asset.hasAudio) &&
    !is_shared_map(store, shared(store, ["scenes", scene_id, "audioTracks"])) {
    @core.throwable(fn() {
      @core.throw_error(
        "音声トラックを準備しています。同期完了後にもう一度追加してください。",
      )
    })
  }
  if kind == "audio" && !asset.hasAudio {
    @core.throwable(fn() {
      @core.throw_error("音声トラックのない素材です。")
    })
  }
  @boundary.read_media_playback(
    record([
      ("start", @core.any(start.max(0.0))),
      ("offset", @core.any(0.0)),
      ("duration", @core.any(asset.duration)),
    ]),
  )
  |> ignore
  let prepared = if kind == "video" {
    @editor.ImportedVideo(name, asset)
  } else {
    @editor.ImportedAudio(name, asset)
  }
  let point = if @core.is_nullish(point) {
    None
  } else {
    Some(@scene.Point::{
      x: number(point._get("x")),
      y: number(point._get("y")),
    })
  }
  let result = @boundary.asset_import_changes(
    scene,
    composition_id,
    [prepared],
    point,
    start_override=start,
  )
  @core.throwable(fn() { store._call("edit", [result._get("changes")]) })
  |> ignore
  let objects : FixedArray[String] = result._get("ids").cast()
  let audio : FixedArray[String] = result._get("audioIds").cast()
  record([
    (
      "objectId",
      if objects.is_empty() {
        @core.undefined()
      } else {
        @core.any(objects[0])
      },
    ),
    (
      "audioTrackId",
      if audio.is_empty() {
        @core.undefined()
      } else {
        @core.any(audio[0])
      },
    ),
  ])
}

///|
pub fn add_media(
  store : @core.Any,
  scene_id : String,
  composition_id : String,
  asset : @core.Any,
  kind : String,
  name : String,
  start : Double,
  point : @core.Any,
) -> @core.Any {
  insert_media(store, scene_id, composition_id, asset, kind, name, start, point) catch {
    error => {
      @core.throw_(native_error(error))
      @core.undefined()
    }
  }
}

///|
pub fn set_audio_track(
  store : @core.Any,
  scene_id : String,
  id : String,
  patch : @core.Any,
  separate : Bool,
) -> Unit {
  let tracks = current_scene(store, scene_id)._get("audioTracks")
  if @core.is_nullish(tracks) || !truthy(tracks._get(id)) {
    return
  }
  try
    @boundary.read_audio_track(merge(tracks._get(id), patch)) |> ignore
  catch {
    error => @core.throw_(native_error(error))
  }
  edit(
    store,
    changes_for(["scenes", scene_id, "audioTracks", id], patch),
    separate~,
  )
}

///|
pub fn remove_audio_track(
  store : @core.Any,
  scene_id : String,
  id : String,
) -> Unit {
  let tracks = current_scene(store, scene_id)._get("audioTracks")
  if !@core.is_nullish(tracks) && truthy(tracks._get(id)) {
    edit(store, [
      change(["scenes", scene_id, "audioTracks", id], @core.undefined()),
    ])
  }
}

///|
pub fn set_video_playback(
  store : @core.Any,
  scene_id : String,
  id : String,
  patch : @core.Any,
  separate : Bool,
) -> Unit {
  let object = current_scene(store, scene_id)._get("objects")._get(id)
  if @core.is_nullish(object) ||
    !truthy(object._get("media")) ||
    !@core.equal(object._get("kind"), @core.any("video")) ||
    truthy(object._get("locked")) {
    return
  }
  let current = object._get("playback")
  let previous = if @core.is_nullish(current) {
    record([
      ("start", @core.any(0.0)),
      ("offset", @core.any(0.0)),
      ("duration", object._get("media")._get("duration")),
    ])
  } else {
    current
  }
  let playback = @boundary.read_media_playback(merge(previous, patch)) catch {
    error => {
      @core.throw_(native_error(error))
      return
    }
  }
  if playback.offset + playback.duration >
    number(object._get("media")._get("duration")) + 1.0 {
    @core.throw_error(
      "素材の長さを超えないようにトリミングしてください。",
    )
    return
  }
  let base = ["scenes", scene_id, "objects", id, "playback"]
  edit(
    store,
    if truthy(current) {
      changes_for(base, patch)
    } else {
      [change(base, @boundary.write_media_playback(playback))]
    },
    separate~,
  )
}
