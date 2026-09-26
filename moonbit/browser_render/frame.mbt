///|
/// Only values consumed by the painter cross the native boundary. In particular,
/// asset waveforms and unrelated document/extension fields are not cloned.
priv struct LayerInput {
  drawable : @render.Drawable
  media : String?
  video_time : Double?
}

///|
priv struct PaintFrame {
  width : Double
  height : Double
  background : String
  items : Array[LayerInput]
  requests : Array[@browser_media.VideoRequest]
  images : Map[String, String]
}

///|
fn capture_layer(input : @core.Any) -> LayerInput {
  {
    drawable: @boundary.decode_drawable(input),
    media: optional_source(input._get("object")._get("media")),
    video_time: optional_number(input._get("videoTimeMs")),
  }
}

///|
/// Capture synchronously before decoder/renderer awaits. Every record read from
/// native input is rebuilt once; subsequent stages borrow those typed values.
fn capture_frame(input : @core.Any) -> PaintFrame {
  let native : FixedArray[@core.Any] = input._get("objects").cast()
  let requests = []
  let images : Map[String, String] = Map([])
  let items = Array::makei(native.length(), fn(i) {
    let value = native[i]
    let item = capture_layer(value)
    let drawable = item.drawable
    if drawable.kind == @scene.Video &&
      drawable.state.visible &&
      drawable.state.opacity > 0.0 &&
      drawable.progress > 0.0 &&
      drawable.video_frame.map(fn(image) { image.is_empty() }).unwrap_or(true) {
      let object = value._get("object")
      let asset = object._get("media")
      requests.push(@browser_media.VideoRequest::{
        id: drawable.id,
        name: object._get("name").cast(),
        source: item.media,
        time: if @core.is_nullish(asset) {
          0.0
        } else {
          @assets.video_seconds(
            item.video_time.unwrap_or(0.0),
            asset._get("duration").cast(),
          )
        },
        publish: fn(image) { images[drawable.id] = image },
      })
    }
    item
  })
  {
    width: input._get("width").cast(),
    height: input._get("height").cast(),
    background: input._get("background").cast(),
    items,
    requests,
    images,
  }
}

///|
fn PaintFrame::svg_frame(self : PaintFrame) -> @render.RenderFrame {
  {
    width: self.width,
    height: self.height,
    background: self.background,
    objects: self.items.map(fn(item) {
      match self.images.get(item.drawable.id) {
        Some(image) => { ..item.drawable, video_frame: Some(image), }
        None => item.drawable
      }
    }),
  }
}
