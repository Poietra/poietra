///|
let cached_layer_row : @core.Any = memo_component(layer_row)

///|
fn layer_row(input : @core.Any) -> @react.Element {
  let id : String = input._get("id").cast()
  let name : String = input._get("name").cast()
  let scene_id : String = input._get("sceneId").cast()
  let composition_id : String = input._get("compositionId").cast()
  let nested : Bool = input._get("nested").cast()
  let visible : Bool = input._get("visible").cast()
  let locked : Bool = input._get("locked").cast()
  let selected : Bool = input._get("selected").cast()
  let playback : Bool = input._get("playback").cast()
  let store = input._get("store")
  let choose : (Array[String], Bool) -> Unit = input._get("choose").cast()
  h(
    "div",
    {
      "key": @core.any(id),
      "data-layer-id": @core.any(id),
      "className": classes([
        @core.any("layer-row"),
        @core.any(if selected { "selected" } else { "" }),
        @core.any(if nested { "nested" } else { "" }),
      ]),
    },
    [
      h(
        "button",
        {
          "className": classes([
            @core.any("layer-select"),
            @core.any(if visible { "" } else { "dimmed" }),
          ]),
          "onClick": @core.any(fn(event : @core.Any) {
            choose([id], truthy(event._get("shiftKey")))
          }),
          "aria-pressed": @core.any(selected),
        },
        [
          component(object_icon, { "kind": input._get("kind") }, []),
          h("span", Map([]), [name]),
        ],
      ),
      h(
        "button",
        {
          "className": @core.any("layer-visibility"),
          "aria-label": @core.any(
            name +
            " を" +
            (if locked { "ロック解除" } else { "ロック" }),
          ),
          "onClick": @core.any(fn() {
            let current = store
              ._call("scene", [@core.any(scene_id)])
              ._get("objects")
              ._get(id)
            store._call("setObject", [
              @core.any(scene_id),
              @core.any(id),
              host_record({
                "locked": @core.any(
                  !(truthy(current) && truthy(current._get("locked"))),
                ),
              }),
            ])
            |> ignore
          }),
        },
        [icon(if locked { "LockKeyhole" } else { "UnlockKeyhole" }, 12)],
      ),
      h(
        "button",
        {
          "className": @core.any("layer-visibility"),
          "disabled": @core.any(locked || playback),
          "aria-label": @core.any(
            name + " を" + (if visible { "非表示" } else { "表示" }),
          ),
          "onClick": @core.any(fn() {
            let current = store
              ._call("scene", [@core.any(scene_id)])
              ._get("objects")
              ._get(id)
            if !(truthy(current) && truthy(current._get("locked"))) {
              store._call("updateState", [
                @core.any(scene_id),
                @core.any(composition_id),
                @core.any(id),
                host_record({ "visible": @core.any(!visible) }),
              ])
              |> ignore
            }
          }),
        },
        [icon(if visible { "Eye" } else { "EyeOff" }, 13)],
      ),
    ],
  )
}

///|
priv struct LayerIndex {
  objects : Array[@core.Any]
  groups : Map[String, Array[@core.Any]]
  group_ids : Array[String]
}

///|
fn layer_index(scene : @core.Any) -> LayerIndex {
  let objects = @boundary.ordered_objects(scene).iter().to_array()
  let groups : Map[String, Array[@core.Any]] = Map([])
  let group_ids : Array[String] = []
  for object in objects {
    let id = object._get("groupId")
    if truthy(id) {
      let key : String = id.cast()
      if !groups.contains(key) {
        groups[key] = []
        group_ids.push(key)
      }
      groups[key].push(object)
    }
  }
  objects.rev_in_place()
  { objects, groups, group_ids, }
}

///|
pub fn object_icon(input : @core.Any) -> @react.Element {
  let name = match @boundary.read_object_kind(input._get("kind")) {
    Circle => "Circle"
    Rectangle => "Square"
    Text => "Type"
    Equation => "Sigma"
    Path => "Spline"
    Arrow => "ArrowUpRight"
    NumberLine => "Minus"
    Image => "Image"
    Video => "Film"
  }
  icon(name, optional_number(input, "size", 15.0).to_int(), props={
    "strokeWidth": @core.any(1.6),
  })
}

