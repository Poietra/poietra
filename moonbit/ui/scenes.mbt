///|
priv struct SceneNameDraft {
  id : String
  name : String
}

///|
priv enum SceneAction {
  Duplicate
  Delete
  Earlier
  Later
}

///|
fn stop_capturing(store : @core.Any) -> Unit {
  store._get("undoManager")._call("stopCapturing", []) |> ignore
}

///|
fn scene_menu_item(
  label : String,
  image : String,
  disabled : Bool,
  on_click : () -> Unit,
) -> @react.Element {
  ui(
    "Menu",
    "Item",
    {
      "className": @core.any(
        "flex cursor-default items-center gap-2 rounded px-2 py-2 text-xs outline-none data-[highlighted]:bg-field data-[disabled]:opacity-40",
      ),
      "disabled": @core.any(disabled),
      "onClick": @core.any(on_click),
    },
    [icon(image, 14), label],
  )
}

///|
pub fn scene_tabs(input : @core.Any) -> @react.Element {
  let project = input._get("project")
  let order : FixedArray[String] = project._get("sceneOrder").cast()
  let dependencies = [input._get("sceneId"), input._get("store")]
  for id in order {
    let scene = project._get("scenes")._get(id)
    dependencies.append([
      @core.any(id),
      if truthy(scene) {
        scene._get("name")
      } else {
        @core.undefined()
      },
    ])
  }
  let change = use_latest_action(input._get("onChange"))
  let notify = use_latest_action(input._get("notify"))
  let create = use_latest_action(input._get("onNew"))
  let props = use_presentation_props(dependencies, fn() {
    host_record({
      "project": project,
      "sceneId": input._get("sceneId"),
      "store": input._get("store"),
      "onChange": change,
      "notify": notify,
      "onNew": create,
    })
  })
  keyed_element(cached_scene_tabs_content, { "view": props }, [])
}

///|
let cached_scene_tabs_content : @core.Any = memo_component(scene_tabs_content)

