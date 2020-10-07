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

open Printf

let send sock str =
  let len = Bytes.length str in
  let total = ref 0 in
  while !total < len do
    let write_count = Aeio.send sock str !total (len - !total) [] in
    total := write_count + !total
  done;
  !total

let recv sock maxlen =
  let str = Bytes.create maxlen in
  let recvlen = Aeio.recv sock str 0 maxlen [] in
  Bytes.sub str 0 recvlen

let close sock =
  try Aeio.shutdown sock Unix.SHUTDOWN_ALL
  with _ -> () ;
  Aeio.close sock

let string_of_sockaddr = function
  | Unix.ADDR_UNIX s -> s
  | Unix.ADDR_INET (inet,port) ->
      (Unix.string_of_inet_addr inet) ^ ":" ^ (string_of_int port)

(* Repeat what the client says until the client goes away. *)
let echo_server sock addr =
  let channel_name = string_of_sockaddr addr in
  let rec loop () =
    let data = recv sock 1024 in
    if Bytes.length data > 0 then begin
      if Bytes.length data = 2 then
        Aeio.cancel (Aeio.my_context ())
      else begin
        printf "echo_server : echo client=%s msg=%s%!" channel_name @@ Bytes.to_string data;
        ignore (send sock data);
        loop ()
      end
    end else
      (printf "echo_server : client=%s disconnected.\n%!" channel_name;
       close sock)
  in
  try loop ()
  with e ->
    begin if e = Aeio.Cancelled then 
      Printf.printf "echo_server : Server connection to client=%s cancelling..\n%!" channel_name;
    end;
    close sock;
    raise e

let server () =
  (* Server listens on localhost at 9301 *)
  let addr, port = Unix.inet_addr_loopback, 9301 in
  printf "Echo server listening on 127.0.0.1:%d\n%!" port;
  printf "Connect as `telnet localhost 9301`\n%!";
  let saddr = Unix.ADDR_INET (addr, port) in
  let ssock = Aeio.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  let ssock_unix = Aeio.get_unix_fd ssock in

  (* configure socket *)
  Unix.setsockopt ssock_unix Unix.SO_REUSEADDR true;
  Unix.bind ssock_unix saddr;
  Unix.listen ssock_unix 20;
  Aeio.set_nonblock ssock;

  try
    let ctxt = Aeio.my_context () in
    (* Wait for clients, and fork off echo servers. *)
    while true do
      let client_sock, client_addr = Aeio.accept ssock in
      let cn = string_of_sockaddr client_addr in
      printf "server : client (%s) connected.\n%!" cn;
      Aeio.set_nonblock client_sock;
      ignore @@ Aeio.async ~ctxt (echo_server client_sock) client_addr
    done
  with
  | e -> 
      begin if e = Aeio.Cancelled then 
        Printf.printf "echo_server : server main thread cancelling..\n%!";
      end;
      close ssock;
      raise e

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
    | "libev" -> Lwt_engine.set (new Lwt_engine.libev ())
    | _ -> print_usage_and_exit ()

let () = 
  Aeio.run server

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
