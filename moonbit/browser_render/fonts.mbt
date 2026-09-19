///|
priv enum CanvasContext {
  Uninitialized
  Unavailable
  Ready(@core.Any)
}

///|
let measurement_context : Ref[CanvasContext] = Ref(Uninitialized)

///|
let font_catalog : Ref[@render.FontCatalog] = Ref({ faces: [], })

///|
let font_styles : Map[String, String] = Map([])

///|
let font_requests : Map[String, @core.Promise[Unit]] = Map([])

///|
priv suberror FontError {
  FontError(String)
}

///|
pub fn create_font_catalog(
  inter_url : String,
  css : String,
  files : @core.Any,
) -> @core.Any {
  let urls = Map([])
  for key in @core.object_keys(files) {
    urls[key] = files._get(key).cast()
  }
  @core.any(@render.font_catalog(inter_url, css, urls))
}

///|
fn sources_array(sources : FixedArray[String]) -> Array[String] {
  Array::makei(sources.length(), fn(i) { sources[i] })
}

///|
extern "js" fn buffer_bytes(buffer : @core.Any) -> Bytes =
  #|buffer => new Uint8Array(buffer)

///|
pub fn prepare_fonts(
  sources : FixedArray[String],
  load_catalog : () -> @core.Promise[@core.Any],
) -> @core.Promise[Unit] {
  @core.from_async(async fn() {
    let global = @core.global_this()
    if @core.is_undefined(global._get("document")) ||
      @core.is_undefined(global._get("FontFace")) ||
      !sources.iter().any(fn(source) { !source.is_empty() }) {
      return
    }
    if font_catalog.val.faces.is_empty() {
      font_catalog.val = load_catalog().wait().cast()
    }
    let required = @render.required_faces(
      font_catalog.val,
      sources_array(sources),
    )
    let tasks = required.map(fn(face) {
      if font_requests.get(face.url) is Some(task) {
        return task
      }
      let task = @core.from_async(async fn() {
        // Publish the request before host code can fail synchronously.
        @core.Promise::resolve(()).wait()
        errdefer font_requests.remove(face.url)
        let fetching : @core.Promise[@core.Any] = @core.throwable(fn() {
          global._call("fetch", [@core.any(face.url)]).cast()
        })
        let response = fetching.wait()
        let ok : Bool = response._get("ok").cast()
        if !ok {
          raise FontError("Font asset could not be loaded: " + face.family)
        }
        let reading : @core.Promise[@core.Any] = @core.throwable(fn() {
          response._call("arrayBuffer", []).cast()
        })
        let buffer = reading.wait()
        let options = @core.from_entries([
          ("style", @core.any("normal")),
          ("weight", @core.any("400")),
        ])
        if face.unicode_range is Some(range) {
          options._set("unicodeRange", @core.any(range))
        }
        let font = @core.throwable(fn() {
          @core.new(global._get("FontFace"), [
            @core.any(face.family),
            buffer,
            options,
          ])
        })
        let loading : @core.Promise[@core.Any] = @core.throwable(fn() {
          font._call("load", []).cast()
        })
        loading.wait() |> ignore
        @core.throwable(fn() {
          global._get("document")._get("fonts")._call("add", [font])
        })
        |> ignore
        let range = face.unicode_range
          .map(fn(range) { "unicode-range:\{range};" })
          .unwrap_or("")
        let encoded = @base64.encode(buffer_bytes(buffer))
        font_styles[face.url] = "@font-face{font-family:'\{face.family}';font-style:normal;font-weight:400;\{range}src:url(data:font/woff2;base64,\{encoded}) format('woff2');}"
      })
      font_requests[face.url] = task
      task
    })
    @core.Promise::all(tasks).wait() |> ignore
  })
  |> host_errors
}

///|
pub fn embedded_font_styles(sources : FixedArray[String]) -> String {
  let css = StringBuilder()
  for face in @render.required_faces(font_catalog.val, sources_array(sources)) {
    if font_styles.get(face.url) is Some(style) {
      css.write_string(style)
    }
  }
  if css.is_empty() {
    ""
  } else {
    "<style>\{css.to_string()}</style>"
  }
}

///|
extern "js" fn text_metrics_value(
  width : Double,
  height : Double,
  line_height : Double,
  baseline : Double,
) -> @core.Any =
  #|(width, height, lineHeight, baseline) => ({width, height, lineHeight, baseline})

///|
pub fn measure_text(text : String, size : Double) -> @core.Any {
  if size <= 0.0 {
    return text_metrics_value(0.0, 0.0, 0.0, 0.0)
  }
  if measurement_context.val is Uninitialized {
    let document = @core.global_this()._get("document")
    if !@core.is_undefined(document) {
      let value = document
        ._call("createElement", [@core.any("canvas")])
        ._call("getContext", [@core.any("2d")])
      measurement_context.val = if @core.is_nullish(value) {
        Unavailable
      } else {
        Ready(value)
      }
    }
  }
  let measure : ((String) -> @render.LineMetrics)? = match
    measurement_context.val {
    Ready(context) => {
      context._set(
        "font",
        @core.any(
          "400 \{size}px 'Poietra Inter', 'Poietra Noto Sans JP', sans-serif",
        ),
      )
      context._set("textRendering", @core.any("geometricPrecision"))
      Some(fn(line : String) {
        let value = context._call("measureText", [@core.any(line)])
        {
          advance: value._get("width").cast(),
          left: value._get("actualBoundingBoxLeft").cast(),
          right: value._get("actualBoundingBoxRight").cast(),
          ascent: value._get("actualBoundingBoxAscent").cast(),
          descent: value._get("actualBoundingBoxDescent").cast(),
        }
      })
    }
    _ => None
  }
  let value = @render.text_metrics(text, size, measure)
  text_metrics_value(
    value.width,
    value.height,
    value.line_height,
    value.baseline,
  )
}
