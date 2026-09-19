///|
pub fn calculus_project() -> @scene.Project {
  let ink = "#e8e8ee"
  let cyan = "#67c4d9"
  let green = "#b5d396"
  let coral = "#ef8078"
  let yellow = "#f4ce55"
  let builder : CalculusBuilder = {
    compositions: [
      composition("forward", "Forward pass", 2600.0, cyan),
      composition("loss", "Measure the error", 2800.0, yellow),
      composition("gradient", "Follow the gradient", 4000.0, coral),
    ],
    objects: Map([]),
  }
  let hide = fn(state : @scene.ObjectState) { { ..state, visible: false, } }
  let show = fn(state : @scene.ObjectState) { { ..state, visible: true, } }
  builder.object(
    "chapter",
    @scene.Text,
    "Chapter",
    {
      ..sample_state(@scene.Text),
      x: 640.0,
      y: 82.0,
      text: "01   THE FORWARD PASS",
      fontSize: 15.0,
      fill: cyan,
    },
    next=fn(state) {
      { ..state, text: "02   MEASURE THE ERROR", fill: yellow, }
    },
    last_stage=fn(state) {
      { ..state, text: "03   FOLLOW THE GRADIENT", fill: coral, }
    },
  )
  builder.object(
    "headline",
    @scene.Text,
    "Headline",
    {
      ..sample_state(@scene.Text),
      x: 640.0,
      y: 131.0,
      text: "A weight becomes an output.",
      fontSize: 31.0,
    },
    next=fn(state) { { ..state, text: "Compare the output with the target.", } },
    last_stage=fn(state) {
      { ..state, text: "One change. Three local sensitivities.", }
    },
  )
  builder.node("weight", "w", "Weight w", 250.0, 160.0, cyan)
  builder.node("weighted", "z", "Weighted sum z", 640.0, 480.0, green)
  builder.node("activation", "a", "Current activation a", 1030.0, 800.0, ink)
  builder.node("cost", "C", "Loss C", 1120.0, 1120.0, coral, visible=false)
  builder.arrow(
    "weight-edge",
    "w → z",
    312.0,
    330.0,
    266.0,
    0.0,
    cyan,
    next=fn(state) { { ..state, x: 222.0, y: 300.0, width: 196.0, } },
    last_stage=fn(state) { { ..state, x: 418.0, width: -196.0, } },
  )
  builder.arrow(
    "activation-edge",
    "z → a",
    702.0,
    330.0,
    266.0,
    0.0,
    green,
    next=fn(state) { { ..state, x: 542.0, y: 300.0, width: 196.0, } },
    last_stage=fn(state) { { ..state, x: 738.0, width: -196.0, } },
  )
  builder.arrow(
    "cost-edge",
    "a → C",
    862.0,
    300.0,
    196.0,
    0.0,
    coral,
    next=show,
    last_stage=fn(state) { { ..state, x: 1058.0, width: -196.0, } },
  )
  builder.hide_initial("cost-edge")
  builder.equation(
    "weighted-operation",
    "Fixed input and bias",
    "\\times a_{\\mathrm{prev}}+b",
    445.0,
    248.0,
    27.0,
    color=cyan,
    next=hide,
  )
  builder.equation(
    "weighted-equation",
    "z = w a_prev + b",
    "z = w\\,a_{\\mathrm{prev}} + b",
    395.0,
    488.0,
    35.0,
    color=green,
    next=fn(state) { { ..state, x: 330.0, y: 608.0, fontSize: 28.0, } },
    last_stage=hide,
  )
  builder.equation(
    "activation-equation",
    "a = sigmoid(z)",
    "a = \\sigma(z)",
    925.0,
    488.0,
    35.0,
    color=ink,
    next=fn(state) { { ..state, x: 790.0, y: 608.0, fontSize: 28.0, } },
    last_stage=hide,
  )
  builder.equation(
    "cost-equation",
    "Squared error",
    "C = (a-y)^2",
    770.0,
    493.0,
    39.0,
    color=coral,
    next=show,
    last_stage=hide,
  )
  builder.hide_initial("cost-equation")
  builder.object(
    "target-node",
    @scene.Circle,
    "Target · node",
    {
      ..sample_state(@scene.Circle),
      x: 1120.0,
      y: 464.0,
      width: 70.0,
      height: 70.0,
      fill: "#121108",
      stroke: yellow,
      strokeWidth: 1.5,
      visible: false,
    },
    next=show,
    last_stage=hide,
    group=Some("group-target"),
  )
  builder.equation(
    "target-label",
    "Target y",
    "y",
    1120.0,
    464.0,
    36.0,
    color=yellow,
    next=show,
    last_stage=hide,
    group=Some("group-target"),
  )
  builder.hide_initial("target-label")
  builder.arrow(
    "target-edge",
    "y → C",
    1120.0,
    421.0,
    0.0,
    -58.0,
    yellow,
    next=show,
    last_stage=hide,
  )
  builder.hide_initial("target-edge")
  builder.object(
    "target-caption",
    @scene.Text,
    "Target caption",
    {
      ..sample_state(@scene.Text),
      x: 1120.0,
      y: 530.0,
      text: "target",
      fontSize: 17.0,
      fill: yellow,
      visible: false,
    },
    next=show,
    last_stage=hide,
    group=Some("group-target"),
  )
  builder.equation(
    "weight-derivative",
    "Local derivative: dz/dw",
    "\\frac{\\partial z}{\\partial w}=a_{\\mathrm{prev}}",
    320.0,
    426.0,
    28.0,
    color=cyan,
    next=hide,
    last_stage=show,
  )
  builder.equation(
    "activation-derivative",
    "Local derivative: da/dz",
    "\\frac{\\partial a}{\\partial z}=\\sigma'(z)",
    640.0,
    426.0,
    28.0,
    color=green,
    next=hide,
    last_stage=show,
  )
  builder.equation(
    "cost-derivative",
    "Local derivative: dC/da",
    "\\frac{\\partial C}{\\partial a}=2(a-y)",
    960.0,
    426.0,
    28.0,
    color=coral,
    next=hide,
    last_stage=show,
  )
  builder.equation(
    "chain-rule",
    "Chain rule: dC/dw",
    "\\frac{\\partial C}{\\partial w}=2(a-y)\\,\\sigma'(z)\\,a_{\\mathrm{prev}}",
    640.0,
    584.0,
    40.0,
    color=ink,
    next=hide,
    last_stage=show,
  )
  for
    id in [
      "weight-derivative", "activation-derivative", "cost-derivative", "chain-rule",
    ] {
    builder.hide_initial(id)
  }
  let reveal : @scene.Transition = {
    id: "reveal-loss",
    fromId: "forward",
    toId: "loss",
    duration: 1800.0,
    tracks: Map([]),
  }
  let trace : @scene.Transition = {
    id: "trace-gradient",
    fromId: "loss",
    toId: "gradient",
    duration: 2100.0,
    tracks: Map([]),
  }
  for
    id in [
      "weight-node", "weight-label", "weighted-node", "weighted-label", "activation-node",
      "activation-label", "weight-edge", "activation-edge", "weighted-equation",
      "activation-equation",
    ] {
    sample_animate(reveal, id, @scene.Move, 0.0, 750.0)
  }
  sample_animate(reveal, "weighted-operation", @scene.Fade, 0.0, 300.0)
  sample_animate(reveal, "cost-edge", @scene.Write, 400.0, 500.0)
  sample_animate(reveal, "cost-node", @scene.Grow, 650.0, 350.0)
  sample_animate(reveal, "cost-label", @scene.Write, 800.0, 400.0)
  sample_animate(reveal, "target-node", @scene.Grow, 850.0, 350.0)
  sample_animate(reveal, "target-label", @scene.Write, 1000.0, 350.0)
  sample_animate(reveal, "target-edge", @scene.Write, 1100.0, 400.0)
  sample_animate(reveal, "target-caption", @scene.Fade, 1100.0, 400.0)
  sample_animate(
    reveal,
    "cost-equation",
    @scene.Write,
    900.0,
    850.0,
    sequential=true,
  )
  for
    id in [
      "target-node", "target-label", "target-edge", "target-caption", "weighted-equation",
      "activation-equation", "cost-equation",
    ] {
    sample_animate(trace, id, @scene.Fade, 0.0, 350.0)
  }
  sample_animate(trace, "cost-edge", @scene.Move, 150.0, 350.0)
  sample_animate(
    trace,
    "cost-derivative",
    @scene.Write,
    300.0,
    450.0,
    sequential=true,
  )
  sample_animate(trace, "activation-edge", @scene.Move, 500.0, 350.0)
  sample_animate(
    trace,
    "activation-derivative",
    @scene.Write,
    650.0,
    450.0,
    sequential=true,
  )
  sample_animate(trace, "weight-edge", @scene.Move, 850.0, 350.0)
  sample_animate(
    trace,
    "weight-derivative",
    @scene.Write,
    1000.0,
    450.0,
    sequential=true,
  )
  sample_animate(trace, "weight-node", @scene.Move, 1100.0, 400.0)
  sample_animate(
    trace,
    "chain-rule",
    @scene.Write,
    1250.0,
    850.0,
    sequential=true,
  )
  let compositions = Map([])
  for composition in builder.compositions {
    compositions[composition.id] = composition
  }
  let scene : @scene.Scene = {
    id: "calculus",
    name: "How a derivative travels",
    width: 1280.0,
    height: 720.0,
    background: "#000000",
    objects: builder.objects,
    compositionOrder: builder.compositions.map(fn(c) { c.id }),
    compositions,
    transitions: Map([(reveal.id, reveal), (trace.id, trace)]),
    audioTracks: None,
    deleted: None,
  }
  {
    version: 1,
    name: "A change, carried through.",
    sceneOrder: [scene.id],
    scenes: Map([(scene.id, scene)]),
  }
}
