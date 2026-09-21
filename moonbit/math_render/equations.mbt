///|
priv struct MathRuntime {
  adaptor : @core.Any
  document : @core.Any
}

///|
priv struct EquationEntry {
  encoded : @core.Any
}

///|
let equations : Map[String, EquationEntry?] = Map([])

///|
let equation_models : @core.Any = @core.new(
  @core.global_this()._get("WeakMap"),
  [],
)

///|
let math_loading : Ref[@core.Promise[MathRuntime]?] = Ref(None)

///|
let geometry_attributes : Map[String, Unit] = Map::from_array(
  [
    "d", "x", "y", "x1", "x2", "y1", "y2", "width", "height", "rx", "ry", "cx", "cy",
    "r", "points", "transform", "stroke-width",
  ].map(fn(name) { (name, ()) }),
)

///|
extern "js" fn frozen(value : @core.Any) -> @core.Any = "Object.freeze"

///|
fn encode_math_node(node : @render.MathNode) -> @core.Any {
  let attributes = @core.from_entries(
    node.attributes.map(fn(attribute) { (attribute.0, @core.any(attribute.1)) }),
  )
  let children = FixedArray::makei(node.children.length(), fn(i) {
    encode_math_node(node.children[i])
  })
  frozen(
    @core.from_entries([
      ("tag", @core.any(@render.math_tag_name(node.tag))),
      ("attributes", frozen(attributes)),
      ("children", frozen(@core.any(children))),
    ]),
  )
}

///|
fn encode_equation(value : @render.Equation) -> @core.Any {
  let result = frozen(
    @core.from_entries([
      ("x", @core.any(value.x)),
      ("y", @core.any(value.y)),
      ("width", @core.any(value.width)),
      ("height", @core.any(value.height)),
      ("tree", encode_math_node(value.tree)),
      ("glyphs", @core.any(value.glyphs)),
    ]),
  )
  equation_models._call("set", [result, @core.any(value)]) |> ignore
  result
}

///|
fn math_children(
  adaptor : @core.Any,
  element : @core.Any,
) -> FixedArray[@core.Any] {
  adaptor._call("childNodes", [element]).cast()
}

///|
fn math_attribute(
  adaptor : @core.Any,
  element : @core.Any,
  name : String,
) -> String? {
  let value = adaptor._call("getAttribute", [element, @core.any(name)])
  if @core.is_nullish(value) {
    None
  } else {
    Some(value.cast())
  }
}

///|
fn view_box(source : String) -> Array[Double]? {
  let parts = []
  let mut start = 0
  let mut end = 0
  while end <= source.length() {
    let space = end == source.length() ||
      @editor.trim_text(source[end:end + 1].to_owned()).is_empty()
    if space {
      if end > start {
        let value = @string.parse_double(source[start:end]) catch {
          _ => return None
        }
        if value.is_nan() || value.is_inf() {
          return None
        }
        parts.push(value)
      }
      start = end + 1
    }
    end += 1
  }
  if parts.length() != 4 || parts[2] <= 0.0 || parts[3] <= 0.0 {
    None
  } else {
    Some(parts)
  }
}

