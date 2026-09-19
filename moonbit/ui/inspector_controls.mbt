///|
fn color_input(input : @core.Any) -> @react.Element {
  let value : String = input._get("value").cast()
  let label : String = input._get("label").cast()
  let (draft, set_draft) = @react.use_state((None : String?))
  let dirty = @react.use_ref(Some(false))
  let code = (if value.has_prefix("#") { value[1:].to_owned() } else { value }).to_upper()
  let change : (String) -> Unit = input._get("onChange").cast()
  h("div", { "className": @core.any("color-field") }, [
    h(
      "label",
      {
        "className": @core.any("color-swatch"),
        "style": host_record({ "background": @core.any(value) }),
      },
      [
        h(
          "input",
          {
            "aria-label": @core.any(label + "の色を選択"),
            "type": @core.any("color"),
            "value": @core.any(value),
            "onChange": @core.any(fn(event : @core.Any) {
              change(event._get("target")._get("value").cast())
            }),
          },
          [],
        ),
      ],
    ),
    h(
      "input",
      {
        "aria-label": @core.any(label + "のカラーコード"),
        "value": @core.any(draft.unwrap_or(code)),
        "onFocus": @core.any(fn() {
          dirty.set_current(Some(false))
          set_draft(Some(code))
        }),
        "onChange": @core.any(fn(event : @core.Any) {
          dirty.set_current(Some(true))
          set_draft(Some(event._get("target")._get("value").cast()))
        }),
        "onBlur": @core.any(fn() {
          if dirty.get_current() == Some(true) &&
            draft is Some(text) &&
            @editor.color_code(text) is Some(color) {
            change(color)
          }
          dirty.set_current(Some(false))
          set_draft(None)
        }),
        "onKeyDown": @core.any(fn(event : @core.Any) {
          let key : String = event._get("key").cast()
          if key == "Escape" {
            dirty.set_current(Some(false))
            set_draft(None)
            blur(event)
          }
          if key == "Enter" {
            blur(event)
          }
        }),
      },
      [],
    ),
    h("span", Map([]), [
      "100",
      h("span", { "className": @core.any("muted") }, [" %"]),
    ]),
  ])
}

///|
fn number_field(
  label : String,
  accessible : String,
  value : Double,
  change : (Double) -> Unit,
  min? : Double = -10000.0,
  max? : Double = 10000.0,
  suffix? : String = "",
) -> @react.Element {
  component(field, { "label": @core.any(label) }, [
    component(
      number_input,
      {
        "label": @core.any(accessible),
        "value": @core.any(value),
        "onChange": @core.any(change),
        "min": @core.any(min),
        "max": @core.any(max),
        "suffix": @core.any(suffix),
      },
      [],
    ),
  ])
}

///|
fn inspector_section(
  title : String,
  nodes : Array[&@react.ReactNode],
) -> @react.Element {
  component(section, { "title": @core.any(title) }, nodes)
}

///|
fn inspector_button(
  label : String,
  image : String,
  action : () -> Unit,
  class_name? : String = "subtle-button full-width",
  disabled? : Bool = false,
) -> @react.Element {
  let nodes : Array[&@react.ReactNode] = []
  if !image.is_empty() {
    nodes.push(icon(image, 14))
  }
  nodes.push(label)
  h(
    "button",
    {
      "className": @core.any(class_name),
      "disabled": @core.any(disabled),
      "onClick": @core.any(action),
    },
    nodes,
  )
}

///|
priv struct InspectorController {
  editor : @core.Any
  scene : @core.Any
  store : @core.Any
  scene_id : String
  composition_id : String
  selected : FixedArray[String]
}

///|
fn InspectorController::can_edit(self : InspectorController) -> Bool {
  let scene = self.store._call("scene", [@core.any(self.scene_id)])
  !self.selected
  .iter()
  .any(fn(id) {
    let object = scene._get("objects")._get(id)
    truthy(object) && truthy(object._get("locked"))
  })
}

