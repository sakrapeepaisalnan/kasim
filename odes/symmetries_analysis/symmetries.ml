(**
   * symmetries.ml
   * openkappa
   * Jérôme Feret & Ly Kim Quyen, projet Antique, INRIA Paris-Rocquencourt
   *
   * Creation: 2016, the 5th of December
   * Last modification: Time-stamp: <Mar 16 2017>
   *
   * Abstract domain to record relations between pair of sites in connected agents.
   *
   * Copyright 2010,2011,2012,2013,2014,2015,2016 Institut National de Recherche
   * en Informatique et en Automatique.
   * All rights reserved.  This file is distributed
   * under the terms of the GNU Library General Public License *)

(******************************************************************)
(*TYPE*)
(******************************************************************)

type contact_map =
  ((string list) * (string*string) list)
    Mods.StringSetMap.Map.t Mods.StringSetMap.Map.t

type partitioned_contact_map =
  string Symmetries_sig.site_partition Mods.StringSetMap.Map.t

(*internal states * binding states*)
type lkappa_partitioned_contact_map =
  int Symmetries_sig.site_partition array

type symmetries =
  {
    rules: lkappa_partitioned_contact_map;
    rules_and_initial_states: lkappa_partitioned_contact_map option;
    rules_and_alg_expr: lkappa_partitioned_contact_map option
  }

(***************************************************************)
(*PARTITION THE CONTACT MAP*)
(***************************************************************)

let add_gen add find_option k data map =
  let old =
    match
      find_option k map
    with
    | None -> []
    | Some l -> l
  in
  add k (data::old) map

let partition_gen
    empty add find_option fold sort empty_range cache hash int_of_hash f map =
  let map =
    fst
      (Mods.StringMap.fold
         (fun key data (inverse,cache) ->
            let range = f data in
            if range = empty_range
            then inverse, cache
            else
              let sorted_range = sort range in
              let cache, hash = hash cache sorted_range in
              let inverse =
                add_gen
                  add find_option (int_of_hash hash) key inverse
              in
              inverse, cache
         ) map (empty, cache))
  in
  List.rev (fold (fun _ l sol -> (List.rev l)::sol) map [])

let partition cache hash int_of_hash f map =
  partition_gen
    Mods.IntMap.empty
    Mods.IntMap.add
    Mods.IntMap.find_option
    Mods.IntMap.fold
    (List.sort compare)
    []
    cache hash int_of_hash f map

let partition_pair cache hash int_of_hash f map =
  partition_gen
    Mods.Int2Map.empty
    Mods.Int2Map.add
    Mods.Int2Map.find_option
    Mods.Int2Map.fold
    (fun (a,b) ->
       List.sort compare a,
       List.sort compare b)
    ([],[])
    cache hash int_of_hash f map

module State:  SetMap.OrderedType
  with type t = string
  =
struct
  type t = string
  let compare = compare
  let print f s = Format.fprintf f "%s" s
end

module StateList = Hashed_list.Make (State)

module BindingType: SetMap.OrderedType
  with type t = string * string
 =
struct
  type t = string*string
  let compare = compare
  let print f (s1,s2) = Format.fprintf f "%s.%s" s1 s2
end

module BindingTypeList = Hashed_list.Make (BindingType)

let collect_partitioned_contact_map contact_map =
  Mods.StringMap.map
    (fun sitemap ->
       let cache1 = StateList.init () in
       let cache2 = BindingTypeList.init () in
       let (internal_state_partition: string list list) =
         partition
           cache1
           StateList.hash
           StateList.int_of_hashed_list
           fst
           sitemap
       in
       let (binding_state_partition: string list list) =
         partition
           cache2
           BindingTypeList.hash
           BindingTypeList.int_of_hashed_list
           snd
           sitemap
       in
       let full_state_partition =
         partition_pair
           (cache1,cache2)
           (fun
             (cache1,cache2)
             (l1,l2) ->
              let cache1,a1 = StateList.hash cache1 l1 in
              let cache2,a2 = BindingTypeList.hash cache2 l2 in
              (cache1,cache2),(a1,a2))
           (fun (a,b) ->
              StateList.int_of_hashed_list a,
              BindingTypeList.int_of_hashed_list b)
           (fun x->x)
           sitemap
       in
       {
         Symmetries_sig.over_internal_states = internal_state_partition ;
         Symmetries_sig.over_binding_states = binding_state_partition ;
         Symmetries_sig.over_full_states = full_state_partition ;
       }
    ) contact_map

