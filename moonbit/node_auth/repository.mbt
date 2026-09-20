///|
priv struct Repository {
  records : String
  accounts : String
}

///|
#module("node:path")
extern "js" fn path(left : String, right : String) -> String = "resolve"

///|
#module("node:fs")
extern "js" fn mkdir_private(path : String, options : @core.Any) -> Unit = "mkdirSync"

///|
#module("node:fs")
extern "js" fn write_file(
  path : String,
  data : String,
  options : @core.Any,
) -> Unit = "writeFileSync"

///|
fn fail(message : String) -> Unit raise {
  @core.throwable(fn() { @core.throw_error(message) })
}

///|
fn Repository::record_path(self : Repository, key : String) -> String raise {
  let parts = key.split(":").to_array()
  if parts.length() != 2 ||
    (parts[0] != "session" && parts[0] != "flow") ||
    !@policy.valid_token(parts[1].to_owned()) {
    fail("Invalid auth key")
  }
  path(self.records, parts[0].to_owned() + "-" + parts[1].to_owned() + ".json")
}

///|
fn Repository::account_path(self : Repository, id : String) -> String raise {
  if !@policy.valid_token(id) {
    fail("Invalid account")
  }
  path(self.accounts, id + ".json")
}

///|
fn read(path : String) -> @core.Any raise {
  if !@fs.existsSync(path) {
    return @core.null()
  }
  let text = @fs.read_file_sync_string(path, "utf8")
  @core.throwable(fn() {
    @core.global_this()._get("JSON")._call("parse", [@core.any(text)])
  })
}

///|
fn write(path : String, value : @core.Any) -> Unit raise {
  let temporary = path + ".tmp"
  let text : String = @core.global_this()
    ._get("JSON")
    ._call("stringify", [value])
    .cast()
  @core.throwable(fn() {
    write_file(temporary, text, @core.from_entries([("mode", @core.any(384))]))
  })
  @fs.renameSync(temporary, path)
}

///|
fn remove(path : String) -> Unit raise {
  if @fs.existsSync(path) {
    @fs.unlinkSync(path)
  }
}

///|
fn active(path : String, now : Double) -> @policy.Record? raise {
  let record = @auth.read_record(read(path))
  if record is Some(record) && record.expires() <= now {
    remove(path)
    return None
  }
  record
}

///|
fn entries(path : String) -> Array[@policy.LibraryEntry] raise {
  let value = read(path)
  if @core.is_nullish(value) {
    return []
  }
  let values : FixedArray[@core.Any] = value.cast()
  Array::makei(values.length(), fn(i) { @auth.read_library_entry(values[i]) })
}

///|
fn entry_values(entries : Array[@policy.LibraryEntry]) -> @core.Any {
  @core.any(
    FixedArray::makei(entries.length(), fn(i) {
      @auth.library_entry_value(entries[i])
    }),
  )
}

///|
extern "js" fn locale_compare(left : String, right : String) -> Int =
  #|(left, right) => left.localeCompare(right)

///|
fn Repository::cleanup(self : Repository, time : Double) -> Unit raise {
  for filename in @fs.readdirSync(self.records) {
    if !filename.has_suffix(".json") {
      continue
    }
    let location = path(self.records, filename)
    let keep = try {
      match @auth.read_record(read(location)) {
        Some(record) => record.expires() > time
        None => false
      }
    } catch {
      _ => false
    }
    if !keep {
      remove(location)
    }
  }
}

///|
fn clock() -> Double {
  @core.global_this()._get("Date")._call("now", []).cast()
}

