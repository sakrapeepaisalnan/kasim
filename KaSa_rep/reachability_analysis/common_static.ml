(**
  * common_static_type.mli
  * openkappa
  * Jérôme Feret & Ly Kim Quyen, projet Abstraction, INRIA Paris-Rocquencourt
  *
  * Creation: 2016, the 18th of Feburary
  * Last modification:
  *
  * Compute the relations between sites in the BDU data structures
  *
  * Copyright 2010,2011,2012,2013,2014,2015,2016 Institut National de Recherche
  * en Informatique et en Automatique.
  * All rights reserved.  This file is distributed
  * under the terms of the GNU Library General Public License *)

let warn parameters mh message exn default =
  Exception.warn parameters mh (Some "BDU side effects") message exn (fun () -> default)  

let trace = false

module Int2Map_HalfBreak_effect =
  Map_wrapper.Make 
    (SetMap.Make
       (struct 
         type t = int * int
         let compare = compare
        end))

module Int2Map_Remove_effect =
  Map_wrapper.Make
    (SetMap.Make
       (struct
         type t = int * int
         let compare = compare
        end))

(*potential partner side effects*)

module Int2Map_potential_effect =
  Map_wrapper.Make
    (SetMap.Make
       (struct
         type t = int * int
         let compare = compare
        end))

type half_break_action = 
  (int list * (int * int) list) Int2Map_HalfBreak_effect.Map.t

(*do not consider the case where site has state free.*)
type remove_action =
  (int list * int list) Int2Map_Remove_effect.Map.t

(*potential side effects*)
type free_partner = (int * int) list Int2Map_potential_effect.Map.t
type bind_partner = (int * int) list Int2Map_potential_effect.Map.t

type potential_partner_free = free_partner
type potential_partner_bind = bind_partner

type bdu_common_static =
  {
    store_side_effects           : half_break_action * remove_action; 
    store_potential_side_effects : potential_partner_free *  potential_partner_bind;
  }

(**********************************************************************************)
(*Implementation*)

let half_break_action parameter error handler rule_id half_break store_result =
  (*module (agent_type, site) -> (rule_id, binding_state) list*)
  let add_link (a, b) (r, state) store_result =
    let error, (l, old) =
      match Int2Map_HalfBreak_effect.Map.find_option_without_logs parameter error
        (a, b) store_result
      with
      | error, None -> error, ([], [])
      | error, Some (l, l') -> error, (l, l')
    in
    let error, result =
      Int2Map_HalfBreak_effect.Map.add_or_overwrite
        parameter error (a, b) (l, (r, state) :: old)
        store_result
    in
    error, result
  in
  (*-------------------------------------------------------------------------------*)
  let error, store_result =
    List.fold_left (fun (error, store_result) (site_address, state_op) ->
      (*site_address: {agent_index, site, agent_type}*)
      let agent_type = site_address.Cckappa_sig.agent_type in
      let site = site_address.Cckappa_sig.site in
      (*state*)
      let error, (state_min, state_max) =
        match state_op with
        | None ->
          begin
            let error, state_value =
              Misc_sa.unsome
                (Int_storage.Nearly_Inf_Int_Int_storage_Imperatif_Imperatif.get
                   parameter
                   error
                   (agent_type, site)
                   handler.Cckappa_sig.states_dic)
                (fun error -> warn parameter error (Some "line 54") Exit
                  (Cckappa_sig.Dictionary_of_States.init()))
            in
            let error, last_entry =
              Cckappa_sig.Dictionary_of_States.last_entry parameter error state_value in
            error, (1, last_entry)
          end
        | Some interval -> error, (interval.Cckappa_sig.min, interval.Cckappa_sig.max)
      in
      (*-------------------------------------------------------------------------------*)
      (*return result*)
      let error, store_result =
        add_link (agent_type, site) (rule_id, state_min) store_result
      in
      error, store_result  
  ) (error, store_result) half_break
  in
  (*-------------------------------------------------------------------------------*)
  (*map function*)
  let store_result =
    Int2Map_HalfBreak_effect.Map.map (fun (l, x) -> List.rev l, x) store_result
  in
  error, store_result

(************************************************************************************)
(*compute remove action: r0 and r1 are remove action *)

