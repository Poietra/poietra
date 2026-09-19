///|
pub(all) enum PreparedAsset {
  ImportedImage(String, @scene.ImageAsset)
  ImportedAudio(String, @scene.MediaAsset)
  ImportedVideo(String, @scene.MediaAsset)
}

///|
pub(all) struct ImportScene {
  width : Double
  height : Double
  orders : Array[Double]
  compositions : Array[String]
  transitions : Array[(String, Double)]
  start : Double
  audio_count : Int?
}

///|
pub(all) struct AssetInsertion {
  objects : Array[PastedObject]
  audio : Array[@scene.AudioTrack]
}

///|
pub fn asset_name(filename : String, fallback : String) -> String {
  let mut end = filename.length()
  for index = filename.length() - 1; index >= 0; index = index - 1 {
    if filename.code_unit_at(index).to_int() == 46 {
      if index < filename.length() - 1 {
        end = index
      }
      break
    }
  }
  if end == 0 {
    fallback
  } else {
    bounded_asset_name(filename[:end].to_owned())
  }
}

///|
fn bounded_asset_name(name : String) -> String {
  let mut end = name.length().min(200)
  if end > 0 {
    let code = name.code_unit_at(end - 1).to_int()
    if code >= 0xd800 && code <= 0xdbff {
      end -= 1
    }
  }
  name[:end].to_owned()
}

///|
/// Build and validate the whole insertion before any collaborative write.
/// Only target metadata is needed, so existing object states stay shared.
pub fn import_assets(
  target : ImportScene,
  composition : String,
  assets : Array[PreparedAsset],
  point : @scene.Point?,
  allocate : (String) -> String,
) -> Result[AssetInsertion, String] {
  if !target.compositions.contains(composition) {
    return Err(
      "追加先の場面が削除されました。もう一度選び直してください。",
    )
  }
  let mut object_count = 0
  let mut audio_count = 0
  for asset in assets {
    match asset {
      ImportedImage(_, _) => object_count += 1
      ImportedAudio(_, _) => audio_count += 1
      ImportedVideo(_, media) => {
        object_count += 1
        if media.width is None || media.height is None {
          return Err("動画のサイズ情報がありません。")
        }
        if media.hasAudio {
          audio_count += 1
        }
      }
    }
  }
  if audio_count > 0 && target.audio_count is None {
    return Err(
      "同期完了後にもう一度素材を追加してください。",
    )
  }
  if audio_count + target.audio_count.unwrap_or(0) > 100 {
    return Err("音声トラックは 100 件まで追加できます。")
  }
  if object_count + target.orders.length() > 500 {
    return Err("オブジェクトは 500 件まで追加できます。")
  }
  let mut order = target.orders.fold(init=-1.0, fn(a, b) { a.max(b) }) + 1.0
  let mut image_index = 0
  let objects : Array[PastedObject] = []
  let audio : Array[@scene.AudioTrack] = []
  let origin = point.unwrap_or({
    x: target.width / 2.0,
    y: target.height / 2.0,
  })
  let first = index_of(target.compositions, composition)
  for asset in assets {
    let (name, image, media, video) = match asset {
      ImportedImage(name, image) => (name, Some(image), None, false)
      ImportedAudio(name, media) => (name, None, Some(media), false)
      ImportedVideo(name, media) => (name, None, Some(media), true)
    }
    let playback = media.map(fn(asset) {
      @scene.MediaPlayback::{
        start: target.start.max(0.0),
        offset: 0.0,
        duration: asset.duration,
      }
    })
    if image is Some(_) || video {
      let id = allocate("obj")
      let (kind, width, height, fraction, offset) = match image {
        Some(image) => {
          let offset = image_index.to_double() * 24.0
          image_index += 1
          (@scene.Image, image.width, image.height, 0.65, offset)
        }
        None => {
          let asset = media.unwrap()
          (@scene.Video, asset.width.unwrap(), asset.height.unwrap(), 0.75, 0.0)
        }
      }
      let scale = 1.0
        .min(target.width * fraction / width)
        .min(target.height * fraction / height)
      let state = {
        ..@scene.default_state(kind),
        x: origin.x + offset,
        y: origin.y + offset,
        width: width * scale,
        height: height * scale,
        cornerRadius: 0.0,
        fill: "none",
        stroke: if video {
          @scene.default_state(kind).stroke
        } else {
          "#ffffff"
        },
        strokeWidth: 0.0,
      }
      objects.push({
        object: {
          id,
          name: bounded_asset_name(name),
          kind,
          order,
          groupId: None,
          locked: false,
          image,
          media,
          playback,
        },
        states: target.compositions.mapi(fn(index, cid) {
          (
            cid,
            {
              ..state,
              visible: if video {
                index >= first
              } else {
                cid == composition
              },
            },
          )
        }),
        tracks: target.transitions.map(fn(link) {
          let (tid, duration) = link
          (tid, { ..@scene.default_track(id, duration), implicit: Some(true), })
        }),
      })
      order += 1.0
    }
    if media is Some(media) && (!video || media.hasAudio) {
      let playback = playback.unwrap()
      audio.push({
        id: allocate("audio"),
        name: bounded_asset_name(name + (if video { " · Audio" } else { "" })),
        asset: media,
        start: playback.start,
        offset: playback.offset,
        duration: playback.duration,
        volume: 1.0,
        muted: false,
      })
    }
  }
  Ok({ objects, audio, })
}
