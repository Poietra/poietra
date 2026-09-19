///|
async fn call(
  owner : @core.Any,
  name : String,
  arguments : FixedArray[@core.Any],
) -> @core.Any {
  let value = @core.throwable(fn() { owner._call(name, arguments) })
  @core.Promise::resolve(value).wait()
}

///|
async fn load_kernel(runtime : @core.Any) -> @core.Any {
  let loaded_module = call(runtime, "loadKernelModule", [])
  call(loaded_module, "loadKernel", [])
}

///|
async fn open_page(
  container : @core.Any,
  root : @client.ReactDOMRoot?,
  runtime : @core.Any,
) -> Unit {
  try {
    match root {
      Some(root) => {
        // Begin the kernel before the editor graph has loaded. Await both
        // promises together so failure of either consumes both completions.
        let editor = @core.from_async(async fn() {
          call(runtime, "loadEditor", [])
        })
        let kernel = @core.from_async(async fn() { load_kernel(runtime) })
        let loaded = @core.Promise::all([editor, kernel]).wait()
        let values = loaded
        call(values[0], "openEditor", [root.as_any(), values[1]]) |> ignore
      }
      None => {
        let loaded_module = call(runtime, "loadHome", [])
        call(loaded_module, "openHome", [container]) |> ignore
      }
    }
  } catch {
    _ => {
      let locale = if root is Some(_) {
        @site.Japanese
      } else {
        @site.locale(get_locale()).unwrap_or(English)
      }
      let root = match root {
        Some(root) => root
        None => @client.create_root(container.cast())
      }
      root.render(failure_view(locale))
    }
  }
}

///|
pub fn start_page(runtime : @core.Any) -> Unit {
  let global = @core.global_this()
  let document = global._get("document")
  let container = document._call("getElementById", [@core.any("root")])
  let url = @core.new(global._get("URL"), [global._get("location")._get("href")])
  let editor = is_editor_location(url)
  document
  ._get("body")
  ._get("dataset")
  ._set("page", @core.any(if editor { "editor" } else { "home" }))
  // Prerendered home content stays visible until hydration is ready.
  let root = if editor {
    let root = @client.create_root(container.cast())
    apply_page_language("ja")
    root.render(
      h(
        "div",
        { "className": @core.any("entry-message"), "role": @core.any("status") },
        [
          h(
            "img",
            { "src": @core.any("/poietra.svg"), "alt": @core.any("Poietra") },
            [],
          ),
          h("span", {}, ["Opening your studio"]),
        ],
      ),
    )
    Some(root)
  } else {
    None
  }
  @core.from_async(async fn() { open_page(container, root, runtime) }) |> ignore
}

///|
pub fn open_editor(
  root : @core.Any,
  kernel : @core.Any,
  runtime : @core.Any,
) -> Unit {
  let store = @core.new(runtime._get("EditorStore"), [
    runtime._call("currentRoom", []),
  ])
  let props = {
    "store": store,
    "kernel": kernel,
    "renderer": runtime._get("renderer"),
    "exporter": runtime._get("exporter"),
    "createFramePainter": runtime._get("createFramePainter"),
  }
  (root.cast() : @client.ReactDOMRoot).render(
    protect(@react.jsx(runtime._get("App"), [], props~)),
  )
}
