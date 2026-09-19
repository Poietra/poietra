///|
#module("#poietra/site-host")
extern "js" fn icon_component(name : String) -> @core.Any = "iconComponent"

///|
fn icon(name : String, size : Int) -> @react.Element {
  @react.jsx(icon_component(name), [], props={ "size": @core.any(size) })
}

///|
fn h(
  tag : String,
  props : Map[String, @core.Any],
  children : Array[&@react.ReactNode],
) -> @react.Element {
  @shell.h(tag, props, children)
}

///|
fn tag(name : String, children : Array[&@react.ReactNode]) -> @react.Element {
  h(name, {}, children)
}

///|
fn cls(
  name : String,
  class_ : String,
  children : Array[&@react.ReactNode],
) -> @react.Element {
  h(name, { "className": @core.any(class_) }, children)
}

///|
fn anchor(
  class_ : String,
  href : String,
  children : Array[&@react.ReactNode],
) -> @react.Element {
  h("a", { "className": @core.any(class_), "href": @core.any(href) }, children)
}

///|
fn linebreak() -> @react.Element {
  tag("br", [])
}

///|
fn lines(values : Array[String]) -> @react.Element {
  let nodes : Array[&@react.ReactNode] = []
  for index, value in values {
    if index > 0 {
      nodes.push(linebreak())
    }
    nodes.push(value)
  }
  @react.fragment(nodes)
}

///|
fn optional_string(value : @core.Any) -> String? {
  if @core.is_nullish(value) {
    None
  } else {
    Some(value.cast())
  }
}

///|
fn action(
  class_ : String,
  disabled : Bool,
  callback : () -> Unit,
  children : Array[&@react.ReactNode],
) -> @react.Element {
  h(
    "button",
    {
      "className": @core.any(class_),
      "disabled": @core.any(disabled),
      "onClick": @core.any(callback),
    },
    children,
  )
}

///|
extern "js" fn fixed(value : Double) -> String =
  #|value => value.toFixed(2)

///|
fn motion_study(input : @core.Any) -> @react.Element {
  let copy : @site.LandingCopy = input._get("copy").cast()
  let (time, set_time) = @react.use_state(1000.0)
  let title_id = @react.use_id()
  let (x, y, opacity) = @site.study_position(time)
  let seconds = fixed(time / 1000.0)
  let timing_row = fn(name : String, duration : String, width : String) {
    tag("div", [
      tag("span", [icon("CornerDownRight", 12), name]),
      cls("div", "landing-study-bar", [
        h(
          "span",
          { "style": @core.from_entries([("width", @core.any(width))]) },
          [],
        ),
      ]),
      tag("span", [duration]),
    ])
  }
  cls("figure", "landing-motion-study", [
    cls("div", "landing-study-heading", [
      tag("span", [icon("SlidersHorizontal", 15), copy.studyTitle]),
      tag("span", [copy.studyLabel]),
    ]),
    h(
      "svg",
      {
        "viewBox": @core.any("0 0 560 280"),
        "role": @core.any("img"),
        "aria-labelledby": @core.any(title_id),
      },
      [
        h("title", { "id": @core.any(title_id) }, [copy.studyDescription]),
        h(
          "g",
          {
            "className": @core.any("landing-study-guides"),
            "fill": @core.any("none"),
            "stroke": @core.any("currentColor"),
            "strokeWidth": @core.any("1"),
          },
          [
            h(
              "path",
              {
                "d": @core.any(
                  "M72 48V232 M176 48V232 M280 48V232 M384 48V232 M488 48V232 M48 76H512 M48 140H512 M48 204H512",
                ),
              },
              [],
            ),
          ],
        ),
        h(
          "path",
          {
            "d": @core.any("M72 204C240 204 300 76 488 76"),
            "fill": @core.any("none"),
            "stroke": @core.any("#67c4d9"),
            "strokeWidth": @core.any("1.5"),
            "opacity": @core.any("0.55"),
          },
          [],
        ),
        h(
          "circle",
          {
            "cx": @core.any("72"),
            "cy": @core.any("204"),
            "r": @core.any("17"),
            "fill": @core.any("none"),
            "stroke": @core.any("#737582"),
            "strokeDasharray": @core.any("3 4"),
          },
          [],
        ),
        h(
          "circle",
          {
            "cx": @core.any("488"),
            "cy": @core.any("76"),
            "r": @core.any("17"),
            "fill": @core.any("none"),
            "stroke": @core.any("#737582"),
            "strokeDasharray": @core.any("3 4"),
          },
          [],
        ),
        h(
          "text",
          {
            "x": @core.any("72"),
            "y": @core.any("247"),
            "textAnchor": @core.any("middle"),
            "className": @core.any("landing-study-coordinate"),
          },
          [copy.studyFrom],
        ),
        h(
          "text",
          {
            "x": @core.any("488"),
            "y": @core.any("42"),
            "textAnchor": @core.any("middle"),
            "className": @core.any("landing-study-coordinate"),
          },
          [copy.studyTo],
        ),
        h(
          "circle",
          {
            "data-demo-object": @core.any(true),
            "cx": @core.any(x),
            "cy": @core.any(y),
            "r": @core.any("17"),
            "fill": @core.any("#c8eef4"),
            "opacity": @core.any(opacity),
          },
          [],
        ),
        h(
          "g",
          {
            "aria-hidden": @core.any("true"),
            "transform": @core.any("translate(\{x + 20.0} \{y + 20.0})"),
          },
          [
            h(
              "path",
              {
                "d": @core.any("M0 0L4 15L8 10L14 9Z"),
                "fill": @core.any("#67c4d9"),
                "stroke": @core.any("#111217"),
                "strokeWidth": @core.any("1.5"),
              },
              [],
            ),
            h(
              "rect",
              {
                "x": @core.any("13"),
                "y": @core.any("12"),
                "width": @core.any("42"),
                "height": @core.any("21"),
                "rx": @core.any("4"),
                "fill": @core.any("#28434b"),
              },
              [],
            ),
            h(
              "text",
              {
                "x": @core.any("34"),
                "y": @core.any("26"),
                "textAnchor": @core.any("middle"),
                "fill": @core.any("#c8eef4"),
                "fontSize": @core.any("11"),
              },
              [copy.studyCursor],
            ),
          ],
        ),
      ],
    ),
    h(
      "div",
      {
        "className": @core.any("landing-study-timings"),
        "aria-label": @core.any(copy.studyTimings),
      },
      [
        timing_row(copy.studyPosition, copy.studyPositionDuration, "100%"),
        timing_row(copy.studyOpacity, copy.studyOpacityDuration, "15%"),
      ],
    ),
    cls("div", "landing-study-control", [
      h("label", { "htmlFor": @core.any(title_id + "-position") }, [
        copy.studyControl,
      ]),
      h("output", { "htmlFor": @core.any(title_id + "-position") }, [
        seconds,
        tag("span", [copy.studyTotal]),
      ]),
      h(
        "input",
        {
          "id": @core.any(title_id + "-position"),
          "type": @core.any("range"),
          "min": @core.any("0"),
          "max": @core.any("2000"),
          "step": @core.any("10"),
          "value": @core.any(time),
          "aria-label": @core.any(copy.studyRange),
          "aria-valuetext": @core.any(seconds + " " + copy.seconds),
          "onChange": @core.any(fn(event : @core.Any) {
            set_time(event._get("target")._get("valueAsNumber").cast())
          }),
        },
        [],
      ),
    ]),
  ])
}
