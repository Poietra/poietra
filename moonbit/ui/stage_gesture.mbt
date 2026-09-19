///|
fn StageController::finish(self : StageController, cancel : Bool) -> Unit {
  guard self.gesture.get_current() is Some(current) else { return }
  self.gesture.set_current(None)
  @core.throwable(fn() {
    if cancel &&
      truthy(current.undo) &&
      !@core.equal(current.undo, current.undo_before) &&
      @core.equal(top_undo(self.store), current.undo) {
      self.store._call("rollbackGesture", [current.undo]) |> ignore
    }
  }) catch {
    failure =>
      self.editor
      ._get("notify")
      ._invoke([
        @core.any(
          error_message(
            ui_native_error(failure),
            "操作を取り消せませんでした。",
          ),
        ),
      ])
      |> ignore
  }
  match current.mode {
    SelectArea(area) => if cancel { self.select(host_array(area.initial)) }
    _ => ui_quiet(self.store, "endGesture")
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
      encode_status(
        Some({
          kind: if cancel {
            @editor.Cancelled
          } else {
            @editor.Complete
          },
          label,
          detail,
        }),
      ),
    )
  } else {
    (self.report)(@core.null())
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
  patch : @core.Any?,
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
      let rotation : Double = patch
        .map(fn(patch) { optional_number(patch, "rotation", state.rotation) })
        .unwrap_or(state.rotation)
      ("回転", coordinate(rotation) + "° · Shift で角度を固定")
    }
    TransformObject(_, _, state, _, _) => {
      let detail = if patch is Some(patch) &&
        !@core.is_undefined(patch._get("fontSize")) {
        coordinate(patch._get("fontSize").cast()) + " px"
      } else {
        let width = patch
          .map(fn(patch) { optional_number(patch, "width", state.width) })
          .unwrap_or(state.width)
        let height = patch
          .map(fn(patch) { optional_number(patch, "height", state.height) })
          .unwrap_or(state.height)
        coordinate(width) + " × " + coordinate(height) + " px"
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
  (self.report)(encode_status(Some(status)))
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
    self.store._call("beginGesture", []) |> ignore
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
  let object = self.scene._get("objects")._get(id)
  if !truthy(object) || truthy(object._get("locked")) {
    return
  }
  let kind = @boundary.read_object_kind(object._get("kind"))
  if !(kind is Text || kind is Equation) {
    return
  }
  prevent_default(event)
  self.editor
  ._get("requestTextEdit")
  ._invoke([@core.any(id), @core.any(self.composition_id)])
  |> ignore
}
