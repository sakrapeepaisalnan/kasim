(**
   * communication.ml
   * openkappa
   * Jérôme Feret & Ly Kim Quyen, projet Abstraction, INRIA Paris-Rocquencourt
   *
   * Creation: 2016, the 22th of February
   * Last modification:
   *
   * Abstract domain to record live rules
   *
   * Copyright 2010,2011,2012,2013,2014,2015,2016 Institut National de Recherche
   * en Informatique et en Automatique.
   * All rights reserved.  This file is distributed
   * under the terms of the GNU Library General Public License *)

type rule_id = Cckappa_sig.rule_id
type agent_id = Cckappa_sig.agent_id
type agent_type = Cckappa_sig.agent_name
type site_name = Cckappa_sig.site_name
type state_index = Cckappa_sig.state_index

type event =
| Dummy (* to avoid compilation warning *)
| Check_rule of rule_id
| See_a_new_bond of ((agent_type * site_name * state_index) * 
                        (agent_type * site_name * state_index))

type step =
  {
    site_out: site_name;
    site_in: site_name;
    agent_type_in: agent_type
  }

type path =
  {
    agent_id: agent_id;
    relative_address: step list;
    site: site_name;
  }

module type PathMap =
sig
  type 'a t
  val empty: 'a -> 'a t
  val add: path -> 'a -> 'a t -> 'a t
  val find: path -> 'a t -> 'a option
end

module PathMap:PathMap

type precondition

type 'a fold =
  Remanent_parameters_sig.parameters ->
  Exception.method_handler ->
  agent_type ->
  site_name ->
  Exception.method_handler *
    ((Remanent_parameters_sig.parameters ->
      state_index ->
      agent_type * site_name * state_index ->
      Exception.method_handler * 'a ->
      Exception.method_handler * 'a) ->
     Exception.method_handler -> 'a ->
     Exception.method_handler * 'a) Usual_domains.flat_lattice
				    
val dummy_precondition: precondition

val is_the_rule_applied_for_the_first_time:
  precondition -> Usual_domains.maybe_bool

val the_rule_is_applied_for_the_first_time:
  Remanent_parameters_sig.parameters ->
  Exception.method_handler ->
  precondition ->
  Exception.method_handler * precondition

val the_rule_is_not_applied_for_the_first_time:
  Remanent_parameters_sig.parameters ->
  Exception.method_handler ->
  precondition ->
  Exception.method_handler * precondition

val get_state_of_site:
  Exception.method_handler ->
  precondition ->
  path ->
  Exception.method_handler * precondition * int list Usual_domains.flat_lattice

type prefold = { fold: 'a. 'a fold}

(*fill in is_enable where it output the precondition, take the
  precondition, refine, the previous result, and output the new
  precondition*)

val refine_information_about_state_of_site:
  precondition ->
  (Exception.method_handler ->
   path ->
   int list Usual_domains.flat_lattice ->
   Exception.method_handler * int list Usual_domains.flat_lattice) ->
  precondition

val get_potential_partner:
  precondition ->
  (agent_type -> site_name -> state_index -> precondition *
   (((agent_type * site_name * state_index) Usual_domains.flat_lattice)))

val fold_over_potential_partners:
  Remanent_parameters_sig.parameters ->
  Exception.method_handler ->
  precondition ->
  agent_type ->
  site_name ->
  (Remanent_parameters_sig.parameters ->
   state_index ->
   agent_type * site_name * state_index ->
   Exception.method_handler * 'a -> Exception.method_handler * 'a) ->
  'a ->
  Exception.method_handler * precondition * 'a Usual_domains.top_or_not
					       
val overwrite_potential_partners_map:
  Remanent_parameters_sig.parameters ->
  Exception.method_handler ->
  precondition ->
  (agent_type ->
   site_name ->
   state_index ->
   (agent_type * site_name * state_index) Usual_domains.flat_lattice)
  -> prefold ->
  Exception.method_handler * precondition

