///|
priv struct CalculusBuilder {
  compositions : Array[@scene.Composition]
  objects : Map[String, @scene.SceneObject]
}

///|
fn sample_state(kind : @scene.ObjectKind) -> @scene.ObjectState {
  {
    ..@scene.default_state(kind),
    fill: "#e8e8ee",
    stroke: "#e8e8ee",
    strokeWidth: 0.0,
  }
}

///|
fn CalculusBuilder::object(
  self : CalculusBuilder,
  id : String,
  kind : @scene.ObjectKind,
  name : String,
  initial : @scene.ObjectState,
  next? : (@scene.ObjectState) -> @scene.ObjectState = fn(state) { state },
  last_stage? : (@scene.ObjectState) -> @scene.ObjectState = fn(state) { state },
  group? : String? = None,
) -> Unit {
  self.objects[id] = sample_object(id, name, kind, self.objects.length(), group)
  self.compositions[0].states[id] = initial
  let second = next(initial)
  self.compositions[1].states[id] = second
  self.compositions[2].states[id] = last_stage(second)
}

///|
fn CalculusBuilder::equation(
  self : CalculusBuilder,
  id : String,
  name : String,
  text : String,
  x : Double,
  y : Double,
  size : Double,
  color? : String = "#e8e8ee",
  next? : (@scene.ObjectState) -> @scene.ObjectState = fn(state) { state },
  last_stage? : (@scene.ObjectState) -> @scene.ObjectState = fn(state) { state },
  group? : String? = None,
) -> Unit {
  self.object(
    id,
    @scene.Equation,
    name,
    {
      ..sample_state(@scene.Equation),
      text,
      x,
      y,
      fontSize: size,
      width: 320.0,
      height: 100.0,
      fill: color,
    },
    next~,
    last_stage~,
    group~,
  )
}

///|
fn CalculusBuilder::hide_initial(self : CalculusBuilder, id : String) -> Unit {
  self.compositions[0].states[id] = {
    ..self.compositions[0].states[id],
    visible: false,
  }
}

///|
fn CalculusBuilder::node(
  self : CalculusBuilder,
  id : String,
  label : String,
  name : String,
  x : Double,
  to_x : Double,
  color : String,
  visible? : Bool = true,
) -> Unit {
  let group = Some("group-" + id)
  self.object(
    id + "-node",
    @scene.Circle,
    name + " · node",
    {
      ..sample_state(@scene.Circle),
      x,
      y: 330.0,
      width: 108.0,
      height: 108.0,
      fill: "#080b10",
      stroke: color,
      strokeWidth: 2.0,
      visible,
    },
    next=fn(state) { { ..state, x: to_x, y: 300.0, visible: true, } },
    last_stage=fn(state) {
      if id == "weight" {
        { ..state, effect: @scene.Glow, }
      } else {
        state
      }
    },
    group~,
  )
  self.equation(
    id + "-label",
    name,
    label,
    x,
    330.0,
    44.0,
    color~,
    next=fn(state) { { ..state, x: to_x, y: 300.0, visible: true, } },
    group~,
  )
  if !visible {
    self.hide_initial(id + "-label")
  }
}

///|
fn CalculusBuilder::arrow(
  self : CalculusBuilder,
  id : String,
  name : String,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  color : String,
  next? : (@scene.ObjectState) -> @scene.ObjectState = fn(state) { state },
  last_stage? : (@scene.ObjectState) -> @scene.ObjectState = fn(state) { state },
) -> Unit {
  self.object(
    id,
    @scene.Arrow,
    name,
    {
      ..sample_state(@scene.Arrow),
      x,
      y,
      width,
      height,
      fill: color,
      stroke: color,
      strokeWidth: 2.0,
    },
    next~,
    last_stage~,
  )
}

///|
fn sample_animate(
  target : @scene.Transition,
  id : String,
  kind : @scene.AnimationKind,
  start : Double,
  duration : Double,
  sequential? : Bool = false,
) -> Unit {
  target.tracks[id] = {
    ..@scene.default_track(id, duration),
    type_: kind,
    start,
    order: if sequential {
      "sequential"
    } else {
      "together"
    },
  }
}