let remove_action parameter error rule_id remove store_result =
  let add_link (a, b) r store_result =
    let error, (l, old) =
      match Int2Map_Remove_effect.Map.find_option_without_logs
        parameter error (a, b) store_result
      with
      | error, None -> error, ([], [])
      | error, Some (l, l') -> error, (l, l')
    in
    let error, result =
      Int2Map_Remove_effect.Map.add_or_overwrite
        parameter error (a, b) (l, r :: old) store_result
    in
    error, result
  in
  (*-------------------------------------------------------------------------------*)
  let error, store_result =
    List.fold_left (fun (error, store_result) (agent_index, agent, list_undoc) ->
      let agent_type = agent.Cckappa_sig.agent_name in
      (*NOTE: if it is a site_free then do not consider this case.*)
      (*result*)
      let store_result =
        List.fold_left (fun store_result site ->
          let error, result =
            add_link (agent_type, site) rule_id store_result
          in
          result
        ) store_result list_undoc
      in
      error, store_result
    ) (error, store_result) remove
  in
  (*-------------------------------------------------------------------------------*)
  let store_result =
    Int2Map_Remove_effect.Map.map (fun (l, x) -> List.rev l, x) store_result
  in
  error, store_result

(************************************************************************************)
(*return a potential sites of side effects in the case of half break action*)

let store_potential_half_break parameter error handler rule_id half_break store_result =
  (*map of potential partner that is bond/free*)
  let add_link (agent_type, rule_id) (site, state) store_result =
    let error, old =
      match Int2Map_potential_effect.Map.find_option_without_logs
        parameter error (agent_type, rule_id) store_result
      with
      | error, None -> error, []
      | error, Some l -> error, l
    in
    let error, result =
      Int2Map_potential_effect.Map.add_or_overwrite parameter error
        (agent_type, rule_id) ((site, state) :: old) store_result
    in
    error, result
  in
  (*-------------------------------------------------------------------------------*)
  List.fold_left (fun (error, store_modif_minus) (add, state_op) ->
    let agent_type = add.Cckappa_sig.agent_type in
    let site = add.Cckappa_sig.site in
    (*state*)
    let error, (state_min, state_max) =
      match state_op with
      | None -> 
        begin
          let error, state_value =
            Misc_sa.unsome
              (Int_storage.Nearly_Inf_Int_Int_storage_Imperatif_Imperatif.get
                 parameter
                 error
                 (agent_type, site)
                 handler.Cckappa_sig.states_dic)
              (fun error -> warn parameter error (Some "line 109") Exit 
                (Cckappa_sig.Dictionary_of_States.init()))
               in
              let error, last_entry =
                Cckappa_sig.Dictionary_of_States.last_entry parameter error state_value
              in
              error, (1, last_entry)
        end
      | Some interval -> error, (interval.Cckappa_sig.min, interval.Cckappa_sig.max)
    in
    (*-------------------------------------------------------------------------------*)
    let rec aux k (error, store_result) =
      if k > state_max
      then
        error, store_result
      else
        (*potential partner*)
        match Handler.dual parameter error handler agent_type site k with
        | error, None -> error, store_result
        | error, Some (agent_type2, site2, state2) ->
          let error, store_potential_free =
            add_link (agent_type2, rule_id) (site2, 0) (fst store_result)
          in
          let error, store_potential_bind =
            add_link (agent_type2, rule_id) (site2, state2) (snd store_result)
          in
          error, (store_potential_free, store_potential_bind)
    in aux state_min (error, store_result)
  ) (error, store_result) half_break

(************************************************************************************)
(*potential partner of remove action*)

