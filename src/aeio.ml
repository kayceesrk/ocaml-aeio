(*---------------------------------------------------------------------------
   Copyright (c) 2016 KC Sivaramakrishnan. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   %%NAME%% %%VERSION%%
  ---------------------------------------------------------------------------*)

(* Asynchronous IO scheduler.
 *
 * For each blocking action, if the action can be performed immediately, then it
 * is. Otherwise, the thread performing the blocking task is suspended and
 * automatically wakes up when the action completes. The suspend/resume is
 * transparent to the programmer.
 *)

(* Type declarations *)

type file_descr = Unix.file_descr
type sockaddr = Unix.sockaddr
type msg_flag = Unix.msg_flag

exception Cancelled
exception Promise_cancelled

type thread_id = int

type cleanup = (unit -> unit) ref

type cont = Cont : ('a, unit) continuation -> cont

type _context = 
  | Default   : (cont * local_state) Lwt_sequence.t -> _context
  | Cancelled : _context

and context = _context ref

and local_state = 
  { mutable context   : context;
            cleanup   : cleanup;
            thread_id : thread_id }

type 'a _promise =
  | Done    of 'a
  | Error   of exn
  | Waiting of ((cont * local_state) Lwt_sequence.node * ('a, unit) continuation) list

type 'a promise = 'a _promise ref


effect Async : ('a -> 'b) * 'a * context option -> 'b promise
effect Await : 'a promise -> 'a
effect Yield : unit

effect Accept : file_descr -> (file_descr * sockaddr)
effect Recv   : file_descr * bytes * int * int * msg_flag list -> int
effect Send   : file_descr * bytes * int * int * msg_flag list -> int
effect Read   : file_descr * bytes * int * int -> int
effect Write  : file_descr * bytes * int * int -> int
effect Sleep  : float -> unit

effect Get_context    : context
effect Cancel_context : context -> unit

type global_state =
  { run_q    : (unit -> unit) Queue.t;
    read_ht  : (file_descr, Lwt_engine.event * (unit -> unit) Lwt_sequence.t) Hashtbl.t;
    write_ht : (file_descr, Lwt_engine.event * (unit -> unit) Lwt_sequence.t) Hashtbl.t; }

(* Wrappers for performing effects *)

let async ?ctxt f v =
  perform (Async (f, v, ctxt))

let await p =
  perform (Await p)

let yield () =
  perform Yield

let accept fd =
  perform (Accept fd)

let recv fd buf pos len mode =
  perform (Recv (fd, buf, pos, len, mode))

let send fd buf pos len mode =
  perform (Send (fd, buf, pos, len, mode))

let read fd buf pos len =
  perform (Read (fd, buf, pos, len))

let write fd buf pos len =
  perform (Write (fd, buf, pos, len))

let sleep timeout =
  perform (Sleep timeout)

(* Stubs *)

external stub_read  : Unix.file_descr -> Bytes.t -> int -> int -> int = "lwt_unix_read"
external stub_write : Unix.file_descr -> Bytes.t -> int -> int -> int = "lwt_unix_write"

(* Cancellation *)

let new_context () = ref (Default (Lwt_sequence.create ()))

let my_context () = perform Get_context

let cancel ctxt = perform (Cancel_context ctxt)

let handle_cancel lst gst k ctxt =
  let cancel_fiber lst k =
    lst.context <- new_context (); 
    !(lst.cleanup) ();
    discontinue k Cancelled
  in
  match !ctxt with
  | Default l ->
      ctxt := Cancelled;
      Lwt_sequence.iter_l (fun (Cont k, lst) -> Queue.push (fun () -> 
        cancel_fiber lst k) gst.run_q) l;
      if ctxt = lst.context then begin
        cancel_fiber lst k 
      end else continue k ()
  | Cancelled -> ()

let live ctxt = 
  match !ctxt with
  | Default _ -> true
  | Cancelled -> false 

let watch_for_cancellation lst k =
  match !(lst.context) with
  | Default s -> Lwt_sequence.add_r (Cont k, lst) s
  | Cancelled -> failwith "Impossible happened"

(* IO loop *)

let clean gst =
  let clean_ht ht = 
    let fd_list = 
      (* XXX: Use Hashtbl.filter_map_inplace *)
      Hashtbl.fold (fun fd (ev,seq) acc -> 
        if Lwt_sequence.is_empty seq then
          (Lwt_engine.stop_event ev; fd::acc)
        else acc) ht []
    in
    List.iter (fun fd -> Hashtbl.remove ht fd) fd_list
  in
  clean_ht gst.read_ht;
  clean_ht gst.write_ht

let rec schedule gst =
  if Queue.is_empty gst.run_q then (* No runnable threads *)
    if Hashtbl.length gst.read_ht = 0 &&
       Hashtbl.length gst.write_ht = 0 &&
       Lwt_engine.timer_count () = 0 then () (* We are done *)
    else perform_io gst
  else (* Still have runnable threads *)
    Queue.pop gst.run_q ()

and perform_io gst =
  Lwt_engine.iter true;
  (* TODO: Cleanup should be performed laziyly for performance. *)
  clean gst;
  schedule gst

(* Syscall wrappers *)

type syscall_kind = 
  | Syscall_read 
  | Syscall_write

external poll_rd : Unix.file_descr -> bool = "lwt_unix_readable"
external poll_wr : Unix.file_descr -> bool = "lwt_unix_writable"

let register_readable fd seq = 
    Lwt_engine.on_readable fd (fun _ -> Lwt_sequence.iter_l (fun f -> f ()) seq)

let register_writable fd seq = 
    Lwt_engine.on_writable fd (fun _ -> Lwt_sequence.iter_l (fun f -> f ()) seq)

let poll_syscall fd kind action =
  try
    if (kind = Syscall_read && poll_rd fd) || (kind = Syscall_write && poll_wr fd) then
      Some (action ())
    else None
  with
  | Unix.Unix_error((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _)
  | Sys_blocked_io -> None

let dummy = Lwt_sequence.add_r ignore (Lwt_sequence.create ())
let dummy_cleanup () = ()

let maybe_continue ctxt_node k v =
  Lwt_sequence.remove ctxt_node;
  try continue k v with
  | Invalid_argument _ -> ()

let maybe_discontinue ctxt_node k v =
  Lwt_sequence.remove ctxt_node;
  try discontinue k v with
  | Invalid_argument _ -> ()

let rec block_syscall cleanup ctxt_node gst fd kind action k =
  let node = ref dummy in
  let ht,register = 
    match kind with
    | Syscall_read -> gst.read_ht, register_readable
    | Syscall_write -> gst.write_ht, register_writable
  in
  let seq = 
    try snd @@ Hashtbl.find ht fd
    with Not_found ->
      let seq = Lwt_sequence.create () in
      let ev = register fd seq in
      Hashtbl.add ht fd (ev, seq);
      seq
  in
  node := Lwt_sequence.add_r (fun () ->
    Lwt_sequence.remove !node;
    match poll_syscall fd kind action with
    | Some res -> 
        cleanup := dummy_cleanup;
        Queue.push (fun () -> maybe_continue ctxt_node k res) gst.run_q
    | None -> block_syscall cleanup ctxt_node gst fd kind action k) seq;
  (* This needs to be run if the thread was cancelled. *)
  cleanup := (fun () -> Lwt_sequence.remove !node)

let do_syscall cleanup ctxt_node gst fd kind action k =
  match poll_syscall fd kind action with
  | Some res -> maybe_continue ctxt_node k res
  | None -> 
      block_syscall cleanup ctxt_node gst fd kind action k;
      schedule gst

let block_sleep ctxt_node gst delay k =
  ignore @@ Lwt_engine.on_timer delay false (fun ev -> 
    Lwt_engine.stop_event ev; 
    Queue.push (maybe_continue ctxt_node k) gst.run_q)

(* Promises *)

let mk_promise () = ref (Waiting [])

let finish gst prom v =
  match !prom with
  | Waiting l ->
      prom := Done v;
      List.iter (fun (ctxt_node, k) ->
        Queue.push (fun () -> maybe_continue ctxt_node k v) gst.run_q) l
  | _ -> failwith "Impossible: finish"

let abort gst prom e =
  match !prom with
  | Waiting l ->
      prom := Error e;
      List.iter (fun (ctxt_node, k) ->
        Queue.push (fun () -> maybe_discontinue ctxt_node k e) gst.run_q) l
  | _ -> failwith "Impossible: abort"

let force lst gst prom k =
  match !prom with
  | Done v -> continue k v
  | Error e -> discontinue k e
  | Waiting l -> 
      let ctxt_node = watch_for_cancellation lst k in
      prom := Waiting ((ctxt_node,k)::l); 
      schedule gst

module IVar = struct

  type 'a t = 'a _promise ref

  let create () = mk_promise ()

  effect Fill : 'a t * 'a -> unit
  let fill iv v = perform (Fill (iv,v))

  effect Read : 'a t -> 'a
  let read iv = perform (Read iv)
end

module Bigstring = struct
  type t = (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

  effect Read : file_descr * t * int * int -> int
  effect Write : file_descr * t * int * int -> int 

  let read fd buf pos len = perform (Read (fd, buf, pos, len))
  let read_all fd buf = read fd buf 0 (Lwt_bytes.length buf)

  let write fd buf pos len = perform (Write (fd, buf, pos, len))
  let write_all fd buf = write fd buf 0 (Lwt_bytes.length buf)

  external stub_read : Unix.file_descr -> t -> int -> int -> int = "lwt_unix_bytes_read"
  external stub_write : Unix.file_descr -> t -> int -> int -> int = "lwt_unix_bytes_write"
end

(* Main handler loop *)

let tid_counter = ref 0

let init () =
  { run_q = Queue.create ();
    read_ht = Hashtbl.create 13;
    write_ht = Hashtbl.create 13 }

let next_tid () = 
  let res = !tid_counter in
  incr tid_counter;
  res

let run main =
  let gst = init () in
  let rec fork : 'a. local_state -> global_state -> 'a promise -> (unit -> 'a) -> unit = 
    fun lst gst prom f ->
      match f () with
      | v -> finish gst prom v; schedule gst
      | exception Cancelled ->
          abort gst prom Promise_cancelled;
          schedule gst
      | exception e ->
          abort gst prom e;
          schedule gst
      | effect Yield k when live lst.context ->
          let ctxt_node = watch_for_cancellation lst k in
          Queue.push (maybe_continue ctxt_node k) gst.run_q;
          schedule gst
      | effect (Async (f, v, c)) k when live lst.context ->
          let ctxt_node = watch_for_cancellation lst k in
          let ctxt = 
            match c with 
            | None -> lst.context 
            | Some ctxt -> ctxt
          in
          let prom = mk_promise () in
          Queue.push (fun () -> maybe_continue ctxt_node k prom) gst.run_q;
          let lst = 
            {cleanup = ref dummy_cleanup; 
             context = ctxt; 
             thread_id = next_tid ()} 
          in 
          fork lst gst prom (fun () -> f v)
      | effect (Await prom) k when live lst.context -> 
          (* TODO KC: Cancellation *)
          force lst gst prom k
      | effect (IVar.Read iv) k when live lst.context -> 
          (* TODO KC: Cancellation *)
          force lst gst iv k
      | effect (IVar.Fill (iv,v)) k when live lst.context ->
          finish gst iv v;
          continue k ()
      | effect (Accept fd) k when live lst.context ->
          let ctxt_node = watch_for_cancellation lst k in
          let action () = Unix.accept fd in
          do_syscall lst.cleanup ctxt_node gst fd Syscall_read action k
      | effect (Recv (fd, buf, pos, len, mode)) k when live lst.context ->
          let ctxt_node = watch_for_cancellation lst k in
          let action () = Unix.recv fd buf pos len mode in
          do_syscall lst.cleanup ctxt_node gst fd Syscall_read action k
      | effect (Send (fd, buf, pos, len, mode)) k when live lst.context ->
          let ctxt_node = watch_for_cancellation lst k in
          let action () = Unix.send fd buf pos len mode in
          do_syscall lst.cleanup ctxt_node gst fd Syscall_write action k
      | effect (Read (fd, buf, pos, len)) k when live lst.context ->
          let ctxt_node = watch_for_cancellation lst k in
          let action () = stub_read fd buf pos len in
          do_syscall lst.cleanup ctxt_node gst fd Syscall_read action k
      | effect (Write (fd, buf, pos, len)) k when live lst.context ->
          let ctxt_node = watch_for_cancellation lst k in
          let action () = stub_write fd buf pos len in
          do_syscall lst.cleanup ctxt_node gst fd Syscall_write action k
      | effect (Bigstring.Read (fd, buf, pos, len)) k when live lst.context ->
          let ctxt_node = watch_for_cancellation lst k in
          let action () = Bigstring.stub_read fd buf pos len in
          do_syscall lst.cleanup ctxt_node gst fd Syscall_read action k
      | effect (Bigstring.Write (fd, buf, pos, len)) k when live lst.context ->
          let ctxt_node = watch_for_cancellation lst k in
          let action () = Bigstring.stub_write fd buf pos len in
          do_syscall lst.cleanup ctxt_node gst fd Syscall_write action k
      | effect (Sleep t) k when live lst.context ->
          if t <= 0. then continue k ()
          else begin
            let ctxt_node = watch_for_cancellation lst k in
            block_sleep ctxt_node gst t k;
            schedule gst
          end
      | effect Get_context k when live lst.context ->
          continue k lst.context 
      | effect (Cancel_context ctxt) k when live lst.context ->
          handle_cancel lst gst k ctxt 
      | effect e k when not(live lst.context) ->
          discontinue k Cancelled
  in
  let prom = mk_promise () in
  let context = new_context () in
  let cleanup = ref dummy_cleanup in
  let lst = {context; cleanup; thread_id = next_tid ()} in
  fork lst gst prom main

(*---------------------------------------------------------------------------
   Copyright (c) 2016 KC Sivaramakrishnan

   Permission to use, copy, modify, and/or distribute this software for any
   purpose with or without fee is hereby granted, provided that the above
   copyright notice and this permission notice appear in all copies.

   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
  ---------------------------------------------------------------------------*)
