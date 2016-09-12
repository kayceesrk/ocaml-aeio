open Sexplib.Std
open Sexplib.Conv

type 'a t = { 
  fin : bool ref;
  next : (unit -> 'a option) ref;
  post_fin : (unit -> unit) ref;
} with sexp

let id () = ()

let finish {fin; post_fin; _} = 
  fin := true;
  (!post_fin) ();
  post_fin := id

let next ({fin; next; _} as s) = 
  if !fin then None
  else 
    match !next () with
    | None -> finish s; None
    | v -> v

let is_empty {fin; _} = !fin

let from f = {
  fin = ref false; 
  next = ref f;
  post_fin = ref id;
}

let rec iter f s =
  match next s with
  | None -> () 
  | Some v -> f v; iter f s

let rec to_list_revacc s acc =
  match next s with
  | None -> acc
  | Some v -> to_list_revacc s (v::acc)

let to_list s = List.rev @@ to_list_revacc s []

let of_list l =
  let r = ref l in
  let fin = ref false in
  let post_fin = ref id in
  let next () =
    match !r with
    | [] -> None
    | x::[] -> fin := true; (!post_fin) (); Some x
    | x::xs -> r := xs; Some x
  in
  (if l = [] then fin := true; (!post_fin) ());
  {fin; next = ref next; post_fin = ref id}

let rec junk_while f s =
  match next s with
  | None -> ()
  | Some v -> 
      if f v then junk_while f s
      else
        let old = !(s.next) in
        s.next := (fun () -> s.next := old; Some v)

let map f s =
  let next = fun () ->
    match next s with
    | None -> None
    | Some r -> Some (f r)
  in
  {s with next = ref next}

let mk_stream fin next = 
  {fin; next = ref next; post_fin = ref id}

let on_terminate s f = 
  let new_f () = !(s.post_fin) (); f() in
  s.post_fin := new_f
