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

val async  : ('a -> 'b) -> 'a -> 'b promise

val await  : 'a promise -> 'a 
(** Raises exception [e] if the promise raises [e]. *)

val yield  : unit -> unit

val accept : file_descr -> file_descr * sockaddr

val recv   : file_descr -> bytes -> int -> int -> msg_flag list -> int

val send   : file_descr -> bytes -> int -> int -> msg_flag list -> int

val sleep  : float -> unit

val run : (unit -> unit) -> unit

type mutex

val create_mutex : unit -> mutex

val lock   : mutex -> unit

val unlock : mutex -> unit

val with_lock : mutex -> (unit -> 'a) -> 'a

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