///|
fn convert_equation(
  runtime : MathRuntime,
  source : String,
) -> @render.Equation? {
  if source.length() > 10000 {
    return None
  }
  @core.throwable(fn() {
    let adaptor = runtime.adaptor
    let container = runtime.document._call("convert", [
      @core.any(source),
      @core.from_entries([("display", @core.any(true))]),
    ])
    let svg = adaptor._call("firstChild", [container])
    guard math_attribute(adaptor, svg, "viewBox").bind(view_box) is Some(bounds) else {
      return None
    }
    let mut glyphs = 0
    let mut invalid = false
    fn read(element : @core.Any) -> @render.MathNode? {
      let tag : String = adaptor._call("kind", [element]).cast()
      if tag == "text" ||
        math_attribute(adaptor, element, "data-mml-node") == Some("merror") {
        invalid = true
      }
      guard @render.math_tag(tag) is Some(tag) else { return None }
      let attributes : Array[(String, String)] = []
      let native_attributes : FixedArray[@core.Any] = adaptor
        ._call("allAttributes", [element])
        .cast()
      for attribute in native_attributes {
        let name : String = attribute._get("name").cast()
        let value : String = attribute._get("value").cast()
        if geometry_attributes.contains(name) ||
          (
            (name == "fill" || name == "stroke") &&
            (value == "none" || value == "currentColor")
          ) {
          attributes.push((name, value))
        }
      }
      if tag != @render.Group {
        glyphs += 1
      }
      let children = []
      for child in math_children(adaptor, element) {
        if read(child) is Some(node) {
          children.push(node)
        }
      }
      Some({ tag, attributes, children, })
    }
    let children = []
    for child in math_children(adaptor, svg) {
      if read(child) is Some(node) {
        children.push(node)
      }
    }
    if invalid || glyphs == 0 {
      return None
    }
    Some({
      x: bounds[0],
      y: bounds[1],
      width: bounds[2],
      height: bounds[3],
      tree: { tag: @render.Group, attributes: [], children, },
      glyphs,
    })
  }) catch {
    _ => None
  }
}

///|
fn load_math(
  load : () -> @core.Promise[@core.Any],
) -> @core.Promise[MathRuntime] {
  if math_loading.val is Some(task) {
    return task
  }
  let task = @core.from_async(async fn() {
    @core.Promise::resolve(()).wait()
    // A failed chunk download must be retryable when the connection comes back.
    errdefer {
      math_loading.val = None
    }
    let runtime = @core.throwable(load).wait()
    @core.throwable(fn() {
      let adaptor = runtime._call("liteAdaptor", [])
      runtime._call("RegisterHTMLHandler", [adaptor]) |> ignore
      let input = @core.new(runtime._get("TeX"), [
        @core.from_entries([
          ("packages", @core.any((["base", "ams"] : FixedArray[String]))),
          ("maxBuffer", @core.any(10000)),
          ("maxMacros", @core.any(1000)),
        ]),
      ])
      let output = @core.new(runtime._get("SVG"), [
        @core.from_entries([("fontCache", @core.any("none"))]),
      ])
      let document = runtime
        ._get("mathjax")
        ._call("document", [
          @core.any(""),
          @core.from_entries([("InputJax", input), ("OutputJax", output)]),
        ])
      { adaptor, document, }
    })
  })
  math_loading.val = Some(task)
  task
}

///|
pub fn prepare_equations(
  sources : FixedArray[String],
  load : () -> @core.Promise[@core.Any],
) -> @core.Promise[Unit] {
  @core.from_async(async fn() {
    let missing : Map[String, Unit] = Map([])
    for source in sources {
      if !equations.contains(source) {
        missing[source] = ()
      }
    }
    if missing.is_empty() {
      return
    }
    let runtime = load_math(load).wait()
    for source in missing.keys() {
      if !equations.contains(source) {
        equations[source] = convert_equation(runtime, source).map(fn(equation) {
          { encoded: encode_equation(equation), }
        })
      }
    }
  }).catch_(fn(error) {
    let value = match error {
      @core.ThrowError(value) => value
      _ => @core.any(error)
    }
    @core.Promise::reject(value).to_any().cast()
  })
}

///|
pub fn get_equation(source : String) -> @core.Any {
  match equations.get(source) {
    Some(Some(entry)) => entry.encoded
    _ => @core.null()
  }
}

///|
pub fn cached_equation(value : @core.Any) -> @core.Any {
  equation_models._call("get", [value])
}

///|
pub fn equation(source : String) -> @render.Equation? {
  let value = get_equation(source)
  if @core.is_nullish(value) {
    None
  } else {
    Some(cached_equation(value).cast())
  }
}
