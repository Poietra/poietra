///|
fn transition_ruler(input : @core.Any) -> @react.Element {
  let editor = use_editor()
  let duration : Double = input._get("duration").cast()
  let scene_time : Double = input._get("local").cast()
  let start : Double = input._get("start").cast()
  let marks : Array[&@react.ReactNode] = []
  for index = 0; index < 5; index = index + 1 {
    marks.push(
      h(
        "span",
        {
          "className": @core.any("track-seek-mark"),
          "aria-hidden": @core.any("true"),
          "key": @core.any(index),
          "style": host_record({ "left": @core.any("\{index * 25}%") }),
        },
        [
          @boundary.format_milliseconds(duration * index.to_double() / 4.0) +
          (if index == 4 { " ms" } else { "" }),
        ],
      ),
    )
  }
  marks.push(
    ui(
      "Slider",
      "Thumb",
      {
        "className": @core.any("track-seek-thumb"),
        "aria-label": @core.any("Transition の再生ヘッド"),
        "aria-valuetext": @core.any(
          @boundary.format_milliseconds(scene_time) +
          " / " +
          @boundary.format_milliseconds(duration) +
          " ms",
        ),
      },
      [],
    ),
  )
  // Keep the ruler's upper strip seekable when the wide, moving thumb overlaps it.
  // A press here reaches Slider.Control; the lower thumb still preserves its grab offset.
  marks.push(
    h(
      "span",
      {
        "className": @core.any("track-seek-ruler-hit"),
        "aria-hidden": @core.any("true"),
      },
      [],
    ),
  )
  h("div", { "className": @core.any("track-ruler") }, [
    h("div", Map([]), []),
    ui(
      "Slider",
      "Root",
      {
        "className": @core.any("track-ruler-scale track-seek"),
        "min": @core.any(0),
        "max": @core.any(duration.max(1.0)),
        "step": @core.any(1),
        "largeStep": @core.any(100),
        "value": @core.any(scene_time),
        "disabled": @core.any(duration <= 0.0),
        "onValueChange": @core.any(fn(value : Double) {
          editor
          ._get("seek")
          ._invoke([
            @core.any(start + @scene.clamp(value, 0.0, duration)),
            @core.any("transition"),
          ])
          |> ignore
        }),
      },
      [
        ui(
          "Slider",
          "Control",
          {
            "className": @core.any("track-seek-control"),
            "onPointerDownCapture": @core.any(fn(event : @core.Any) {
              if event._get("button").cast() == 0 {
                editor
                ._get("seek")
                ._invoke([
                  @core.any(start + scene_time),
                  @core.any("transition"),
                ])
                |> ignore
              }
            }),
          },
          [
            ui(
              "Slider",
              "Track",
              { "className": @core.any("track-seek-track") },
              marks,
            ),
          ],
        ),
      ],
    ),
  ])
}

///|
fn scene_ruler(
  editor : @core.Any,
  segments : FixedArray[@core.Any],
  total : Double,
  playhead : Double,
) -> @react.Element {
  let nodes : Array[&@react.ReactNode] = []
  for part in segments {
    let start : Double = part._get("start").cast()
    let left = timeline_fraction(start, total) * 100.0
    nodes.push(
      h(
        "span",
        {
          "key": part._get("id"),
          "style": host_record({
            "left": @core.any(string_value(@core.any(left)) + "%"),
          }),
        },
        [h("i", Map([]), []), @boundary.format_milliseconds(start)],
      ),
    )
  }
  nodes.push(
    h("span", { "className": @core.any("ruler-end") }, [
      h("i", Map([]), []),
      @boundary.format_milliseconds(total) + " ms",
    ]),
  )
  nodes.push(
    h(
      "input",
      {
        "type": @core.any("range"),
        "aria-label": @core.any("再生位置"),
        "min": @core.any(0),
        "max": @core.any(total.max(1.0)),
        "step": @core.any(1),
        "value": @core.any(playhead.min(total)),
        "onChange": @core.any(fn(event : @core.Any) {
          editor
          ._get("seek")
          ._invoke([
            @core.any(number_value(event._get("target")._get("value").cast())),
            @core.any("scene"),
          ])
          |> ignore
        }),
      },
      [],
    ),
  )
  h("div", { "className": @core.any("scene-ruler") }, nodes)
}

///|
fn timeline_transport(
  input : @core.Any,
  editor : @core.Any,
  total : Double,
) -> @react.Element {
  let playing = truthy(editor._get("playing"))
  let scene = editor._get("scene")
  let options : Array[&@react.ReactNode] = []
  for
    (value, name) in [
      (1.0, "Fit"),
      (0.5, "50%"),
      (0.75, "75%"),
      (1.25, "125%"),
      (1.5, "150%"),
    ] {
    options.push(
      h("option", { "key": @core.any(value), "value": @core.any(value) }, [name]),
    )
  }
  h("div", { "className": @core.any("transport") }, [
    h("div", { "className": @core.any("transport-left") }, [
      component(
        icon_button,
        {
          "label": @core.any("最初に戻る"),
          "onClick": @core.any(fn() {
            editor._get("seek")._invoke([@core.any(0), @core.any("scene")])
            |> ignore
          }),
        },
        [icon("SkipBack", 14)],
      ),
      component(
        icon_button,
        {
          "label": @core.any(
            if playing {
              "一時停止"
            } else {
              "シーンを再生"
            },
          ),
          "onClick": @core.any(fn() {
            editor._get("play")._invoke([@core.any("scene")]) |> ignore
          }),
        },
        [
          icon(if playing { "Pause" } else { "Play" }, 15, props={
            "fill": @core.any("currentColor"),
          }),
        ],
      ),
      h("span", { "className": @core.any("time-code") }, [
        h("strong", Map([]), [
          @boundary.format_milliseconds(editor._get("playhead").cast()),
        ]),
        h("span", Map([]), ["/ " + @boundary.format_milliseconds(total) + " ms"]),
      ]),
    ]),
    h("span", { "className": @core.any("canvas-meta") }, [
      string_value(scene._get("width")) +
      " × " +
      string_value(scene._get("height")),
      h("span", Map([]), ["30 fps"]),
    ]),
    h(
      "select",
      {
        "className": @core.any("zoom-select"),
        "aria-label": @core.any("キャンバスのズーム"),
        "value": input._get("zoom"),
        "onChange": @core.any(fn(event : @core.Any) {
          input
          ._get("setZoom")
          ._invoke([
            @core.any(number_value(event._get("target")._get("value").cast())),
          ])
          |> ignore
        }),
      },
      options,
    ),
  ])
}
