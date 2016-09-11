(*---------------------------------------------------------------------------
   Copyright (c) 2016 KC Sivaramakrishnan. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   %%NAME%% %%VERSION%%
  ---------------------------------------------------------------------------*)

(* A simple echo server.
 *
 * The server listens on localhost port 9301. It accepts multiple clients and
 * echoes back to the client any data sent to the server. This server is a
 * direct-style reimplementation of the echo server found at [1], which
 * illustrates the same server written in CPS style.
 *
 * Compiling
 * ---------
 *
 *   make
 *
 * Running
 * -------
 * The echo server can be tested with a telnet client by starting the server and
 * on the same machine, running:
 *
 *   telnet localhost 9301
 *
 * -----------------------
 * [1] http://www.mega-nerd.com/erikd/Blog/CodeHacking/Ocaml/ocaml_select.html
 * [2] https://github.com/ocamllabs/opam-repo-dev
 *)

open Printexc
open Printf

let send sock str =
  let len = String.length str in
  let total = ref 0 in
  (try
      while !total < len do
        let write_count = Aio.send sock str !total (len - !total) [] in
        total := write_count + !total
        done
    with _ -> ()
    );
  !total

let recv sock maxlen =
  let str = Bytes.create maxlen in
  let recvlen =
    try Aio.recv sock str 0 maxlen []
    with _ -> 0
  in
  String.sub str 0 recvlen

let close sock =
  try Unix.shutdown sock Unix.SHUTDOWN_ALL
  with _ -> () ;
  Unix.close sock

let string_of_sockaddr = function
  | Unix.ADDR_UNIX s -> s
  | Unix.ADDR_INET (inet,port) ->
      (Unix.string_of_inet_addr inet) ^ ":" ^ (string_of_int port)

(* Repeat what the client says until the client goes away. *)
let rec echo_server sock addr =
  try
    let data = recv sock 1024 in
    if String.length data > 0 then
      (ignore (send sock data);
       echo_server sock addr)
    else
      let cn = string_of_sockaddr addr in
      (printf "echo_server : client (%s) disconnected.\n%!" cn;
       close sock)
  with
  | _ -> close sock

let server () =
  (* Server listens on localhost at 9301 *)
  let addr, port = Unix.inet_addr_loopback, 9301 in
  printf "Echo server listening on 127.0.0.1:%d\n%!" port;
  let saddr = Unix.ADDR_INET (addr, port) in
  let ssock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  (* SO_REUSEADDR so we can restart the server quickly. *)
  Unix.setsockopt ssock Unix.SO_REUSEADDR true;
  Unix.bind ssock saddr;
  Unix.listen ssock 20;
  (* Socket is non-blocking *)
  Unix.set_nonblock ssock;
  try
    (* Wait for clients, and fork off echo servers. *)
    while true do
      let client_sock, client_addr = Aio.accept ssock in
      let cn = string_of_sockaddr client_addr in
      printf "server : client (%s) connected.\n%!" cn;
      Unix.set_nonblock client_sock;
      ignore @@ Aio.async (echo_server client_sock) client_addr
    done
  with
  | _ -> close ssock

(* Main *)

let print_usage_and_exit () =
  print_endline @@ "Usage: " ^ Sys.argv.(0) ^ " [select|libev]";
  exit(0)

let () =
  if Array.length Sys.argv < 2 then
    print_usage_and_exit ()
  else 
    match Sys.argv.(1) with
    | "select" -> Lwt_engine.set (new Lwt_engine.select)
    | "libev" -> Lwt_engine.set (new Lwt_engine.libev)
    | _ -> print_usage_and_exit ()

let () = 
  Aio.run server

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
