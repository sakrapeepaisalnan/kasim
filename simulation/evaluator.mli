(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

val do_interactive_directives :
  outputs:(Data.t -> unit) -> max_sharing:bool -> new_syntax:bool ->
  Contact_map.t -> Model.t -> Counter.t -> Rule_interpreter.t ->
  State_interpreter.t -> (Ast.mixture, string) Ast.modif_expr list ->
  Primitives.modification list *
  (Model.t * (bool * Rule_interpreter.t * State_interpreter.t))

val get_pause_criteria :
  max_sharing:bool -> new_syntax:bool -> Contact_map.t -> Model.t ->
  Rule_interpreter.t -> (Ast.mixture, string) Alg_expr.bool Locality.annot ->
  Model.t * Rule_interpreter.t * (Pattern.id array list, int) Alg_expr.bool
