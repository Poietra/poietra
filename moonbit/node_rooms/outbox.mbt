///|
priv enum Payload {
  Bytes(@core.Any)
  SyncReply(() -> @core.Any?)
}

///|
priv struct Packet {
  payload : Payload
  size : Double
}

///|
priv enum SendState {
  Idle
  Sending
  Closed
}

///|
priv struct Outbox {
  socket : @core.Any
  pending : @deque.Deque[Packet?]
  mut queued_bytes : Double
  mut state : SendState
}

///|
fn Outbox::new(socket : @core.Any) -> Outbox {
  { socket, pending: @deque.Deque([]), queued_bytes: 0.0, state: Idle, }
}

///|
fn Outbox::stop(self : Outbox) -> Unit {
  self.state = Closed
  self.pending.clear()
  // Deque retains removed slots for views; explicitly release payload references.
  self.pending.release_unused(placeholder=None)
  self.queued_bytes = 0.0
}

///|
fn Outbox::close(self : Outbox, code : Int, reason : String) -> Unit {
  self.stop()
  (@core.throwable(fn() {
    self.socket._call("close", [@core.any(code), @core.any(reason)])
  })
  |> ignore) catch {
    _ => ()
  }
}

///|
fn Outbox::drain(self : Outbox) -> Unit {
  match self.state {
    Idle => ()
    Sending | Closed => return
  }
  guard self.pending.length() > 0 else { return }
  let connection : @websocket.WebSocket = self.socket.cast()
  if connection.readyState != 1 {
    self.stop()
    return
  }
  let packet = self.pending[0].unwrap()
  self.pending[0] = None
  self.pending.pop_front() |> ignore
  self.queued_bytes -= packet.size
  // ws owns the bytes until its public send callback fires. Queue references,
  // never copies; do not enqueue the next packet into its native write buffer.
  (@core.throwable(fn() {
    let data = match packet.payload {
      Bytes(data) => Some(data)
      SyncReply(build) => build()
    }
    guard data is Some(data) && !(self.state is Closed) else { return }
    self.state = Sending
    self.socket._call("send", [
      data,
      @core.any(fn(error : @core.Any) {
        if self.state is Closed {
          return
        }
        if !@core.is_nullish(error) {
          self.close(1011, "Send failed; resynchronize")
        } else {
          self.state = Idle
          self.drain()
        }
      }),
    ])
    |> ignore
  })
  |> ignore) catch {
    _ => self.close(1011, "Send failed; resynchronize")
  }
}

///|
fn Outbox::send(self : Outbox, data : @core.Any) -> Unit {
  self.enqueue({ payload: Bytes(data), size: data._get("byteLength").cast(), })
}

///|
fn Outbox::enqueue(self : Outbox, packet : Packet) -> Unit {
  if self.state is Closed {
    return
  }
  let connection : @websocket.WebSocket = self.socket.cast()
  if connection.readyState != 1 {
    self.stop()
    return
  }
  let mut largest = packet.size
  for queued in self.pending {
    if queued is Some(queued) {
      largest = Double::max(largest, queued.size)
    }
  }
  // The native writer owns one active packet. Independently bound the waiting
  // queue by 128 entries and 1 MiB beyond one indivisible packet. Server-side
  // migration can produce a larger packet while an accepted import is in flight.
  // Deferred replies retain only their input vector until preceding writes finish.
  if self.pending.length() >= 128 ||
    self.queued_bytes + packet.size > 1048576.0 + largest {
    self.close(1013, "Slow connection; resynchronize")
    return
  }
  self.pending.push_back(Some(packet))
  self.queued_bytes += packet.size
  self.drain()
}