let store_potential_remove parameter error handler rule_id remove store_result =
  let add_link (agent_type, rule_id) (site, state) store_result =
    let error, old =
      match Int2Map_potential_effect.Map.find_option_without_logs
        parameter error (agent_type, rule_id) store_result
      with
      | error, None -> error, []
      | error, Some l -> error, l
    in
    let error, result =
      Int2Map_potential_effect.Map.add_or_overwrite parameter error (agent_type, rule_id)
        ((site, state) :: old) store_result
    in
    error, result
  in
  (*-------------------------------------------------------------------------------*)
  List.fold_left (fun (error, store_result) (agent_index, agent, list_undoc) ->
    let agent_type = agent.Cckappa_sig.agent_name in
    let error, store_result =
      List.fold_left (fun (error, store_result) site ->
        let error, is_binding =
          Handler.is_binding_site parameter error handler agent_type site
        in
        if is_binding
        then
          begin
            let error, state_dic =
              Misc_sa.unsome
                (Int_storage.Nearly_Inf_Int_Int_storage_Imperatif_Imperatif.get
                   parameter error (agent_type, site) handler.Cckappa_sig.states_dic)
                (fun error -> warn parameter error (Some "line 196") Exit
                  (Cckappa_sig.Dictionary_of_States.init()))
            in
            let error, last_entry =
              Cckappa_sig.Dictionary_of_States.last_entry parameter error state_dic
            in
            (*---------------------------------------------------------------------------*)
            let rec aux k (error, store_result) =
              if k > last_entry
              then error, store_result
              else
                (*potential partner*)
                match Handler.dual parameter error handler agent_type site k with
                | error, None -> error, store_result
                | error, Some (agent_type2, site2, state2) ->
                  (*---------------------------------------------------------------------*)
                  let error, store_potential_free =
                    add_link (agent_type2, rule_id) (site2, 0) (fst store_result)
                  in
                  let error, store_potential_bind =
                    add_link (agent_type2, rule_id) (site2, state2) (snd store_result)
                  in
                  error, (store_potential_free, store_potential_bind)
            in
            aux 1 (error, store_result)
          end          
        else
          error, store_result
      ) (error, store_result) list_undoc
    in
    error, store_result
  ) (error, store_result) remove

(************************************************************************************)

