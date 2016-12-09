(*---------------------------------------------------------------------------
   Copyright (c) 2016 KC Sivaramakrishnan. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   %%NAME%% %%VERSION%%
  ---------------------------------------------------------------------------*)

(** Asynchronous effect-based IO

    {e %%VERSION%% — {{:%%PKG_HOMEPAGE%% }homepage}} *)

(** {1 Aeio} *)

type file_descr = Unix.file_descr
type sockaddr = Unix.sockaddr
type msg_flag = Unix.msg_flag

type 'a promise
(** The type of promise. *)

type context 
(** The type of cancellation context. *)

exception Cancelled
(** Raised in the cancelled fiber. Allows the fiber to dispose resources
    cleanly. *)

exception Promise_cancelled
(** Raised at {!await} if the promise was cancelled. *)

val new_context : unit -> context 
(** Creates a new cancellation context. *)

val my_context : unit -> context
(** Return the current cancellation context. *)

val cancel : context -> unit
(** Cancel the context. *)

val async : ?ctxt:context-> ('a -> 'b) -> 'a -> 'b promise
(** [async f v] spawns a fiber to run [f v] asynchronously. If no cancellation
    context was provided, then the new fiber shares the cancelallation context
    of the caller. *)

val await : 'a promise -> 'a 
(** Block until the result of a promise is available. Raises exception [e] if
    the promise raises [e]. 
    @raise Promise_cancelled if the promise was cancelled. *)

val yield : unit -> unit
(** Yield control. *)

val accept : file_descr -> file_descr * sockaddr
(** Similar to Unix.accept, but asynchronous. *)

val recv : file_descr -> bytes -> int -> int -> msg_flag list -> int
(** Similar to Unix.recv, but asynchronous. *)

val send : file_descr -> bytes -> int -> int -> msg_flag list -> int
(** Similar to Unix.send, but asynchronous. *)

val sleep : float -> unit
(** [sleep t] suspends the fiber for [t] milliseconds. *)

val run : (unit -> unit) -> unit
(** Run the asynchronous program. *)

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