(*****************************************************************)
(*PRINT*)
(*****************************************************************)

  let print_partitioned_contact_map parameters partitioned_contact_map =
    let log = Remanent_parameters.get_logger parameters in
    Mods.StringMap.iter
      (fun agent partition ->
         Symmetries_sig.print
           log
           (fun agent fmt site ->
              Loggers.fprintf log "%s" site)
           (fun fmt agent ->
              Loggers.fprintf log "%s" agent)
           agent
           partition
      ) partitioned_contact_map

let print_partitioned_contact_map_in_lkappa logger env partitioned_contact_map =
  let signature = Model.signatures env in
  Array.iteri
    (fun agent_id partition ->
       Symmetries_sig.print
         logger
         (Signature.print_site signature)
         (Signature.print_agent signature)
         agent_id
         partition
    ) partitioned_contact_map

let print_contact_map parameters contact_map =
  let log = Remanent_parameters.get_logger parameters in
  Mods.StringMap.iter
    (fun agent sitemap ->
       let () = Loggers.fprintf log "agent:%s\n" agent in
       Mods.StringMap.iter
         (fun site (l1,l2) ->
         let () = Loggers.fprintf log "  site:%s\n" site in
         let () =
           if l1 <> []
           then
             let () = Loggers.fprintf log "internal_states:" in
             let () = List.iter (Loggers.fprintf log "%s;") l1 in
             let () = Loggers.print_newline log in ()
         in
         let () =
           if l2 <> []
           then
             let () = Loggers.fprintf log "binding_states:" in
             let () =
               List.iter (fun (s1,s2) ->
                   Loggers.fprintf log "%s.%s;" s1 s2) l2
             in
             let () = Loggers.print_newline log in ()
         in ()) sitemap) contact_map

(****************************************************************)

let translate_list l agent_interface =
  List.rev_map
    (fun equ_class ->
       List.rev_map
         (fun site_string ->
            Signature.num_of_site
              (Locality.dummy_annot site_string)
              agent_interface)
         (List.rev equ_class))
    (List.rev l)

let translate_to_lkappa_representation env partitioned_contact_map =
  let signature = Model.signatures env in
  let nagents = Signature.size signature in
  let array = Array.make nagents Symmetries_sig.empty in
  let () =
    Mods.StringMap.iter
      (fun agent_string partition ->
         let ag_id =
           Signature.num_of_agent
             (Locality.dummy_annot agent_string)
             signature
         in
         let interface = Signature.get signature ag_id in
         let partition =
           Symmetries_sig.map
            (fun site_string  ->
              Signature.num_of_site
                (Locality.dummy_annot site_string)
                interface)
            partition
         in
         array.(ag_id) <- partition)
      partitioned_contact_map
  in
  array

let partition_pair cache p l =
  let rec part cache yes no = function
    | [] -> cache, (List.rev yes, List.rev no)
    | x :: l ->
      let cache, b = p cache x in
      if b
      then part
          cache
          (x :: yes)
          no
          l
      else part cache yes (x :: no) l in
  part cache [] [] l

let refine_class cache p l result =
  let rec aux cache to_do classes =
    match to_do with
    | [] -> cache, classes
    | h::tail ->
      let cache, (newclass, others) =
        partition_pair cache (fun cache -> p cache h) tail
      in
      aux cache others ((h::newclass) :: classes)
  in
  aux cache l result

let refine_class cache p l =
  if l <> [] then
    List.fold_left
      (fun (cache, result) l ->
         let cache, result =
           refine_class cache p l result
         in
         cache, result
      ) (cache, []) l
  else (cache, [])

