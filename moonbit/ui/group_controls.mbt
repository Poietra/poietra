///|
pub fn group_controls(_input : @core.Any) -> @react.Element {
  let editor = use_editor()
  let scene = editor._get("scene")
  let store = editor._get("store")
  let ids : FixedArray[String] = editor._get("selectedIds").cast()
  let selected = ids
    .iter()
    .map(fn(id) { scene._get("objects")._get(id) })
    .filter(truthy)
    .to_array()
  let editable = @boundary.editable_group_members(scene, ids)
  let groups : Array[String] = []
  for object in selected {
    let group = object._get("groupId")
    if truthy(group) && !groups.contains(group.cast()) {
      groups.push(group.cast())
    }
  }
  if selected.is_empty() || (selected.length() == 1 && groups.is_empty()) {
    return @react.fragment([])
  }
  let members : FixedArray[@core.Any] = if groups.length() == 1 {
    @boundary.group_members(scene, groups[0])
  } else {
    []
  }
  let playback = truthy(editor._get("viewingPlayback"))
  let content : Array[&@react.ReactNode] = [
    h("div", { "className": @core.any("group-control-actions") }, [
      h(
        "button",
        {
          "className": @core.any("subtle-button"),
          "aria-label": @core.any("Group"),
          "disabled": @core.any(
            selected.length() <= 1 || editable.length() < 2 || playback,
          ),
          "onClick": @core.any(fn() {
            store._call("link", [scene._get("id"), @core.any(ids)]) |> ignore
            editor
            ._get("notify")
            ._invoke([
              @core.any(
                "グループ化しました。メンバーのドラッグで一緒に移動できます。",
              ),
            ])
            |> ignore
          }),
        },
        [
          icon("Group", 14),
          "Group",
          h("span", { "className": @core.any("shortcut") }, ["⌘G"]),
        ],
      ),
      h(
        "button",
        {
          "className": @core.any("subtle-button"),
          "disabled": @core.any(
            playback ||
            !editable.iter().any(fn(object) { truthy(object._get("groupId")) }),
          ),
          "onClick": @core.any(fn() {
            store._call("unlink", [scene._get("id"), @core.any(ids)]) |> ignore
            editor
            ._get("notify")
            ._invoke([
              @core.any(
                "グループを解除しました。Undo で戻せます。",
              ),
            ])
            |> ignore
          }),
        },
        [icon("Ungroup", 14), "Ungroup"],
      ),
    ]),
  ]
  if members.length() > 1 &&
    !members
    .iter()
    .all(fn(object) {
      ids.iter().any(fn(id) { @core.equal(@core.any(id), object._get("id")) })
    }) {
    content.push(
      h(
        "button",
        {
          "className": @core.any("text-button group-select-all"),
          "onClick": @core.any(fn() {
            let selected = FixedArray::makei(members.length(), fn(index) {
              members[index]._get("id")
            })
            editor._get("setSelectedIds")._invoke([@core.any(selected)])
            |> ignore
          }),
        },
        [icon("MousePointer2", 12), "Select group · \{members.length()}"],
      ),
    )
  }
  if !groups.is_empty() {
    content.push(
      h("p", Map([]), [
        "表示中・未ロックのメンバーが一緒に移動します。行で個別に選択できます。",
      ]),
    )
  }
  if selected.any(fn(object) { truthy(object._get("locked")) }) {
    content.push(
      h("p", Map([]), ["ロック中のメンバーは変更しません。"]),
    )
  }
  h(
    "section",
    {
      "className": @core.any("group-controls"),
      "aria-label": @core.any("Grouping"),
    },
    content,
  )
}

///|
fn common_number(input : @core.Any) -> @react.Element {
  let (draft, set_draft) = @react.use_state(NumberDraft::Idle)
  let dirty = @react.use_ref(Some(false))
  let value = input._get("value")
  let high : Double = input._get("max").cast()
  h("span", { "className": @core.any("number-input") }, [
    h(
      "input",
      {
        "aria-label": input._get("label"),
        "type": @core.any("number"),
        "min": @core.any(0),
        "max": @core.any(high),
        "step": @core.any(1),
        "placeholder": @core.any("Mixed"),
        "value": match draft {
          Editing(text) => @core.any(text)
          Idle => if @core.is_nullish(value) { @core.any("") } else { value }
        },
        "onFocus": @core.any(fn() {
          dirty.set_current(Some(false))
          set_draft(
            Editing(
              if @core.is_undefined(value) {
                ""
              } else {
                string_value(value)
              },
            ),
          )
        }),
        "onChange": @core.any(fn(event : @core.Any) {
          dirty.set_current(Some(true))
          set_draft(Editing(event._get("target")._get("value").cast()))
        }),
        "onBlur": @core.any(fn() {
          if dirty.get_current() == Some(true) &&
            draft is Editing(text) &&
            !@editor.trim_text(text).is_empty() {
            let number = number_value(text)
            if !number.is_nan() && !number.is_inf() {
              input
              ._get("onCommit")
              ._invoke([@core.any(number.min(high).max(0.0))])
              |> ignore
            }
          }
          dirty.set_current(Some(false))
          set_draft(Idle)
        }),
        "onKeyDown": @core.any(fn(event : @core.Any) {
          let key : String = event._get("key").cast()
          if key == "Escape" {
            dirty.set_current(Some(false))
          }
          if key == "Escape" || key == "Enter" {
            blur(event)
          }
        }),
      },
      [],
    ),
    h("span", Map([]), ["ms"]),
  ])
}