///|
pub fn sidebar(input : @core.Any) -> @react.Element {
  let editor = use_editor_state()
  let scene = editor._get("scene")
  let scene_id : String = scene._get("id").cast()
  let composition_id : String = editor._get("compositionId").cast()
  let store = editor._get("store")
  let selection = editor._get("selection")
  let selected_ids : FixedArray[String] = editor._get("selectedIds").cast()
  let selected = selected_ids.iter().to_array()
  let selected_set : Map[String, Bool] = Map([])
  for id in selected_ids {
    selected_set[id] = true
  }
  let select : (@core.Any) -> Unit = editor._get("select").cast()
  let notify : (String) -> Unit = editor._get("notify").cast()
  let playback = truthy(editor._get("viewingPlayback"))
  let (searching, set_searching) = @react.use_state(false)
  let (query, set_query) = @react.use_state("")
  let (collapsed, set_collapsed) = @react.use_state(
    (Map([]) : Map[String, Bool]),
  )
  let index = @react.use_memo(fn() { layer_index(scene) }, [
    scene._get("objects"),
  ])
  let folded = query.to_lower()
  let objects = index.objects.filter(fn(object) {
    let name : String = object._get("name").cast()
    name.to_lower().contains(folded)
  })
  let choose = fn(ids : Array[String], additive : Bool) {
    editor
    ._get("setSelectedIds")
    ._invoke([
      @core.any(
        host_array(@editor.select_layer_members(selected, ids, additive)),
      ),
    ])
    |> ignore
  }
  let change_composition = fn(id : String, duplicate : Bool) {
    stop_capturing(store)
    attempt(
      fn() {
        if duplicate {
          let created = @boundary.duplicate_composition(
            store._get("doc"),
            scene_id,
            id,
            shared_runtime(),
          )
          select(
            host_record({
              "kind": @core.any("composition"),
              "id": @core.any(created),
            }),
          )
          notify(
            "Composition を複製しました。配置と見た目を個別に編集できます。",
          )
        } else {
          let removed = @boundary.delete_composition(
            store._get("doc"),
            scene_id,
            id,
            shared_runtime(),
          )
          let current_id : String = selection._get("id").cast()
          let current_kind : String = selection._get("kind").cast()
          let removed_ids : FixedArray[String] = removed
            ._get("removedTransitionIds")
            .cast()
          if (current_kind == "composition" && current_id == id) ||
            (
              current_kind == "transition" &&
              removed_ids.iter().any(fn(id) { id == current_id })
            ) {
            select(
              host_record({
                "kind": @core.any("composition"),
                "id": removed._get("selectedId"),
              }),
            )
          }
          notify(
            "Composition と前後のアニメーションを削除しました。元に戻すで復元できます。",
          )
        }
      },
      notify,
      "Composition を変更できませんでした。",
    )
    stop_capturing(store)
  }
  // Stable row callbacks read the current selection instead of retaining old IDs.
  let current_choose = @react.use_ref(Some(choose))
  current_choose.set_current(Some(choose))
  let choose_row = @react.use_memo(
    fn() {
      fn(ids : Array[String], additive : Bool) {
        let latest = current_choose.get_current().unwrap()
        latest(ids, additive)
      }
    },
    [],
  )
  let row = fn(object : @core.Any, nested : Bool) {
    let id : String = object._get("id").cast()
    let state = @boundary.state_for(scene, composition_id, id)
    keyed_element(
      cached_layer_row,
      {
        "key": @core.any(id),
        "id": @core.any(id),
        "name": object._get("name"),
        "kind": object._get("kind"),
        "sceneId": @core.any(scene_id),
        "compositionId": @core.any(composition_id),
        "nested": @core.any(nested),
        "visible": @core.any(truthy(state) && truthy(state._get("visible"))),
        "locked": @core.any(truthy(object._get("locked"))),
        "selected": @core.any(selected_set.contains(id)),
        "playback": @core.any(playback),
        "store": store,
        "choose": @core.any(choose_row),
      },
      [],
    )
  }
  let project = store._call("snapshot", [])._get("project")
  let scene_count = if truthy(project) {
    project._get("sceneOrder")._get("length").cast()
  } else {
    0
  }
  let content : Array[&@react.ReactNode] = [
    h("div", { "className": @core.any("new-scene-row") }, [
      h(
        "button",
        {
          "className": @core.any("new-scene-button"),
          "onClick": input._get("onNewScene"),
          "disabled": @core.any(scene_count >= 100),
        },
        [
          icon("Square", 13),
          h("span", Map([]), ["New scene"]),
          h("span", { "className": @core.any("shortcut") }, ["＋"]),
        ],
      ),
      component(
        icon_button,
        {
          "label": @core.any("レイヤーを検索"),
          "active": @core.any(searching),
          "onClick": @core.any(fn() { set_searching(!searching) }),
        },
        [icon("Search", 15)],
      ),
    ]),
    h("div", { "className": @core.any("sidebar-scene-title") }, [
      h("span", Map([]), ["Scenes"]),
      icon("ChevronDown", 13),
    ]),
    h("div", { "className": @core.any("sidebar-section-heading") }, [
      h("span", Map([]), ["Layers"]),
      h("span", { "className": @core.any("muted") }, [
        index.objects.length().to_string(),
      ]),
    ]),
  ]
  if selected_ids.length() > 0 {
    content.push(
      h(
        "div",
        {
          "className": @core.any("layer-selection-summary"),
          "role": @core.any("status"),
        },
        [
          h("span", Map([]), ["\{selected_ids.length()} selected"]),
          h("span", Map([]), ["Shift + click"]),
        ],
      ),
    )
  }
  if searching {
    content.push(
      h("div", { "className": @core.any("layer-search") }, [
        icon("Search", 13),
        h(
          "input",
          {
            "autoFocus": @core.any(true),
            "aria-label": @core.any("レイヤーを検索"),
            "placeholder": @core.any("Find a layer…"),
            "value": @core.any(query),
            "onChange": @core.any(fn(event : @core.Any) {
              set_query(event._get("target")._get("value").cast())
            }),
          },
          [],
        ),
      ]),
    )
  }
  let layers : Array[&@react.ReactNode] = []
  for position, object in objects {
    let group = object._get("groupId")
    if !truthy(group) {
      layers.push(row(object, false))
      continue
    }
    let group_id : String = group.cast()
    if position > 0 && @core.equal(objects[position - 1]._get("groupId"), group) {
      continue
    }
    let members = index.groups.get(group_id).unwrap_or([])
    let member_ids = members.map(fn(item) {
      let id : String = item._get("id").cast()
      id
    })
    let group_selected = member_ids.all(fn(id) { selected_set.contains(id) })
    let closed = collapsed.contains(group_id)
    let group_number = index.group_ids.search(group_id).unwrap_or(0) + 1
    let label = "Select group: " +
      members
      .map(fn(item) {
        let name : String = item._get("name").cast()
        name
      })
      .iter()
      .join(", ")
    let nodes : Array[&@react.ReactNode] = [
      h(
        "div",
        {
          "className": classes([
            @core.any("group-heading"),
            @core.any(if group_selected { "selected" } else { "" }),
          ]),
        },
        [
          h(
            "button",
            {
              "className": @core.any("group-chevron"),
              "aria-label": @core.any("グループを開閉"),
              "aria-expanded": @core.any(!closed),
              "onClick": @core.any(fn() {
                let next = collapsed.copy()
                if closed {
                  next.remove(group_id)
                } else {
                  next[group_id] = true
                }
                set_collapsed(next)
              }),
            },
            [icon(if closed { "ChevronRight" } else { "ChevronDown" }, 13)],
          ),
          h(
            "button",
            {
              "className": @core.any("group-select"),
              "aria-label": @core.any(label),
              "aria-pressed": @core.any(group_selected),
              "onClick": @core.any(fn(event : @core.Any) {
                choose(member_ids, truthy(event._get("shiftKey")))
              }),
            },
            [
              icon("Group", 13),
              h("span", Map([]), ["Group \{group_number}"]),
              h("small", Map([]), [members.length().to_string()]),
            ],
          ),
        ],
      ),
    ]
    if !closed {
      let mut cursor = position
      while cursor < objects.length() &&
            @core.equal(objects[cursor]._get("groupId"), group) {
        nodes.push(row(objects[cursor], true))
        cursor += 1
      }
    }
    let id : String = object._get("id").cast()
    layers.push(
      h(
        "div",
        {
          "className": @core.any("layer-group"),
          "key": @core.any(group_id + "-" + id),
          "data-group-id": @core.any(group_id),
        },
        nodes,
      ),
    )
  }
  if objects.is_empty() {
    layers.push(
      h("p", { "className": @core.any("sidebar-empty") }, [
        if query.is_empty() {
          "ツールで最初のオブジェクトを追加"
        } else {
          "一致するレイヤーがありません"
        },
      ]),
    )
  }
  content.push(h("div", { "className": @core.any("layer-tree") }, layers))
  let compositions : Array[&@react.ReactNode] = [
    h("div", { "className": @core.any("sidebar-section-heading") }, [
      h("span", Map([]), ["Compositions"]),
      component(
        icon_button,
        {
          "label": @core.any("Composition を追加"),
          "onClick": editor._get("appendComposition"),
        },
        [icon("Plus", 16)],
      ),
    ]),
  ]
  let order : FixedArray[String] = scene._get("compositionOrder").cast()
  for id in order {
    let composition = scene._get("compositions")._get(id)
    if !truthy(composition) {
      continue
    }
    let chosen = selection._get("kind").cast() == "composition" &&
      selection._get("id").cast() == id
    let name : String = composition._get("name").cast()
    compositions.push(
      h(
        "div",
        {
          "key": @core.any(id),
          "data-composition-id": @core.any(id),
          "className": @core.any("group flex items-center gap-0.5"),
        },
        [
          h(
            "button",
            {
              "className": classes([
                @core.any("composition-list-item min-w-0 flex-1"),
                @core.any(if chosen { "selected" } else { "" }),
              ]),
              "onClick": @core.any(fn() {
                select(
                  host_record({
                    "kind": @core.any("composition"),
                    "id": @core.any(id),
                  }),
                )
              }),
              "aria-pressed": @core.any(chosen),
            },
            [icon("Square", 14), h("span", Map([]), [name])],
          ),
          ui("Menu", "Root", Map([]), [
            ui(
              "Menu",
              "Trigger",
              {
                "className": @core.any(
                  "icon-button shrink-0 opacity-0 group-hover:opacity-100 focus-visible:opacity-100 data-[popup-open]:opacity-100",
                ),
                "aria-label": @core.any(name + " の操作"),
              },
              [icon("MoreHorizontal", 15)],
            ),
            ui("Menu", "Portal", Map([]), [
              ui(
                "Menu",
                "Positioner",
                {
                  "side": @core.any("right"),
                  "align": @core.any("start"),
                  "sideOffset": @core.any(6),
                  "className": @core.any("z-50"),
                },
                [
                  ui(
                    "Menu",
                    "Popup",
                    {
                      "className": @core.any(
                        "min-w-44 max-w-60 rounded-md border border-line bg-panel p-1 shadow-lg outline-none",
                      ),
                    },
                    [
                      scene_menu_item("Duplicate", "Copy", false, fn() {
                        change_composition(id, true)
                      }),
                      scene_menu_item("Delete", "Trash2", order.length() <= 1, fn() {
                        change_composition(id, false)
                      }),
                      h(
                        "p",
                        {
                          "className": @core.any(
                            "px-2 py-1 text-xs text-[var(--muted)]",
                          ),
                        },
                        [
                          if order.length() <= 1 {
                            "最後の Composition は残します。"
                          } else {
                            "削除すると前後のアニメーションも消えます。元に戻すで復元できます。"
                          },
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ]),
          ]),
        ],
      ),
    )
  }
  content.push(
    h("div", { "className": @core.any("composition-list") }, compositions),
  )
  content.push(
    h("div", { "className": @core.any("sidebar-bottom") }, [
      icon("Layers2", 13),
      h("span", Map([]), ["Make room for your ideas."]),
    ]),
  )
  h("aside", { "className": @core.any("left-panel") }, content)
}
