///|
fn StageController::finish(self : StageController, cancel : Bool) -> Unit {
  guard self.gesture.get_current() is Some(current) else { return }
  self.gesture.set_current(None)
  @core.throwable(fn() {
    let history = current.binding.history()
    if cancel &&
      current.undo is Some(entry) &&
      current.undo != current.undo_before &&
      history.top() == current.undo {
      history.rollback(entry)
    }
  }) catch {
    failure =>
      (self.editor.actions.notify)(
        error_message(
          ui_native_error(failure),
          "操作を取り消せませんでした。",
        ),
      )
  }
  match current.mode {
    SelectArea(area) => if cancel { self.select(host_array(area.initial)) }
    _ => current.binding.history().end()
  }
  (self.draw)(None)
  (self.marquee)(None)
  if current.changed || current.mode is DrawObject(_) {
    let label = if cancel {
      "操作をキャンセル"
    } else {
      match current.mode {
        DrawObject(_) => "オブジェクトを追加"
        SelectArea(_) => "範囲を選択"
        _ => "変更を確定"
      }
    }
    let detail = if cancel {
      None
    } else {
      match current.feedback {
        Some(status) => status.detail
        None => None
      }
    }
    (self.report)(
      Some({
        kind: if cancel {
          @editor.Cancelled
        } else {
          @editor.Complete
        },
        label,
        detail,
      }),
    )
  } else {
    (self.report)(None)
  }
  @core.throwable(fn() {
    if truthy(
        current.element._call("hasPointerCapture", [@core.any(current.pointer)]),
      ) {
      current.element._call("releasePointerCapture", [
        @core.any(current.pointer),
      ])
      |> ignore
    }
  }) catch {
    _ => ()
  }
}

///|
fn StageController::feedback(
  self : StageController,
  current : StageGesture,
  at : @scene.Point,
  value : StageTransformValue?,
) -> Unit {
  let coordinate = @boundary.format_milliseconds
  let (label, detail) = match current.mode {
    DrawObject(_) =>
      (
        "オブジェクトを描画",
        coordinate((at.x - current.start.x).abs()) +
        " × " +
        coordinate((at.y - current.start.y).abs()) +
        " px",
      )
    SelectArea(area) =>
      (
        if area.additive {
          "選択に追加"
        } else {
          "範囲を選択"
        },
        "ドラッグで囲む · Esc で戻す",
      )
    EditPath(_, _, _) =>
      (
        "ベジェ曲線を調整",
        "X " + coordinate(at.x) + " · Y " + coordinate(at.y),
      )
    TransformObject(_, @editor.RotateObject, state, _, _) => {
      let rotation = match value {
        Some(Rotation(rotation)) => rotation
        _ => state.rotation
      }
      ("回転", coordinate(rotation) + "° · Shift で角度を固定")
    }
    TransformObject(_, _, state, _, _) => {
      let (width, height, font_size) = match value {
        Some(Size(size)) => (size.width, size.height, size.font_size)
        _ => (state.width, state.height, None)
      }
      let detail = match font_size {
        Some(size) => coordinate(size) + " px"
        None => coordinate(width) + " × " + coordinate(height) + " px"
      }
      ("サイズを変更", detail)
    }
    MoveObjects(positions) =>
      (
        if positions.length() > 1 {
          "\{positions.length()} 個を移動"
        } else {
          "移動"
        },
        "ΔX " +
        coordinate(at.x - current.start.x) +
        " · ΔY " +
        coordinate(at.y - current.start.y),
      )
  }
  let status : @editor.OperationStatus = {
    kind: @editor.Active,
    label,
    detail: Some(detail),
  }
  current.feedback = Some(status)
  (self.report)(Some(status))
}

///|
fn StageController::capture(
  self : StageController,
  event : @core.Any,
  gesture : StageGesture,
) -> Unit {
  self.gesture.set_current(Some(gesture))
  if !(gesture.mode is SelectArea(_)) {
    self.feedback(gesture, gesture.start, None)
    gesture.binding.history().begin()
  }
  try
    @core.throwable(fn() {
      gesture.element._call("setPointerCapture", [@core.any(gesture.pointer)])
    })
    |> ignore
  catch {
    _ => {
      self.finish(true)
      return
    }
  }
  prevent_default(event)
}

///|
fn stage_handle(target : @core.Any, attribute : String) -> String? {
  let handle = target._call("closest", [@core.any("[" + attribute + "]")])
  if truthy(handle) {
    optional_string(handle._call("getAttribute", [@core.any(attribute)]))
  } else {
    None
  }
}

///|
fn StageController::double_click(
  self : StageController,
  event : @core.Any,
) -> Unit {
  if !self.can_edit || !self.state_editing || !(self.tool is SelectTool) {
    return
  }
  let target = event._get("target")
  if truthy(
      target._call("closest", [
        @core.any("[data-transform-handle], [data-path-handle]"),
      ]),
    ) {
    return
  }
  guard self.point(event) is Some(at) && self.hit(at, target) is Some(id) else {
    return
  }
  guard self.binding.current() is Some(snapshot) &&
    snapshot.object(id) is Some(object) &&
    !object.locked else {
    return
  }
  let kind = object.kind
  if !(kind is Text || kind is Equation) {
    return
  }
  prevent_default(event)
  (self.editor.actions.request_text_edit)(id, self.composition_id)
}
