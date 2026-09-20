///|
priv enum StageSvg {
  SvgMarkup(String)
  SvgView(@core.Any)
}

///|
// The renderer already supplies native props. Keep this hot path out of Map
// conversion; keys belong to React, not authored SVG attributes.
#module("react/jsx-runtime")
extern "js" fn svg_element(
  component : @core.Any,
  props : @core.Any,
  key : String,
) -> @react.Element = "jsx"

///|
let cached_svg_object : @core.Any = memo_component(svg_object)

///|
let cached_svg_fonts : @core.Any = memo_component(svg_fonts)

///|
fn svg_fonts(input : @core.Any) -> @react.Element {
  h(
    "g",
    { "dangerouslySetInnerHTML": host_record({ "__html": input._get("body") }) },
    [],
  )
}

///|
fn svg_object(input : @core.Any) -> @react.Element {
  let markup = @react.use_memo(
    fn() { host_record({ "__html": input._get("body") }) },
    [input._get("body")],
  )
  h(
    "g",
    {
      "data-object-id": input._get("id"),
      "transform": input._get("transform"),
      "opacity": input._get("opacity"),
      "fill": input._get("fill"),
      "color": input._get("color"),
      "stroke": input._get("stroke"),
      "strokeWidth": input._get("strokeWidth"),
      "strokeLinecap": @core.any("round"),
      "strokeLinejoin": @core.any("round"),
      "filter": input._get("filter"),
      "dangerouslySetInnerHTML": markup,
    },
    [],
  )
}

///|
fn stage_svg(value : StageSvg, canvas_visible : Bool) -> @react.Element {
  let props = {
    "key": @core.any("svg"),
    "className": @core.any(
      if canvas_visible {
        "scene-svg scene-hit-svg"
      } else {
        "scene-svg"
      },
    ),
  }
  match value {
    SvgMarkup(svg) => {
      props["dangerouslySetInnerHTML"] = host_record({
        "__html": @core.any(svg),
      })
      h("div", props, [])
    }
    SvgView(view) => {
      let width : String = view._get("width").cast()
      let height : String = view._get("height").cast()
      let nodes : Array[&@react.ReactNode] = [
        keyed_element(
          cached_svg_fonts,
          { "key": @core.any("fonts"), "body": view._get("fonts") },
          [],
        ),
      ]
      if !@core.is_nullish(view._get("background")) {
        nodes.push(
          h(
            "rect",
            {
              "key": @core.any("background"),
              "width": @core.any(width),
              "height": @core.any(height),
              "fill": view._get("background"),
            },
            [],
          ),
        )
      }
      let objects : FixedArray[@core.Any] = view._get("objects").cast()
      for item in objects {
        nodes.push(
          svg_element(
            cached_svg_object,
            item,
            "object-" + string_value(item._get("id")),
          ),
        )
      }
      h("div", props, [
        h(
          "svg",
          {
            "xmlns": @core.any("http://www.w3.org/2000/svg"),
            "width": @core.any(width),
            "height": @core.any(height),
            "viewBox": @core.any("0 0 \{width} \{height}"),
          },
          nodes,
        ),
      ])
    }
  }
}
