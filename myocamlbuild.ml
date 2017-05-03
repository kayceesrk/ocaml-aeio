open Ocamlbuild_plugin
open Command

let () =
  dispatch begin function
    | After_rules -> 
				flag ["link"; "library"; "ocaml"; "byte"; "use_aeio"]
					(S ([A "-dllib"; A "-laeio_stubs"]));
				flag ["link"; "library"; "ocaml"; "native"; "use_aeio"]
					(S ([A "-cclib"; A "-laeio_stubs"]));
				flag ["link"; "ocaml"; "link_aeio"]
					(A "src/libaeio_stubs.a");
				dep ["link"; "ocaml"; "use_aeio"]
					["src/libaeio_stubs.a"];
    | _ -> ()
  end
