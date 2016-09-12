type 'a t with sexp

val from : (unit -> 'a option) -> 'a t

val is_empty : 'a t -> bool

val next : 'a t -> 'a option

val iter : ('a -> unit) -> 'a t -> unit

val to_list : 'a t -> 'a list

val of_list : 'a list -> 'a t

val junk_while : ('a -> bool) -> 'a t -> unit

val map : ('a -> 'b) -> 'a t -> 'b t

val mk_stream : bool ref -> (unit -> 'a option) -> 'a t

val on_terminate : 'a t -> (unit -> unit) -> unit
