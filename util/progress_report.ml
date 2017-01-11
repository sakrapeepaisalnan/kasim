(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

type bar = {
  mutable ticks : int ;
  bar_size : int ;
  bar_char : char ;
}

type text = {
  mutable last_length : int;
  mutable last_time : float;
}

type t = Bar of bar | Text of text

let inc_tick c = c.ticks <- c.ticks + 1

let create bar_size bar_char =
  if Unix.isatty Unix.stdout
  then Text { last_length = 0; last_time = -5.;  }
  else
    let () =
      for _ = bar_size downto 1 do
        Format.pp_print_string Format.std_formatter "_"
      done in
    let () = Format.pp_print_newline Format.std_formatter () in
    Bar { ticks = 0; bar_size; bar_char; }

let pp_not_null f x =
  match classify_float x with
  | FP_normal ->
    Format.fprintf f " (%.2f%%)" (x *. 100.)
  | FP_subnormal | FP_zero | FP_infinite | FP_nan -> ()

let pp_text time t_r event e_r f s =
  let string =
    Format.asprintf "%.2f time units%a in %i events%a"
      time pp_not_null t_r event pp_not_null e_r in
  let () =
    Format.fprintf f "%s%s@?" (String.make s.last_length '\b') string in
  s.last_length <- String.length string

let tick time t_r event e_r = function
  | Bar s ->
    let n_t = t_r *. (float_of_int s.bar_size) in
    let n_e = e_r *. (float_of_int s.bar_size) in
    let n = ref (int_of_float (max n_t n_e) - s.ticks) in
    while !n > 0 do
      Format.fprintf Format.std_formatter "%c" s.bar_char;
      let () = if !Parameter.eclipseMode then
          Format.pp_print_newline Format.std_formatter () in
      inc_tick s; decr n
    done;
    Format.pp_print_flush Format.std_formatter ()
  | Text s ->
    let run = Sys.time () in
    if run -. s.last_time > 2. then
      let () = pp_text time t_r event e_r Format.std_formatter s in
      s.last_time <- run

let complete_progress_bar time event t =
  let () =
    match t with
    | Bar t ->
      for _ = t.bar_size - t.ticks downto 1 do
        Format.printf "%c" t.bar_char
      done
    | Text s -> pp_text time 1. event 1. Format.std_formatter s in
  Format.pp_print_newline Format.std_formatter ()
