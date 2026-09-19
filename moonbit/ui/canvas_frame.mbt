///|
fn pixel_density() -> Double {
  let value = @core.global_this()._get("window")._get("devicePixelRatio")
  if truthy(value) {
    value.cast()
  } else {
    1.0
  }
}

///|
pub fn canvas_frame(input : @core.Any) -> @react.Element {
  let canvas = @react.use_ref((None : @core.Any?))
  let session = @react.use_ref((None : CanvasSession?))
  let callback = @react.use_ref(Some(input._get("onPresent")))
  callback.set_current(Some(input._get("onPresent")))
  let (density, set_density) = @react.use_state_lazy(pixel_density)
  let width : Double = input._get("width").cast()
  let height : Double = input._get("height").cast()
  let job : PaintJob = {
    frame: input._get("frame"),
    scene: input._get("scene"),
    key: input._get("presentationKey").cast(),
    width,
    height,
    pixel_width: round_number(width * density).max(1.0),
    pixel_height: round_number(height * density).max(1.0),
  }
  let latest = @react.use_ref(Some(job))
  latest.set_current(Some(job))
  @react.use_effect(
    fn() {
      let media : Ref[@core.Any?] = Ref(None)
      fn update() -> Unit {
        let ratio = pixel_density()
        set_density(ratio)
        if media.val is Some(previous) {
          previous._call("removeEventListener", [
            @core.any("change"),
            @core.any(update),
          ])
          |> ignore
        }
        let query = @core.global_this()._call("matchMedia", [
          @core.any("(resolution: \{ratio}dppx)"),
        ])
        media.val = Some(query)
        query._call("addEventListener", [@core.any("change"), @core.any(update)])
        |> ignore
      }
      update()
      let window = @core.global_this()._get("window")
      window._call("addEventListener", [@core.any("resize"), @core.any(update)])
      |> ignore
      fn() {
        if media.val is Some(query) {
          query._call("removeEventListener", [
            @core.any("change"),
            @core.any(update),
          ])
          |> ignore
        }
        window._call("removeEventListener", [
          @core.any("resize"),
          @core.any(update),
        ])
        |> ignore
      }
    },
    [],
  )
  @react.use_layout_effect(
    fn() {
      let output = canvas.get_current().unwrap()
      let display = output._call("getContext", [
        @core.any("2d"),
        @core.from_entries([("alpha", @core.any(false))]),
      ])
      let publish = fn(value : @core.Any) {
        callback.get_current().unwrap()._invoke([value]) |> ignore
      }
      publish(@core.null())
      if @core.is_nullish(display) {
        return fn() { () }
      }
      let target = @core.global_this()
        ._get("document")
        ._call("createElement", [@core.any("canvas")])
      let owner : CanvasSession = {
        output,
        display,
        target,
        renderer: input._get("renderer"),
        lifetime: new_controller(),
        latest: fn() { latest.get_current().unwrap() },
        publish,
        state: Opening,
        pending: latest.get_current(),
        busy: false,
        prepared_scene: None,
      }
      session.set_current(Some(owner))
      owner.initialize(input._get("createFramePainter"))
      fn() {
        session.set_current(None)
        owner.stop(false)
      }
    },
    [
      input._get("createFramePainter"),
      input._get("renderer"),
      input._get("presentationKey"),
    ],
  )
  @react.use_layout_effect(
    fn() {
      if session.get_current() is Some(owner) {
        owner.enqueue(latest.get_current().unwrap())
      }
      fn() { () }
    },
    [
      job.frame,
      job.scene,
      @core.any(width),
      @core.any(height),
      @core.any(density),
      input._get("createFramePainter"),
      input._get("renderer"),
      input._get("presentationKey"),
    ],
  )
  h(
    "canvas",
    {
      "ref": canvas.as_any(),
      "className": @core.any("scene-canvas"),
      "aria-hidden": @core.any("true"),
      "style": @core.from_entries([
        (
          "visibility",
          @core.any(
            if truthy(input._get("visible")) {
              "visible"
            } else {
              "hidden"
            },
          ),
        ),
      ]),
    },
    [],
  )
}
