(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

let route_handler
    ?(shutdown_key : string option  = None)
    ()
  :
    Cohttp_lwt_unix.Server.conn ->
    Cohttp.Request.t ->
    Cohttp_lwt_body.t ->
    (Cohttp.Response.t * Cohttp_lwt_body.t) Lwt.t
  =
  let intermediate =
    (Webapp_common.route_handler
       ((Route_root.route ~shutdown_key)
        (*@ Route_sessions.route *))) in
  fun (conn : Cohttp_lwt_unix.Server.conn)
    (request : Cohttp.Request.t)
    (body : Cohttp_lwt_body.t)
    ->
      let context = { Webapp_common.arguments = []
                    ; Webapp_common.connection = conn
                    ; Webapp_common.request = request
                    ; Webapp_common.body = body }
      in
      intermediate ~context
