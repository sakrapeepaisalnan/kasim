type t = {
  init_stopping_times : (Nbr.t * int) list;
  mutable stopping_times : (Nbr.t * int) list;
  perturbations_alive : bool array;
  perturbations_not_done_yet : bool array;
  (* internal array for perturbate function (global to avoid useless alloc) *)
  activities : Random_tree.tree;
  (* pair numbers are regular rule, odd unary instances *)
  mutable flux: (Data.flux_data) list;
}

let initial_activity env counter graph activities =
  Environment.fold_rules
    (fun i () rule ->
       if Array.length rule.Primitives.connected_components = 0 then
         match Nbr.to_float @@ Rule_interpreter.value_alg
             counter graph (fst rule.Primitives.rate) with
         | None ->
           ExceptionDefn.warning ~pos:(snd rule.Primitives.rate)
             (fun f -> Format.fprintf f "Problematic rule rate replaced by 0")
         | Some rate -> Random_tree.add (2*i) rate activities)
    () env

let empty env stopping_times =
  let activity_tree =
    Random_tree.create (2*Environment.nb_rules env) in
  let stops =
    List.sort (fun (a,_) (b,_) -> Nbr.compare a b) stopping_times in
  {
    init_stopping_times = stops;
    stopping_times = stops;
    perturbations_alive =
      Array.make (Environment.nb_perturbations env) true;
    perturbations_not_done_yet =
      Array.make (Environment.nb_perturbations env) true;
    activities = activity_tree;
    flux = [];
  }

let observables_values env graph counter =
  Environment.map_observables
    (Rule_interpreter.value_alg counter graph)
    env

