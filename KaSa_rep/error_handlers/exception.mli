(** Time-stamp: <Jul 02 2016>*)

type method_handler = Exception_without_parameter.method_handler

val empty_error_handler : method_handler

val warn_with_exn :
  Remanent_parameters_sig.parameters -> method_handler ->
  string * int * int * int  -> ?message:string -> ?pos:Locality.t option ->
  exn -> (unit -> 'a) -> method_handler * 'a

val warn :
  Remanent_parameters_sig.parameters -> method_handler ->
  string * int * int * int  -> ?message:string -> ?pos:Locality.t ->
  exn -> 'a -> method_handler * 'a

val print : Remanent_parameters_sig.parameters -> method_handler -> unit
val print_errors_light_for_kasim : Remanent_parameters_sig.parameters -> method_handler -> unit
val print_for_KaSim : Remanent_parameters_sig.parameters -> method_handler -> unit

val wrap : Remanent_parameters_sig.parameters ->
  method_handler -> string -> string option -> exn -> method_handler

val check_point :
  (Remanent_parameters_sig.parameters -> method_handler -> 'a -> ?message:string -> ?pos:Locality.t ->
   exn -> unit -> method_handler * unit) ->
  Remanent_parameters_sig.parameters -> method_handler -> method_handler ->
  'a -> ?message:string -> ?pos:Locality.t -> exn -> method_handler