///|
fn create_repository(directory : String) -> @core.Any raise {
  let repository : Repository = {
    records: path(directory, "records"),
    accounts: path(directory, "users"),
  }
  for directory in [repository.records, repository.accounts] {
    @core.throwable(fn() {
      mkdir_private(
        directory,
        @core.from_entries([
          ("recursive", @core.any(true)),
          ("mode", @core.any(448)),
        ]),
      )
    })
  }
  @core.from_entries([
    (
      "putRecord",
      @core.any(fn(key, value) {
        @core.from_async(fn() raise {
          write(repository.record_path(key), value)
        })
        |> @http.native_errors
      }),
    ),
    (
      "getSession",
      @core.any(fn(key, now) {
        @core.from_async(fn() raise {
          match active(repository.record_path(key), now) {
            Some(Session(session)) => @auth.record_value(Session(session))
            _ => @core.null()
          }
        })
        |> @http.native_errors
      }),
    ),
    (
      "takeFlow",
      @core.any(fn(key, provider : String, browser_hash, origin, now) {
        @core.from_async(fn() raise {
          let path = repository.record_path(key)
          guard active(path, now) is Some(Flow(flow)) &&
            flow.provider.name() == provider &&
            flow.browser_hash == browser_hash &&
            flow.origin == origin else {
            return @core.null()
          }
          // No await between comparison and deletion in this local process.
          remove(path)
          @auth.record_value(Flow(flow))
        })
        |> @http.native_errors
      }),
    ),
    (
      "deleteRecord",
      @core.any(fn(key) {
        @core.from_async(fn() raise { remove(repository.record_path(key)) })
        |> @http.native_errors
      }),
    ),
    (
      "listProjects",
      @core.any(fn(user) {
        @core.from_async(fn() raise {
          let values : Array[@policy.Project] = []
          for entry in entries(repository.account_path(user)) {
            if entry is Listed(project) {
              values.push(project)
            }
          }
          values.sort_by(fn(a, b) {
            if a.updated > b.updated {
              -1
            } else if a.updated < b.updated {
              1
            } else {
              locale_compare(a.room, b.room)
            }
          })
          @core.any(
            FixedArray::makei(values.length(), fn(i) {
              @auth.project_value(values[i])
            }),
          )
        })
        |> @http.native_errors
      }),
    ),
    (
      "putProject",
      @core.any(fn(user, value, intent : @core.Any) {
        @core.from_async(fn() raise {
          let path = repository.account_path(user)
          let values = entries(path)
          let project = @auth.read_project(value)
          let index = values.search_by(fn(item) { item.room() == project.room })
          let listed = match index {
            Some(index) =>
              match values[index] {
                Listed(_) => true
                Dismissed(_) => {
                  if @core.equal(intent, @core.any("visit")) {
                    return false
                  }
                  false
                }
              }
            None => false
          }
          if !listed &&
            values.filter(fn(item) { item is Listed(_) }).length() >=
            @policy.project_limit {
            return false
          }
          match index {
            Some(index) => values[index] = @policy.Listed(project)
            None => values.push(@policy.Listed(project))
          }
          write(path, entry_values(values))
          true
        })
        |> @http.native_errors
      }),
    ),
    (
      "deleteProject",
      @core.any(fn(user, room) {
        @core.from_async(fn() raise {
          let path = repository.account_path(user)
          let values = entries(path)
          match values.search_by(fn(item) { item.room() == room }) {
            Some(index) => values[index] = @policy.Dismissed(room)
            None => values.push(@policy.Dismissed(room))
          }
          write(path, entry_values(values))
        })
        |> @http.native_errors
      }),
    ),
    (
      "cleanup",
      @core.any(fn(time : @core.Any) {
        repository.cleanup(
          if @core.is_nullish(time) {
            clock()
          } else {
            time.cast()
          },
        ) catch {
          error => @core.throw_(@http.native_error(error))
        }
      }),
    ),
  ])
}

///|
extern "js" fn class_adapter(create : (String) -> @core.Any) -> @core.Any =
  #|create => function NodeAuthRepository(directory) { return create(directory); }

///|
pub fn repository_class() -> @core.Any {
  class_adapter(fn(directory) {
    create_repository(directory) catch {
      error => {
        @core.throw_(@http.native_error(error))
        @core.undefined()
      }
    }
  })
}