///|
fn InspectorController::update(
  self : InspectorController,
  patch : Map[String, @core.Any],
) -> Unit {
  if !self.can_edit() {
    return
  }
  let value = host_record(patch)
  for id in self.selected {
    self.store._call("updateState", [
      @core.any(self.scene_id),
      @core.any(self.composition_id),
      @core.any(id),
      value,
    ])
    |> ignore
  }
}

///|
fn InspectorController::number(
  self : InspectorController,
  key : String,
  value : Double,
) -> Unit {
  self.update(Map([(key, @core.any(value))]))
}

///|
fn InspectorController::align(
  self : InspectorController,
  axis : String,
  alignment : @editor.Alignment,
) -> Unit {
  if !self.can_edit() {
    return
  }
  let composition = self.scene._get("compositions")._get(self.composition_id)
  let frame = @boundary.composition_frame(
    self.scene,
    composition,
    @core.undefined(),
  )
  let objects : FixedArray[@core.Any] = frame._get("objects").cast()
  let dimension = if axis == "x" { "width" } else { "height" }
  let items : Array[@editor.AlignmentItem] = []
  let positions : Map[String, @scene.Point] = Map([])
  let origins : Map[String, @scene.Point] = Map([])
  for item in objects {
    let id : String = item._get("object")._get("id").cast()
    if !self.selected.iter().any(fn(chosen) { chosen == id }) {
      continue
    }
    let state = @boundary.read_object_state(item._get("state"))
    let origin : @scene.Point = { x: state.x, y: state.y, }
    let matrix = stage_item_matrix(item)
    let bounds = @geometry.matrix_bounds(
      stage_bounds(self.editor._get("renderer")._call("objectBounds", [item])),
      origin,
      matrix,
    )
    let position = @boundary.parent_matrix(self.scene, self.composition_id, id).point(
      origin,
    )
    positions[id] = position
    origins[id] = origin
    items.push({
      id,
      position: if axis == "x" {
        position.x
      } else {
        position.y
      },
      low: if axis == "x" {
        bounds.x
      } else {
        bounds.y
      },
      extent: if axis == "x" {
        bounds.width
      } else {
        bounds.height
      },
    })
  }
  let plan = @editor.alignment_plan(
    items,
    self.scene._get(dimension).cast(),
    alignment,
  )
  if plan.is_empty() {
    return
  }
  let moves : Array[@editor.WorldMove] = plan.map(fn(pair) {
    let (id, position) = pair
    {
      id,
      start: origins[id],
      delta: if axis == "x" {
        { x: position - positions[id].x, y: 0.0, }
      } else {
        { x: 0.0, y: position - positions[id].y, }
      },
    }
  })
  let changes = @boundary.object_position_changes(
    self.scene_id,
    self.composition_id,
    @boundary.project_world_moves(self.scene, self.composition_id, moves),
  )
  self.store._call("edit", [@core.any(host_array(changes))]) |> ignore
}

///|
fn InspectorController::arrange(
  self : InspectorController,
  front : Bool,
) -> Unit {
  if !self.can_edit() {
    return
  }
  let ordered = @boundary.ordered_objects(
    self.store._call("scene", [@core.any(self.scene_id)]),
  )
  let chosen = ordered
    .iter()
    .filter(fn(item) {
      let id : String = item._get("id").cast()
      self.selected.iter().any(fn(chosen) { chosen == id })
    })
    .to_array()
  if chosen.is_empty() {
    return
  }
  let mut edge : Double = ordered[0]._get("order").cast()
  for item in ordered {
    let order : Double = item._get("order").cast()
    edge = if front {
      @scene.maximum(edge, order)
    } else {
      @scene.minimum(edge, order)
    }
  }
  if !front {
    edge -= chosen.length().to_double() + 1.0
  }
  let changes : Array[@core.Any] = []
  for index, item in chosen {
    let id : String = item._get("id").cast()
    for
      change in @boundary.changes_for(
        ["scenes", self.scene_id, "objects", id],
        host_record({ "order": @core.any(edge + index.to_double() + 1.0) }),
      ) {
      changes.push(change)
    }
  }
  self.store._call("edit", [@core.any(host_array(changes))]) |> ignore
}