let do_modification ~outputs env counter graph state extra modification =
  let print_expr_val =
    Kappa_printer.print_expr_val
      (Rule_interpreter.value_alg counter graph) in
  match modification with
  | Primitives.ITER_RULE ((v,_),r) ->
    let graph' =
      Nbr.iteri
        (fun _ g ->
           Rule_interpreter.force_rule
             ~outputs env
             (Environment.connected_components_of_unary_rules env)
             counter g (Trace.PERT "pert") r)
        graph (Rule_interpreter.value_alg counter graph v) in
    let graph'',extra' =
      Rule_interpreter.update_outdated_activities
        (fun x _ y -> Random_tree.add x y state.activities)
        env counter graph' in
    ((false,graph'',state),List.rev_append extra' extra)
  | Primitives.UPDATE (i,(expr,_)) ->
    let graph' = Rule_interpreter.overwrite_var i counter graph expr in
    let graph'',extra' =
        Rule_interpreter.update_outdated_activities
          (fun x _ y -> Random_tree.add x y state.activities)
          env counter graph' in
    ((false, graph'', state),List.rev_append extra' extra)
  | Primitives.STOP pexpr ->
    let () = if pexpr <> [] then
        let file = Format.asprintf "@[<h>%a@]" print_expr_val pexpr in
        outputs (Data.Snapshot
                   (Rule_interpreter.snapshot env counter file graph)) in
    ((true,graph,state),extra)
  | Primitives.PRINT (pe_file,pe_expr) ->
    let file_opt =
      match pe_file with
        [] -> None
      | _ -> Some (Format.asprintf "@[<h>%a@]" print_expr_val pe_file)
    in
    let line = Format.asprintf "%a" print_expr_val pe_expr in
    let () = outputs
        (Data.Print
           {Data.file_line_name = file_opt ; Data.file_line_text = line;}) in
    ((false, graph, state),extra)
  | Primitives.PLOTENTRY ->
    let () = outputs (Data.Plot (observables_values env graph counter)) in
    ((false, graph, state),extra)
  | Primitives.SNAPSHOT pexpr  ->
    let file = Format.asprintf "@[<h>%a@]" print_expr_val pexpr in
    let () = outputs (Data.Snapshot
                        (Rule_interpreter.snapshot env counter file graph)) in
    ((false, graph, state),extra)
  | Primitives.CFLOW (name,cc,tests) ->
    let name = match name with
      | Some s -> s
      | None ->
        let domain = Environment.domain env in
        Format.asprintf
          "@[<h>%a@]"
          (Pp.array Pp.comma
             (fun _ -> Pattern.print ~domain ~with_id:false)) cc in
    ((false,
      Rule_interpreter.add_tracked cc (Trace.OBS name) tests graph,
      state),
     extra)
  | Primitives.CFLOWOFF cc ->
    ((false, Rule_interpreter.remove_tracked cc graph, state),extra)
  | Primitives.FLUX (rel,s) ->
    let file = Format.asprintf "@[<h>%a@]" print_expr_val s in
    let () =
      if List.exists
          (fun x -> Fluxmap.flux_has_name file x && x.Data.flux_normalized = rel)
          state.flux
      then ExceptionDefn.warning
          (fun f ->
             Format.fprintf
               f "At t=%f, e=%i: tracking FLUX into \"%s\" was already on"
               (Counter.current_time counter)
               (Counter.current_event counter) file)
    in
    let () = state.flux <-
        Fluxmap.create_flux env counter rel file::state.flux in
    ((false, graph, state),extra)
  | Primitives.FLUXOFF s ->
    let file = Format.asprintf "@[<h>%a@]" print_expr_val s in
    let (these,others) =
      List.partition (Fluxmap.flux_has_name file) state.flux in
    let () = List.iter
        (fun x -> outputs (Data.Flux (Fluxmap.stop_flux env counter x)))
        these in
    let () = state.flux <- others in
    ((false, graph, state),extra)

let rec perturbate ~outputs env counter graph state = function
  | [] -> (false,graph,state)
  | i :: tail ->
    let pert = Environment.get_perturbation env i in
    if state.perturbations_alive.(i) &&
       state.perturbations_not_done_yet.(i) &&
       Rule_interpreter.value_bool
         counter graph (fst pert.Primitives.precondition)
    then
      let (stop,graph,state as acc,extra) =
        List.fold_left (fun ((stop,graph,state),extra as acc) effect ->
            if stop then acc else
              do_modification ~outputs env counter graph state extra effect)
          ((false,graph,state),[]) pert.Primitives.effect in
      let () = state.perturbations_not_done_yet.(i) <- false in
      let () =
        state.perturbations_alive.(i) <-
          match pert.Primitives.abort with
          | None -> false
          | Some (ex,_) ->
            not (Rule_interpreter.value_bool counter graph ex) in
      if stop then acc else
        perturbate ~outputs env counter graph state (List.rev_append extra tail)
    else
      perturbate ~outputs env counter graph state tail

let do_modifications ~outputs env counter graph state list =
  let (stop,graph,state as acc,extra) =
    List.fold_left (fun ((stop,graph,state),extra as acc) effect ->
        if stop then acc else
          do_modification ~outputs env counter graph state extra effect)
      ((false,graph,state),[]) list in
  if stop then acc else perturbate ~outputs env counter graph state extra

let initialize ~bind ~return ~outputs env counter graph0 state0 init_l =
  let mgraph =
    List.fold_left
      (fun mstate (alg,compiled_rule,pos) ->
         bind
           mstate
           (fun (stop,state,state0) ->
              let value =
                Rule_interpreter.value_alg counter state alg in
              let actions,_,_ = snd compiled_rule.Primitives.instantiations in
              let creations_sort =
                List.fold_left
                  (fun l -> function
                     | Instantiation.Create (x,_) ->
                       Matching.Agent.get_type x :: l
                     | Instantiation.Mod_internal _ | Instantiation.Bind _
                     | Instantiation.Bind_to _ | Instantiation.Free _
                     | Instantiation.Remove _ -> l) [] actions in
              return (stop,
                Nbr.iteri
                  (fun _ s ->
                     match Rule_interpreter.apply_rule
                             ~outputs env
                             (Environment.connected_components_of_unary_rules env)
                             counter s (Trace.INIT creations_sort)
                             compiled_rule with
                     | Rule_interpreter.Success s -> s
                     | (Rule_interpreter.Clash | Rule_interpreter.Corrected) ->
                       raise (ExceptionDefn.Internal_Error
                                ("Bugged initial rule",pos)))
                  state value,state0))) (return (false,graph0,state0)) init_l in
  bind
    mgraph
    (fun (_,graph,state0) ->
       let () =
         initial_activity env counter graph state0.activities in
       let mid_graph,_ =
         Rule_interpreter.update_outdated_activities
           (fun x _ y -> Random_tree.add x y state0.activities)
           env counter graph in
       let everybody =
         let t  = Array.length state0.perturbations_alive in
         Tools.recti (fun l i -> (t-i-1)::l) [] t in
       return (perturbate ~outputs env counter mid_graph state0 everybody))

let one_rule ~outputs dt env counter graph state =
  let choice,_ = Random_tree.random
      (Rule_interpreter.get_random_state graph) state.activities in
  let rule_id = choice/2 in
  let rule = Environment.get_rule env rule_id in
  let register_new_activity rd_id syntax_rd_id new_act =
    let () =
      match state.flux with
      | [] -> ()
      | l ->
        let old_act = Random_tree.find rd_id state.activities in
        List.iter
          (fun fl ->
             Fluxmap.incr_flux_flux
               rule.Primitives.syntactic_rule syntax_rd_id
               (
                 let cand =
                   if fl.Data.flux_normalized &&
                      (match classify_float old_act with
                       | (FP_zero | FP_nan | FP_infinite) -> false
                       | (FP_normal | FP_subnormal) -> true)
                   then (new_act -. old_act) /. old_act
                   else (new_act -. old_act) in
                 match classify_float cand with
                 | (FP_nan | FP_infinite) ->
                   let () =
                     let ct = Counter.current_time counter in
                     ExceptionDefn.warning
                       (fun f -> Format.fprintf
                           f "An infinite (or NaN) activity variation has been ignored at t=%f"
                           ct) in 0.
                 | (FP_zero | FP_normal | FP_subnormal) -> cand) fl)
          l
    in Random_tree.add rd_id new_act state.activities in
  let () =
    if !Parameter.debugModeOn then
      Format.printf
        "@[<v>@[Applied@ %t%i:@]@ @[%a@]@]@."
        (fun f -> if choice mod 2 = 1 then Format.fprintf f "unary@ ")
        rule_id (Kappa_printer.elementary_rule ~env) rule
        (*Rule_interpreter.print_dist env graph rule_id*) in
  (* let () = *)
  (*   Format.eprintf "%a@." (Rule_interpreter.print_injections env) graph in *)
  let cause = Trace.RULE rule.Primitives.syntactic_rule in
  let apply_rule =
    if choice mod 2 = 1
    then Rule_interpreter.apply_unary_rule ~outputs ~rule_id
    else Rule_interpreter.apply_rule ~outputs ~rule_id in
  match apply_rule
          env (Environment.connected_components_of_unary_rules env)
          counter graph cause rule with
  | Rule_interpreter.Success (graph') ->
    let final_step = not (Counter.one_constructive_event counter dt) in
    let graph'',extra_pert =
      Rule_interpreter.update_outdated_activities
        register_new_activity env counter graph' in
    let (stop,graph''',state') =
      perturbate ~outputs env counter graph'' state extra_pert in
    let () =
      List.iter
        (fun fl -> Fluxmap.incr_flux_hit rule.Primitives.syntactic_rule fl)
        state.flux in
    let () =
      Array.iteri (fun i _ -> state.perturbations_not_done_yet.(i) <- true)
        state.perturbations_not_done_yet in
    let () =
      if !Parameter.debugModeOn then
        Format.printf "@[<v>Obtained@ %a@]@."
          (Rule_interpreter.print env) graph'' in
    (final_step||stop,graph''',state')
  | (Rule_interpreter.Clash | Rule_interpreter.Corrected) as out ->
    let continue =
      if out = Rule_interpreter.Clash then
        Counter.one_clashing_instance_event counter dt
      else if choice mod 2 = 1
      then Counter.one_no_more_unary_event counter dt
      else Counter.one_no_more_binary_event counter dt in
    if Counter.consecutive_null_event counter < !Parameter.maxConsecutiveClash
    then (not continue,graph,state)
    else
      (not continue,
       (if choice mod 2 = 1
        then Rule_interpreter.adjust_unary_rule_instances
            ~rule_id register_new_activity env counter graph rule
        else Rule_interpreter.adjust_rule_instances
            ~rule_id register_new_activity env counter graph rule),
       state)

let activity state = Random_tree.total state.activities

let a_loop ~outputs env counter graph state =
  let activity = activity state in
  let rd = Random.State.float (Rule_interpreter.get_random_state graph) 1.0 in
  let dt = abs_float (log rd /. activity) in

  let (_,graph',_ as out) =
    (*Activity is null or dt is infinite*)
    if not (activity > 0.) || dt = infinity then
      match state.stopping_times with
      | [] ->
        let () =
          if !Parameter.dumpIfDeadlocked then
            outputs
              (Data.Snapshot
                 (Rule_interpreter.snapshot env counter "deadlock.ka" graph)) in
        let () =
          ExceptionDefn.warning
            (fun f ->
               Format.fprintf
                 f "A deadlock was reached after %d events and %Es (Activity = %.5f)"
                 (Counter.current_event counter)
                 (Counter.current_time counter) activity) in
        (true,graph,state)
      | (ti,pe) :: tail ->
        let () = state.stopping_times <- tail in
        let continue = Counter.one_time_correction_event counter ti in
        let stop,graph',state' =
          perturbate ~outputs env counter graph state [pe] in
        (not continue||stop,graph',state')
    else
      (*activity is positive*)
      match state.stopping_times with
      | (ti,pe) :: tail
        when Nbr.is_smaller ti (Nbr.F (Counter.current_time counter +. dt)) ->
        let () = state.stopping_times <- tail in
        let continue = Counter.one_time_correction_event counter ti in
        let stop,graph',state' =
          perturbate ~outputs env counter graph state [pe] in
        (not continue||stop,graph',state')
      | _ ->
        one_rule ~outputs dt env counter graph state in
  let () =
    Counter.fill ~outputs counter (observables_values env graph') in
  out

let end_of_simulation ~outputs form env counter state =
  let () =
    List.iter
      (fun e ->
         let () =
           ExceptionDefn.warning
             (fun f ->
                Format.fprintf
                  f "Tracking FLUX into \"%s\" was not stopped before end of simulation"
                  (Fluxmap.get_flux_name e)) in
         outputs (Data.Flux (Fluxmap.stop_flux env counter e)))
      state.flux in
  ExceptionDefn.flush_warning form

let batch_loop ~outputs form env counter graph state =
  let rec iter graph state =
    let stop,graph',state' = a_loop ~outputs env counter graph state in
    if stop then (graph',state')
    else let () = Counter.tick form counter in iter graph' state'
  in iter graph state

let interactive_loop ~outputs form pause_criteria env counter graph state =
  let user_interrupted = ref false in
  let old_sigint_behavior =
    Sys.signal
      Sys.sigint (Sys.Signal_handle
                    (fun _ -> if !user_interrupted then raise Sys.Break
                      else user_interrupted := true)) in
  let rec iter graph state =
    if !user_interrupted ||
       Rule_interpreter.value_bool counter graph pause_criteria then
      let () = Sys.set_signal Sys.sigint old_sigint_behavior in
      (false,graph,state)
    else
      let stop,graph',state' as out =
        a_loop ~outputs env counter graph state in
      if stop then
        let () = Sys.set_signal Sys.sigint old_sigint_behavior in
        out
      else let () = Counter.tick form counter in iter graph' state'
  in iter graph state