let collect_potential_side_effects_free parameter error handler rule_id 
    half_break remove store_result_map =
  let error, store_result_hb =
    store_potential_half_break
      parameter
      error
      handler
      rule_id
      half_break
      (Int2Map_potential_effect.Map.empty, Int2Map_potential_effect.Map.empty)
  in
  let error, store_result_remove =
    store_potential_remove
      parameter
      error
      handler
      rule_id
      remove
      (Int2Map_potential_effect.Map.empty, Int2Map_potential_effect.Map.empty)
  in
  (*-------------------------------------------------------------------------------*)
  let add_link error (agent_type, rule_id) l store_result =
    let error, old =
      match Int2Map_potential_effect.Map.find_option_without_logs parameter error
        (agent_type, rule_id) store_result
      with
      | error, None -> error, []
      | error, Some l -> error, l
    in
    let new_list = List.concat [l; old] in
    let error, result =
      Int2Map_potential_effect.Map.add parameter error (agent_type, rule_id)
        new_list store_result
    in
    error, result
  in
  (*-------------------------------------------------------------------------------*)
  Int2Map_potential_effect.Map.fold2
    parameter
    error
    (*exists in 'a t*)
    (fun parameter error (agent_type, rule_id) l1 store_result ->
      let error, store_result =
        add_link error (agent_type, rule_id) l1 store_result
      in
      error, store_result
    )
    (*exists in 'b t*)
    (fun paramter error (agent_type, rule_id) l2 store_result ->
      let error, store_result =
        add_link error (agent_type, rule_id) l2 store_result
      in
      error, store_result
    )
    (*exists in both*)
    (fun parameter error (agent_type, rule_id) l1 l2 store_result ->
      let concat = List.concat [l1; l2] in
      let error, store_result =
        add_link error (agent_type, rule_id) concat store_result
      in
      error, store_result
    )
    (fst store_result_hb)
    (fst store_result_remove)
    store_result_map

(************************************************************************************)

let collect_potential_side_effects_bind parameter error handler rule_id 
    half_break remove store_result_map =
  let error, store_result_hb =
    store_potential_half_break
      parameter
      error
      handler
      rule_id
      half_break
      (Int2Map_potential_effect.Map.empty, Int2Map_potential_effect.Map.empty)
  in
  let error, store_result_remove =
    store_potential_remove
      parameter
      error
      handler
      rule_id
      remove
      (Int2Map_potential_effect.Map.empty, Int2Map_potential_effect.Map.empty)
  in
  (*-------------------------------------------------------------------------------*)
  let add_link error (agent_type, rule_id) l store_result =
    let error, old =
      match Int2Map_potential_effect.Map.find_option_without_logs
        parameter error (agent_type, rule_id) store_result 
      with
      | error, None -> error, []
      | error, Some l -> error, l
    in
    let new_list = List.concat [l; old] in
    let error, result =
      Int2Map_potential_effect.Map.add parameter error (agent_type, rule_id)
        new_list store_result
    in
    error, result
  in
  (*-------------------------------------------------------------------------------*)
  Int2Map_potential_effect.Map.fold2
    parameter
    error
    (*exists in 'a t*)
    (fun parameter error (agent_type, rule_id) l1 store_result ->
      let error, store_result =
        add_link error (agent_type, rule_id) l1 store_result
      in
      error, store_result
    )
    (*exists in 'b t*)
    (fun paramter error (agent_type, rule_id) l2 store_result ->
      let error, store_result =
        add_link error (agent_type, rule_id) l2 store_result
      in
      error, store_result
    )
    (*exists in both*)
    (fun parameter error (agent_type, rule_id) l1 l2 store_result ->
      let concat = List.concat [l1; l2] in
      let error, store_result =
        add_link error (agent_type, rule_id) concat store_result
      in
      error, store_result
    )
    (snd store_result_hb)
    (snd store_result_remove)
    store_result_map

(************************************************************************************)

let collect_potential_side_effects parameter error handler rule_id half_break remove
    store_result =
  let error, store_result_free =
    collect_potential_side_effects_free
      parameter
      error
      handler
      rule_id
      half_break
      remove
      (fst store_result)
  in
  let error, store_result_bind =
    collect_potential_side_effects_bind
      parameter
      error
      handler
      rule_id
      half_break
      remove
      (snd store_result)
  in
  error, (store_result_free, store_result_bind)

(************************************************************************************)
(*compute side effects: this is an update before discover bond function *)

let collect_side_effects parameter error handler rule_id half_break remove store_result =
  let store_half_break_action, store_remove_action = store_result in
  (*if there is a half_break action*)
  let error, store_half_break_action =
    half_break_action
      parameter
      error
      handler
      rule_id
      half_break
      store_half_break_action
  in
  (*if there is a remove action*)
  let error, store_remove_action =
    remove_action
      parameter
      error
      rule_id
      remove
      store_remove_action
  in
  error, (store_half_break_action, store_remove_action)

(************************************************************************************)

let scan_rule parameter error handler_kappa rule_id rule store_result =
  (*------------------------------------------------------------------------------*)
  (*side effects*)
  let error, store_side_effects =
    collect_side_effects
      parameter
      error
      handler_kappa
      rule_id 
      rule.Cckappa_sig.actions.Cckappa_sig.half_break
      rule.Cckappa_sig.actions.Cckappa_sig.remove
      store_result.store_side_effects
  in 
  (*------------------------------------------------------------------------------*)
  (*potential partner side effects*)
  let error, store_potential_side_effects =
    collect_potential_side_effects
      parameter
      error
      handler_kappa
      rule_id
      rule.Cckappa_sig.actions.Cckappa_sig.half_break
      rule.Cckappa_sig.actions.Cckappa_sig.remove
      store_result.store_potential_side_effects
  in
  error,
  {
    store_side_effects = store_side_effects;
    store_potential_side_effects = store_potential_side_effects
  }

(************************************************************************************)

let init_bdu_common_static =
  let init_half_break     = Int2Map_HalfBreak_effect.Map.empty  in
  let init_remove         = Int2Map_Remove_effect.Map.empty  in
  let init_potential_free = Int2Map_potential_effect.Map.empty in
  let init_potential_bind = Int2Map_potential_effect.Map.empty in
  let init_common_static =
    {
      store_side_effects            = (init_half_break, init_remove);
      store_potential_side_effects  = (init_potential_free, init_potential_bind); 
    }
  in
  init_common_static

(************************************************************************************)

let scan_rule_set parameter error handler_kappa compil =
  let error, store_result =
    Int_storage.Nearly_inf_Imperatif.fold
      parameter error
      (fun parameter error rule_id rule store_result ->
        scan_rule
          parameter
          error
          handler_kappa
          rule_id
          rule.Cckappa_sig.e_rule_c_rule
          store_result
      ) compil.Cckappa_sig.rules init_bdu_common_static
  in
  error, store_result
