///|
priv struct Packet {
  data : @core.Any
  size : Double
}

///|
priv enum SendState {
  Idle
  Sending(Double)
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
  guard self.state is Idle && self.pending.length() > 0 else { return }
  let connection : @websocket.WebSocket = self.socket.cast()
  if connection.readyState != 1 {
    self.stop()
    return
  }
  let packet = self.pending[0].unwrap()
  self.pending[0] = None
  self.pending.pop_front() |> ignore
  self.queued_bytes -= packet.size
  self.state = Sending(packet.size)
  // ws owns the bytes until its public send callback fires. Queue references,
  // never copies; do not enqueue the next packet into its native write buffer.
  (@core.throwable(fn() {
    self.socket._call("send", [
      packet.data,
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
  })
  |> ignore) catch {
    _ => self.close(1011, "Send failed; resynchronize")
  }
}

///|
fn Outbox::send(self : Outbox, data : @core.Any) -> Unit {
  if self.state is Closed {
    return
  }
  let connection : @websocket.WebSocket = self.socket.cast()
  if connection.readyState != 1 {
    self.stop()
    return
  }
  let size : Double = data._get("byteLength").cast()
  let active = match self.state {
    Sending(size) => size
    Idle | Closed => 0.0
  }
  let mut largest = Double::max(active, size)
  for packet in self.pending {
    if packet is Some(packet) {
      largest = Double::max(largest, packet.size)
    }
  }
  // One indivisible sync packet may exceed 1 MiB. Bound all additional work
  // by 1 MiB and 128 packets, including the active native write. This also
  // permits a large packet queued behind the initial small sync request.
  let outstanding = Double::max(active, connection.bufferedAmount.to_double()) +
    self.queued_bytes +
    size
  if self.pending.length() >= 128 || outstanding > 1048576.0 + largest {
    self.close(1013, "Slow connection; resynchronize")
    return
  }
  self.pending.push_back(Some({ data, size, }))
  self.queued_bytes += size
  self.drain()
}