///|
fn scene_tabs_content(input : @core.Any) -> @react.Element {
  let input = input._get("view")
  let project = input._get("project")
  let selected : String = input._get("sceneId").cast()
  let store = input._get("store")
  let on_change : (String) -> Unit = input._get("onChange").cast()
  let notify : (String) -> Unit = input._get("notify").cast()
  let (draft, set_draft) = @react.use_state((None : SceneNameDraft?))
  let (error, set_error) = @react.use_state("")
  let order : FixedArray[String] = project._get("sceneOrder").cast()
  let operate = fn(id : String, action : SceneAction) {
    stop_capturing(store)
    attempt(
      fn() {
        let doc = store._get("doc")
        let runtime = shared_runtime()
        match action {
          Earlier | Later => {
            @boundary.move_scene(
              doc,
              id,
              if action is Earlier {
                -1
              } else {
                1
              },
              runtime,
            )
            notify(
              "Scene の順番を変更しました。Undo で戻せます。",
            )
          }
          Duplicate => {
            on_change(@boundary.duplicate_scene(doc, id, runtime))
            notify(
              "Scene を複製しました。個別に編集できます。",
            )
          }
          Delete => {
            let result = @boundary.delete_scene(doc, id, runtime)
            if selected == id {
              on_change(result._get("selectedId").cast())
            }
            notify(
              "Scene を削除しました。元に戻すで復元できます。",
            )
          }
        }
      },
      notify,
      "Scene を変更できませんでした。",
    )
    stop_capturing(store)
  }
  let save_name = fn() {
    if draft is Some(value) {
      stop_capturing(store)
      attempt(
        fn() {
          @boundary.rename_scene(
            store._get("doc"),
            value.id,
            value.name,
            shared_runtime(),
          )
          set_draft(None)
          set_error("")
        },
        set_error,
        "名前を変更できませんでした。",
      )
      stop_capturing(store)
    }
  }
  let tabs : Array[&@react.ReactNode] = []
  for index, id in order {
    let scene = project._get("scenes")._get(id)
    if @core.is_nullish(scene) {
      continue
    }
    let name : String = scene._get("name").cast()
    let items : Array[&@react.ReactNode] = [
      scene_menu_item("Rename", "Pencil", false, fn() {
        let current = store._call("project", [])._get("scenes")._get(id)
        let name = if @core.is_nullish(current) {
          name
        } else {
          current._get("name").cast()
        }
        set_error("")
        set_draft(Some({ id, name, }))
      }),
      scene_menu_item("Duplicate", "Copy", order.length() >= 100, fn() {
        operate(id, Duplicate)
      }),
      scene_menu_item("Move earlier", "ArrowLeft", index == 0, fn() {
        operate(id, Earlier)
      }),
      scene_menu_item("Move later", "ArrowRight", index == order.length() - 1, fn() {
        operate(id, Later)
      }),
      scene_menu_item("Delete", "Trash2", order.length() <= 1, fn() {
        operate(id, Delete)
      }),
      h(
        "p",
        { "className": @core.any("px-2 py-1 text-xs text-[var(--muted)]") },
        [
          if order.length() <= 1 {
            "最後の Scene は残します。"
          } else {
            "削除した Scene は元に戻すで復元できます。"
          },
        ],
      ),
    ]
    tabs.push(
      h(
        "div",
        {
          "key": @core.any(id),
          "className": @core.any("scene-tab-item"),
          "data-scene-id": @core.any(id),
          "data-selected": if selected == id {
            @core.any(true)
          } else {
            @core.undefined()
          },
        },
        [
          ui(
            "Tabs",
            "Tab",
            {
              "className": @core.any("scene-tab"),
              "value": @core.any(id),
              "title": @core.any(name),
            },
            [
              icon("ChartNoAxesColumnIncreasing", 13),
              h("span", { "className": @core.any("scene-tab-name") }, [name]),
            ],
          ),
          ui("Menu", "Root", Map([]), [
            ui(
              "Menu",
              "Trigger",
              {
                "className": @core.any("scene-tab-menu"),
                "aria-label": @core.any(name + " のシーン操作"),
              },
              [icon("MoreHorizontal", 14)],
            ),
            ui("Menu", "Portal", Map([]), [
              ui(
                "Menu",
                "Positioner",
                {
                  "side": @core.any("bottom"),
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
                    items,
                  ),
                ],
              ),
            ]),
          ]),
        ],
      ),
    )
  }
  let form : Array[&@react.ReactNode] = [
    h("label", Map([]), [
      "Scene name",
      h(
        "input",
        {
          "autoFocus": @core.any(true),
          "aria-label": @core.any("Scene name"),
          "maxLength": @core.any(200),
          "value": @core.any(draft.map(fn(value) { value.name }).unwrap_or("")),
          "onChange": @core.any(fn(event : @core.Any) {
            if draft is Some(value) {
              set_draft(
                Some({
                  ..value,
                  name: event._get("target")._get("value").cast(),
                }),
              )
            }
          }),
        },
        [],
      ),
    ]),
  ]
  if !error.is_empty() {
    form.push(h("p", { "role": @core.any("alert") }, [error]))
  }
  form.push(
    h("div", Map([]), [
      h(
        "button",
        {
          "type": @core.any("button"),
          "className": @core.any("subtle-button"),
          "onClick": @core.any(fn() { set_draft(None) }),
        },
        ["Cancel"],
      ),
      h(
        "button",
        {
          "type": @core.any("submit"),
          "className": @core.any("primary-button"),
          "disabled": @core.any(
            draft
            .map(fn(value) { @editor.trim_text(value.name).is_empty() })
            .unwrap_or(true),
          ),
        },
        ["Save name"],
      ),
    ]),
  )
  @react.fragment([
    h("div", { "className": @core.any("scene-management") }, [
      ui(
        "Tabs",
        "Root",
        {
          "value": @core.any(selected),
          "className": @core.any("scene-tabs"),
          "onValueChange": @core.any(fn(value : @core.Any) {
            on_change(string_value(value))
          }),
        },
        [
          ui(
            "Tabs",
            "List",
            {
              "className": @core.any("scene-tab-list"),
              "aria-label": @core.any("Scenes"),
            },
            tabs,
          ),
        ],
      ),
      component(
        icon_button,
        {
          "label": @core.any("Scene を追加"),
          "onClick": input._get("onNew"),
          "disabled": @core.any(order.length() >= 100),
        },
        [icon("Plus", 14)],
      ),
    ]),
    component(
      modal,
      {
        "open": @core.any(draft is Some(_)),
        "title": @core.any("Rename scene"),
        "description": @core.any("Scene の名前を変更します。"),
        "onOpenChange": @core.any(fn(open : Bool) {
          if !open {
            set_draft(None)
            set_error("")
          }
        }),
      },
      [
        h(
          "form",
          {
            "className": @core.any("scene-rename-form"),
            "onSubmit": @core.any(fn(event : @core.Any) {
              prevent_default(event)
              save_name()
            }),
          },
          form,
        ),
      ],
    ),
  ])
}

///|
pub fn playback_panel(input : @core.Any) -> @react.Element {
  let scene = input._get("scene")
  let segment = input._get("segment")
  let compositions = scene._get("compositions")
  let title = if @core.is_nullish(segment) {
    scene._get("name")
  } else if string_value(segment._get("kind")) == "transition" {
    let transition = scene._get("transitions")._get(segment._get("id").cast())
    if @core.is_nullish(transition) {
      @core.undefined()
    } else {
      let from : String = compositions
        ._get(transition._get("fromId").cast())
        ._get("name")
        .cast()
      let to : String = compositions
        ._get(transition._get("toId").cast())
        ._get("name")
        .cast()
      @core.any(from + " → " + to)
    }
  } else {
    let composition = compositions._get(segment._get("id").cast())
    if @core.is_nullish(composition) {
      @core.undefined()
    } else {
      composition._get("name")
    }
  }
  h("div", { "className": @core.any("inspector-content playback-panel") }, [
    h("div", { "className": @core.any("inspector-title") }, [
      h("span", Map([]), ["Scene preview"]),
      h("span", { "className": @core.any("inspector-kind") }, [
        @boundary.format_milliseconds(input._get("playhead").cast()) + " ms",
      ]),
    ]),
    h("div", { "className": @core.any("property-section") }, [
      icon("Clapperboard", 25, props={ "strokeWidth": @core.any(1.4) }),
      h("h3", Map([]), [HostNode::{ value: title, }]),
      h("p", Map([]), [
        "再生位置の場面を開いて、配置や動きを編集できます。",
      ]),
      h(
        "button",
        {
          "className": @core.any("subtle-button full-width"),
          "onClick": input._get("onEdit"),
        },
        [icon("PencilLine", 14), "この場面を編集"],
      ),
      h("span", { "className": @core.any("muted small") }, [
        "Esc で編集に戻る",
      ]),
    ]),
  ])
}
