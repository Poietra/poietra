///|
pub(all) enum KeyboardAction {
  IgnoreShortcut
  RememberPaste(Bool)
  UndoShortcut
  RedoShortcut
  DuplicateSelection
  SelectAllObjects
  GroupSelection(Bool)
  NudgeSelection(Int, Int)
  TogglePlayback
  ClearSelection
  HideSelection
  ChooseTool(StageTool)
  ReturnFromPreview
  PreviewNotice
}

///|
pub(all) struct NudgeTarget {
  scene : String
  composition : String
  objects : Array[String]
} derive(Eq)

///|
pub fn keyboard_action(
  key : String,
  code : String,
  command : Bool,
  shift : Bool,
  preview : Bool,
  has_scene : Bool,
  has_targets : Bool,
) -> KeyboardAction {
  let lower = key.to_lower()
  let direction = match key {
    "ArrowLeft" => Some((-1, 0))
    "ArrowRight" => Some((1, 0))
    "ArrowUp" => Some((0, -1))
    "ArrowDown" => Some((0, 1))
    _ => None
  }
  if preview &&
    (
      key == "Delete" ||
      key == "Backspace" ||
      direction is Some(_) ||
      (command && ["d", "g", "a"].contains(lower))
    ) {
    return PreviewNotice
  }
  if preview && key == "Escape" {
    return ReturnFromPreview
  }
  if command {
    return match lower {
      "v" => RememberPaste(shift)
      "z" => if shift { RedoShortcut } else { UndoShortcut }
      "d" if has_scene && has_targets => DuplicateSelection
      "a" if has_scene => SelectAllObjects
      "g" if has_scene && has_targets => GroupSelection(!shift)
      _ => IgnoreShortcut
    }
  }
  if direction is Some((x, y)) && has_scene && has_targets {
    let step = if shift { 10 } else { 1 }
    return NudgeSelection(x * step, y * step)
  }
  if code == "Space" {
    return TogglePlayback
  }
  if key == "Escape" {
    return ClearSelection
  }
  if (key == "Delete" || key == "Backspace") && has_scene && has_targets {
    return HideSelection
  }
  match lower {
    "v" => ChooseTool(SelectTool)
    "r" => ChooseTool(DrawTool(@scene.Rectangle))
    "o" => ChooseTool(DrawTool(@scene.Circle))
    "t" => ChooseTool(DrawTool(@scene.Text))
    "e" => ChooseTool(DrawTool(@scene.Equation))
    "p" => ChooseTool(DrawTool(@scene.Path))
    "l" => ChooseTool(DrawTool(@scene.Arrow))
    _ => IgnoreShortcut
  }
}

///|
pub fn shortcut_consumes(action : KeyboardAction) -> Bool {
  match action {
    IgnoreShortcut | RememberPaste(_) | ClearSelection | ChooseTool(_) => false
    _ => true
  }
}