let refine_partitioned_contact_map_in_lkappa_representation
    cache
    p_internal_state
    p_binding_state
    p_both
    partitioned_contact_map =
  Tools.array_fold_lefti
    (fun agent_type cache partition ->
       let over_binding_states = partition.Symmetries_sig.over_binding_states in
       let over_internal_states = partition.Symmetries_sig.over_internal_states
       in
       let over_full_states = partition.Symmetries_sig.over_full_states in
       let cache, a =
        refine_class
          cache
          (fun cache -> p_internal_state cache agent_type)
          over_internal_states
      in
      let cache, b =
        refine_class
          cache
          (fun cache -> p_binding_state cache agent_type)
          over_binding_states
      in
      let cache, c =
        refine_class
          cache
          (fun cache -> p_both cache agent_type)
          over_full_states
      in
      let () =
        partitioned_contact_map.(agent_type) <-
          {
            Symmetries_sig.over_internal_states = a ;
            Symmetries_sig.over_binding_states = b ;
            Symmetries_sig.over_full_states = c
          }
      in
      cache
    ) cache partitioned_contact_map, partitioned_contact_map

(*****************************************************************)
(*DETECT SYMMETRIES*)
(*****************************************************************)

let max_hash h1 h2 =
  if compare h1 h2 >= 0
  then h1
  else h2

let max_hashes hash_list =
  let rec aux tail best =
    match tail with
    | [] -> best
    | head :: tail -> aux tail (max_hash best head)
  in aux hash_list LKappa_auto.RuleCache.empty

let build_array_for_symmetries hashed_list =
  let max_hash = max_hashes hashed_list in
  let size_hash_plus_1 =
    (LKappa_auto.RuleCache.int_of_hashed_list max_hash) + 1
  in
  let to_be_checked = Array.make size_hash_plus_1 false in
  let counter = Array.make size_hash_plus_1 0 in
  let correct = Array.make size_hash_plus_1 1 in
  let rate =
    Array.make size_hash_plus_1 Rule_modes.RuleModeMap.empty
  in
  to_be_checked, counter, rate, correct

(******************************************************************)
(*from syntactic_rule to cannonic form *)
(******************************************************************)

let divide_rule_rate_by rule_cache env rate_convention rule
    lkappa_rule_init =
  match rate_convention with
  | Remanent_parameters_sig.Common -> assert false
  (* this is not a valid parameterization *)
  (* Common can be used only to compute normal forms *)
  | Remanent_parameters_sig.No_correction -> rule_cache, 1, 1
  | Remanent_parameters_sig.Biochemist
  | Remanent_parameters_sig.Divide_by_nbr_of_autos_in_lhs ->
    let rule_id = rule.Primitives.syntactic_rule in
    let lkappa_rule = Model.get_ast_rule env rule_id in
    let rule_cache, output1 =
      LKappa_auto.nauto rate_convention rule_cache
        lkappa_rule
    in
    let rule_cache, output2 =
      LKappa_auto.nauto rate_convention rule_cache lkappa_rule_init
    in
    rule_cache, output1, output2

let lkappa_init =
  {
    LKappa.r_mix =  [];
    LKappa.r_created = [];
    LKappa.r_delta_tokens = [] ;
    LKappa.r_rate = Alg_expr.int 0 ;
    LKappa.r_un_rate = None  ;
  }

(*convert a species into lkappa rule signature*)
let species_to_lkappa_rule parameters env species =
  let signature = Model.signatures env in
  let some_pair =
    Raw_mixture_extra.pattern_to_raw_mixture
      ~parameters
      signature
      species
  in
  match some_pair with
  | None -> lkappa_init
  | Some (raw_mixture, _) ->
    let lkappa_rule =
      Raw_mixture_group_action.lkappa_of_raw_mixture raw_mixture
    in
    lkappa_rule

(*compute rate*)
let rate rule (_, arity, _) =
  match arity with
  | Rule_modes.Usual -> Some rule.Primitives.rate
  | Rule_modes.Unary ->
    Option_util.map fst rule.Primitives.unary_rate

let valid_modes rule id =
  let add x y list  =
    match y with
    | None -> list
    | Some _ -> x::list
  in
  let mode = Rule_modes.Direct in
  List.rev_map
    (fun x -> id,x,mode)
    (List.rev
       (Rule_modes.Usual::
        (add Rule_modes.Unary rule.Primitives.unary_rate [])))

(*cannonic form from syntactic rule*)
let cannonic_form_from_syntactic_rule
    rule_cache
    env
    rule
    lkappa_rule_init =
  (*over each rule*)
  let rule_id = rule.Primitives.syntactic_rule in
  let lkappa_rule = Model.get_ast_rule env rule_id in
  let rule_cache, hashed_list =
    LKappa_auto.cannonic_form rule_cache lkappa_rule
  in
  let i = LKappa_auto.RuleCache.int_of_hashed_list hashed_list in
  (*initial state*)
  let rule_cache, hashed_list_init =
    LKappa_auto.cannonic_form rule_cache lkappa_rule_init
  in
  let i' =
    LKappa_auto.RuleCache.int_of_hashed_list hashed_list_init in
  (*get the rate information at each rule*)
  let rule_id_with_mode_list = valid_modes rule rule_id in
  let rate_map =
    List.fold_left (fun rate_map rule_id_with_mode ->
        let rate_opt = rate rule rule_id_with_mode in
        let _,a,b = rule_id_with_mode in
        let rate_map =
          match rate_opt with
          | None -> rate_map
          | Some rate ->
            Rule_modes.RuleModeMap.add (a,b) rate rate_map
        in
        rate_map
      ) Rule_modes.RuleModeMap.empty rule_id_with_mode_list
  in
  rule_cache,
  (lkappa_rule, i, rate_map, hashed_list),
  (hashed_list_init, i')

(*cannonic_form_from_syntactic_rules and initial states*)
let cannonic_form_from_syntactic_rules
    rule_cache
    env
    rate_convention
    lkappa_rule_list
    get_rules =
  (*cannonic form from syntactic rule*)
  let rule_cache, cannonic_list, hashed_lists =
    List.fold_left
      (*fold over a list of rules*)
      (fun (rule_cache, current_list, hashed_lists) rule ->
         (*lkappa rule in the initial states*)
         List.fold_left
           (fun (rule_cache, current_list, hashed_lists)
             lkappa_rule_init ->
             (*****************************************************)
             (* identifiers of rule up to isomorphism*)
             let rule_cache,
                 (lkappa_rule, i, rate_map, hashed_list),
                  (hashed_list_init, i') =
                cannonic_form_from_syntactic_rule
                  rule_cache
                  env
                  rule
                  lkappa_rule_init
              in
              (*****************************************************)
              (* convention of r:
                 the number of automorphisms in the lhs of the rule r.
                 - convention_rule1 : the result of convention for each
                 rule.
                 - convention_rule2: the result of convention in the
                 initial states
              *)
              let rule_cache, convention_rule1, convention_rule2 =
                divide_rule_rate_by
                  rule_cache
                  env
                  rate_convention
                  rule
                  lkappa_rule_init
              in
              (*****************************************************)
              (*store result*)
              let current_list =
                ((i, rate_map, convention_rule1),
                 (i', rate_map,  convention_rule2)) :: current_list
              in
              let hashed_lists =
                ((hashed_list, lkappa_rule),
                 (hashed_list_init, lkappa_rule_init)) ::
                hashed_lists
              in
              rule_cache, current_list, hashed_lists
           ) (rule_cache, current_list, hashed_lists)
           lkappa_rule_list
      ) (rule_cache, [], []) get_rules
  in
  rule_cache, cannonic_list, hashed_lists

(******************************************************************)
(*detect_symmetries*)

let check_invariance_gen
    p ?parameters ?env ~to_be_checked ~counter ~correct ~rates
    (hash_and_rule_list: (LKappa_auto.RuleCache.hashed_list *
                          LKappa.rule) list)
    cache agent_type site1 site2 =
  let rec aux hash_and_rule_list (cache, to_be_checked, counter) =
    match hash_and_rule_list with
    | [] -> (cache, to_be_checked, counter), true
    | (hash, rule) :: tail ->
      let id = LKappa_auto.RuleCache.int_of_hashed_list hash in
      if
        to_be_checked.(id)
      then
        let (cache, counter, to_be_checked), b =
          p ?parameters ?env ~agent_type ~site1 ~site2 rule ~correct
            rates cache ~counter to_be_checked
        in
        if b then
          aux tail (cache, to_be_checked, counter)
        else
          (cache, to_be_checked, counter), false
      else
        aux tail (cache, to_be_checked, counter)
  in
  aux hash_and_rule_list (cache, to_be_checked, counter)

let check_invariance_internal_states
    ~correct ~rates ?parameters ?env
    (hash_and_rule_list: (LKappa_auto.RuleCache.hashed_list *
                          LKappa.rule) list)
    (cache, to_be_checked, counter)
    agent_type site1 site2 =
  check_invariance_gen
    LKappa_group_action.check_orbit_internal_state_permutation
    ?parameters ?env
    ~to_be_checked ~counter ~correct ~rates
    hash_and_rule_list cache agent_type site1 site2

let check_invariance_binding_states
    ~correct ~rates ?parameters ?env
    hash_and_rule_list
    (cache, to_be_checked, counter)
    agent_type site1 site2 =
  check_invariance_gen
    LKappa_group_action.check_orbit_binding_state_permutation
    ?parameters ?env
    ~to_be_checked ~counter ~correct ~rates
    hash_and_rule_list cache agent_type site1 site2

let check_invariance_both
    ~correct ~rates ?parameters ?env
    hash_and_rule_list
    (cache, to_be_checked, counter)
    agent_type site1 site2 =
  check_invariance_gen
    LKappa_group_action.check_orbit_full_permutation
    ?parameters ?env
    ~to_be_checked ~counter ~correct ~rates
    hash_and_rule_list cache agent_type site1 site2

let print_symmetries_gen parameters env contact_map
    partitioned_contact_map partitioned_contact_map_in_lkappa
    refined_partitioned_contact_map
    refined_partitioned_contact_map_init
  =
  let () =
    if Remanent_parameters.get_trace parameters
    then
      let logger = Remanent_parameters.get_logger parameters in
      let () = Loggers.fprintf logger "Contact map" in
      let () = Loggers.print_newline logger in
      let () = print_contact_map parameters contact_map in
      let () = Loggers.fprintf logger "Partitioned contact map" in
      let () = Loggers.print_newline logger in
      let () =
        print_partitioned_contact_map parameters partitioned_contact_map in
      let () = Loggers.fprintf logger
          "Partitioned contact map (LKAPPA)"
      in
      let () = Loggers.print_newline logger in
      let () =
        print_partitioned_contact_map_in_lkappa logger env
          partitioned_contact_map_in_lkappa
      in
      let () = Loggers.fprintf logger "With predicate (LKAPPA)" in
      let () = Loggers.print_newline logger in
      let () =
        print_partitioned_contact_map_in_lkappa
          logger env
          refined_partitioned_contact_map
      in
      let () = Loggers.fprintf logger "With predicate (LKAPPA) init" in
      let () = Loggers.print_newline logger in
      let () =
        print_partitioned_contact_map_in_lkappa
          logger env
          refined_partitioned_contact_map_init
      in
      ()
    else
      ()
  in
  ()

  let initial_value_of_arrays cannonic_list arrays =
    let to_be_checked, rates, correct = arrays in
    List.iter
      (fun (i, rate_map, convention_rule) ->
         let () =
           correct.(i) <- convention_rule
         in
         let () =
           rates.(i) <-
             (Rule_modes.add_map (rates.(i)) rate_map)
         in
         let () =
           to_be_checked.(i) <- true
         in
         ()
      ) cannonic_list

let detect_symmetries parameters env cache
    rate_convention
    lkappa_rule_list
    get_rules
    (contact_map:(string list * (string * string) list)
         Mods.StringMap.t Mods.StringMap.t) =
  (*-------------------------------------------------------------*)
  let cache, pair_cannonic_list, pair_list =
    cannonic_form_from_syntactic_rules
      cache
      env
      rate_convention
      lkappa_rule_list
      get_rules
  in
  let hash_and_rule_list, hash_and_rule_list_init =
    List.split pair_list in
  let cannonic_list, init_cannonic_list =
    List.split pair_cannonic_list
  in
  let to_be_checked_init, counter_init, rates_init, correct_init =
    build_array_for_symmetries
      (List.rev_map fst (List.rev hash_and_rule_list_init))
  in
  let () =
    initial_value_of_arrays init_cannonic_list
      (to_be_checked_init, rates_init, correct_init)
  in
  (********************************************************)
  (*detect symmetries for rules*)
  let to_be_checked, counter, rates, correct =
    build_array_for_symmetries
      (List.rev_map fst (List.rev hash_and_rule_list))
  in
  let () =
    initial_value_of_arrays cannonic_list
      (to_be_checked, rates, correct)
  in
  (*-------------------------------------------------------------*)
  (*PARTITION A CONTACT MAP RETURN A LIST OF LIST OF SITES*)
  let partitioned_contact_map =
    collect_partitioned_contact_map contact_map
  in
  (*-------------------------------------------------------------*)
  (*PARTITION A CONTACT MAP RETURN A LIST OF LIST OF SITES WITH A
    PREDICATE*)
  let partitioned_contact_map_in_lkappa =
    translate_to_lkappa_representation env partitioned_contact_map
  in
  let p' = Array.copy partitioned_contact_map_in_lkappa in
  (*-------------------------------------------------------------*)
  (*rules*)
  let (cache, _, _), refined_partitioned_contact_map =
    let parameters, env = Some parameters, Some env in
    refine_partitioned_contact_map_in_lkappa_representation
      (cache, to_be_checked, counter)
      (check_invariance_internal_states
         ?parameters
         ?env ~correct ~rates hash_and_rule_list)
      (check_invariance_binding_states
         ?parameters
         ?env ~correct ~rates hash_and_rule_list)
      (check_invariance_both
         ?parameters
         ?env ~correct ~rates hash_and_rule_list)
      p'
  in
  let refined_partitioned_contact_map =
    Array.map Symmetries_sig.clean refined_partitioned_contact_map
  in
  (*-------------------------------------------------------------*)
  (*rule and initial states*)
  (*a copy of refined partition of rules*)
  let refined_partitioned_contact_map_copy =
    Array.copy refined_partitioned_contact_map
  in
  let (cache, _, _), refined_partitioned_contact_map_init =
    let parameters, env = Some parameters, Some env in
    let correct = correct_init in
    let rates = rates_init in
    refine_partitioned_contact_map_in_lkappa_representation
      (cache, to_be_checked_init, counter_init)
      (check_invariance_internal_states
         ?parameters
         ?env ~correct ~rates hash_and_rule_list_init)
      (check_invariance_binding_states
         ?parameters
         ?env ~correct ~rates hash_and_rule_list_init)
      (check_invariance_both
         ?parameters
         ?env ~correct ~rates hash_and_rule_list_init)
      refined_partitioned_contact_map_copy
  in
  let refined_partitioned_contact_map_init =
    Array.map Symmetries_sig.clean
      refined_partitioned_contact_map_init
  in
  (*-------------------------------------------------------------*)
  (*print*)
  let () =
    print_symmetries_gen parameters env contact_map
      partitioned_contact_map partitioned_contact_map_in_lkappa
      refined_partitioned_contact_map
      refined_partitioned_contact_map_init
  in
  cache,
  {
    rules = refined_partitioned_contact_map;
    rules_and_initial_states =
      Some refined_partitioned_contact_map_init;
    rules_and_alg_expr = None
  }

(******************************************************)

module Cc =
struct
  type t = Pattern.cc
  let compare = compare
  let print _ _ = ()
end

module CcSetMap = SetMap.Make(Cc)

module CcMap = CcSetMap.Map

type cache = Pattern.cc CcMap.t

let empty_cache () = CcMap.empty

let representant ?parameters signature cache rule_cache preenv_cache
    symmetries species =
  match CcMap.find_option species cache with
  | Some species -> cache, rule_cache, preenv_cache, species
  | None ->
    let rule_cache, preenv_cache, species' =
      Pattern_group_action.normalize
        ?parameters
        signature
        rule_cache
        preenv_cache
        symmetries.rules (*TODO*)
        species
    in
    let cache  = CcMap.add species species' cache in
    cache, rule_cache, preenv_cache, species'

let print_symmetries parameters env symmetries =
  let log = Remanent_parameters.get_logger parameters in
  let () = Loggers.fprintf log "Symmetries:" in
  let () = Loggers.print_newline  log in
  let () = Loggers.fprintf log "In rules:" in
  let () = Loggers.print_newline  log in
  let () = print_partitioned_contact_map_in_lkappa log env
      symmetries.rules
  in
  let () =
    match
      symmetries.rules_and_initial_states
    with
    | None -> ()
    | Some sym ->
      let () = Loggers.fprintf log "In rules and initial states:" in
      let () = Loggers.print_newline log in
      let () =
        print_partitioned_contact_map_in_lkappa log env sym
      in
      ()
  in ()