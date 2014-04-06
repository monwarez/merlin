open Std

let rec find_structure md =
  match md.Typedtree.mod_desc with
  | Typedtree.Tmod_structure _ -> Some md
  | Typedtree.Tmod_functor (_,_,_,md) -> find_structure md
  | Typedtree.Tmod_constraint (md,_,_,_) -> Some md
  | _ -> None

let caught catch =
  let caught = !catch in
  catch := [];
  caught

module Last_env = struct
  open Typedtree

  let rec structure { str_final_env = env; str_items = l } =
    Option.value_map (List.last l)
      ~f:structure_item
      ~default:env

  and structure_item { str_desc; str_env } =
    structure_item_desc str_env str_desc

  and structure_item_desc env = function _ -> env
    (*| Tstr_eval (e, _) -> expression e
    | Tstr_value (_, l) ->
      Option.value_map (List.last l)
        ~f:(fun (_,e) -> expression e)
        ~default:env
    | Tstr_primitive v -> value_description v
    | Tstr_exception e -> exception_declaration env e
    | Tstr_module m -> module_expr m
    | Tstr_recmodule l ->
      Option.value_map (List.last l)
        ~f:(fun (_,_,_,m) -> module_expr m)
        ~default:env
    | Tstr_modtype mt -> module_type mt
    | Tstr_class l ->
      Option.value_map (List.last l)
        ~f:(fun (c,_,_) -> class_declaration c)
        ~default:env
    | Tstr_class_type l ->
      Option.value_map (List.last l)
        ~f:(fun (_,_,c) -> class_type_declaration c)
        ~default:env
    | Tstr_include (m,_,_) -> module_expr m
    | Tstr_type _ | Tstr_open _ | Tstr_exn_rebind _ -> env*)

  and expression { exp_desc; exp_env } = expression_desc exp_env exp_desc

  and expression_desc env = function
    | Texp_ident _ | Texp_instvar _ | Texp_constant _ | Texp_apply _ -> env
    | Texp_let (_,_,e) -> expression e
    | Texp_function _ -> env
    (*| Texp_function (_,l,_) ->
      Option.value_map (List.last l)
        ~f:(fun (_,e) -> expression e)
        ~default:env*)
    | Texp_try (e,l) | Texp_match (e,l,_,_) -> env
    (*| Texp_try (e,l) | Texp_match (e,l,_) ->
      expression (Option.value_map (List.last l) ~f:snd ~default:e)*)
    | Texp_array l | Texp_tuple l ->
      Option.value_map (List.last l)
        ~f:expression
        ~default:env
    | Texp_construct _ -> env
    (*| Texp_construct (_,_,l,_) -> *)
      (*Option.value_map (List.last l)
        ~f:expression
        ~default:env*)
    | Texp_variant (_,e) ->
      Option.value_map e
        ~f:expression
        ~default:env
    | Texp_record (l,_) ->
      Option.value_map (List.last l)
        ~f:(fun (_,_,e) -> expression e)
        ~default:env
    | Texp_field (e,_,_) | Texp_setfield (_,_,_,e) | Texp_ifthenelse (_,_,Some e)
    | Texp_ifthenelse (_,e,None) | Texp_sequence (_,e) | Texp_while (_,e)
    | Texp_for (_,_,_,_,_,e) | Texp_send (_,_,Some e)
    | Texp_send (e,_,None) | Texp_letmodule (_,_,_,e) | Texp_lazy e
    | Texp_assert e | Texp_setinstvar (_,_,_,e) -> expression e
    | Texp_new (_,_,c) -> failwith "TODO"
    | Texp_override (_,l) ->
      Option.value_map (List.last l)
        ~f:(fun (_,_,e) -> expression e)
        ~default:env
    | Texp_object (e,_) -> failwith "TODO"
    | Texp_pack m -> module_expr m

  and value_description { val_desc } = core_type val_desc

  and core_type { ctyp_env } = ctyp_env

  and exception_declaration env (*{ exn_params }*) = env
    (*Option.value_map (List.last exn_params)
      ~f:core_type
      ~default:env*)

  and module_expr { mod_env; mod_desc } = module_expr_desc mod_env mod_desc

  and module_expr_desc env = function
    | Tmod_ident _ -> env
    | Tmod_structure s -> structure s
    | Tmod_constraint (m,_,_,_) | Tmod_apply (_,m,_) | Tmod_functor (_,_,_,m) -> module_expr m
    | Tmod_unpack (e,_) -> expression e

  and module_type { mty_env; mty_desc } = module_type_desc mty_env mty_desc

  and module_type_desc env = function
    | Tmty_signature _ | Tmty_ident _ | Tmty_alias _ -> env
    | Tmty_with (m,_) | Tmty_functor (_,_,_,m) -> module_type m
    | Tmty_typeof m -> module_expr m

  and class_infos f { ci_expr } = f ci_expr

  and class_expr { cl_env; cl_desc } = class_expr_desc cl_env cl_desc

  and class_expr_desc env = function
    | Tcl_ident (_,_,l) ->
    Option.value_map (List.last l)
      ~f:core_type
      ~default:env
    | Tcl_structure c -> failwith "TODO"
    | Tcl_fun (_,_,_,e,_) | Tcl_apply (e,_) | Tcl_let (_,_,_,e)
    | Tcl_constraint (e,_,_,_,_) -> class_expr e

  and class_declaration _ = failwith "TODO"

  and class_type_declaration _ = failwith "TODO"
end

module P = struct
  open Raw_parser

  type st = Extension.set * exn list ref

  type t = {
    raw: Raw_typer.t;
    snapshot: Btype.snapshot;
    env: Env.t;
    structures: Typedtree.structure list;
    exns: exn list;
  }

  let empty (extensions,catch) =
    let env = Env.initial_unsafe_string (*FIXME: should be in Raw_typer ?*) in
    let env = Env.open_pers_signature "Pervasives" env in
    let env = Extension.register extensions env in
    let raw = Raw_typer.empty in
    let exns = caught catch in
    let snapshot = Btype.snapshot () in
    { raw; snapshot; env; structures = []; exns }

  let validate _ t = Btype.is_valid t.snapshot

  let rewrite loc =
    let open Parsetree in
    function
    | Raw_typer.Functor_argument (id,mty) ->
      let mexpr = Pmod_structure [] in
      let mexpr = { pmod_desc = mexpr; pmod_loc = loc; pmod_attributes = [] } in
      let mexpr = Pmod_functor (id, mty, mexpr) in
      let mexpr = { pmod_desc = mexpr; pmod_loc = loc; pmod_attributes = [] } in
      failwith "TODO"
    (*let item = Pstr_module (Location.mknoloc "" , mexpr) in
      `fake { pstr_desc = item; pstr_loc = loc }*)
    | Raw_typer.Pattern (l,o,p) ->
      let expr = Pexp_constant (Asttypes.Const_int 0) in
      let expr = { pexp_desc = expr; pexp_loc = loc; pexp_attributes = [] } in
      let expr = Pexp_fun (l, o, p, expr) in
      let expr = { pexp_desc = expr; pexp_loc = loc; pexp_attributes = [] } in
      let item = Pstr_eval (expr,[]) in
      `fake { pstr_desc = item; pstr_loc = loc }
    | Raw_typer.Newtype s ->
      let expr = Pexp_constant (Asttypes.Const_int 0) in
      let expr = { pexp_desc = expr; pexp_loc = Location.none; pexp_attributes = [] } in
      let pat = { ppat_desc = Ppat_any; ppat_loc = Location.none; ppat_attributes = [] } in
      let expr = Pexp_fun ("", None, pat, expr) in
      let expr = { pexp_desc = expr; pexp_loc = Location.none; pexp_attributes = [] } in
      let expr = Parsetree.Pexp_newtype (s,expr) in
      let expr = { pexp_desc = expr; pexp_loc = loc; pexp_attributes = [] } in
      let item = Pstr_eval (expr,[]) in
      `fake { pstr_desc = item; pstr_loc = loc }
    | Raw_typer.Bindings (rec_,e) ->
      let item = Pstr_value (rec_,e) in
      `str [{ pstr_desc = item; pstr_loc = loc }]
    | Raw_typer.Open (override,name) ->
      let item = Pstr_open (Ast_helper.Opn.mk ~override name) in
      `str [{ pstr_desc = item; pstr_loc = loc }]
    | Raw_typer.Eval e ->
      `str [{
        Parsetree. pstr_desc = Parsetree.Pstr_eval (e,[]);
        pstr_loc = e.Parsetree.pexp_loc;
      }]
    | Raw_typer.Structure str -> `str str
    | Raw_typer.Signature sg -> `sg sg

  let append catch loc item t =
    try
      Btype.backtrack t.snapshot;
      let env, structures =
        match item with
        | `str str ->
          let structure,_,env = Typemod.type_structure t.env str loc in
          env, structure :: t.structures
        | `sg sg ->
          let sg = Typemod.transl_signature t.env sg in
          let sg = sg.Typedtree.sig_type in
          Env.add_signature sg t.env, t.structures
        | `fake str ->
          let structure,_,_ =
            Either.get (Parsing_aux.catch_warnings (ref [])
                          (fun () -> Typemod.type_structure t.env [str] loc))
          in
          Last_env.structure structure, structure :: t.structures
        | `none -> t.env, t.structures
      in
      Typecore.reset_delayed_checks ();
      {env; structures; snapshot = Btype.snapshot (); raw = t.raw;
       exns = caught catch @ t.exns}
    with exn ->
      Typecore.reset_delayed_checks ();
      {t with exns = exn :: caught catch @ t.exns;
              snapshot = Btype.snapshot () }

  let frame (_,catch) f t =
    let module Frame = Merlin_parser.Frame in
    let loc = Frame.location f in
    let raw = Raw_typer.step (Frame.value f) t.raw in
    let t = {t with raw} in
    let items = Raw_typer.observe t.raw in
    let items = List.map ~f:(rewrite loc) items in
    let t = List.fold_left' ~f:(append catch loc) items ~init:t in
    t

  let delta st f t ~old:_ = frame st f t

  let evict st _ = ()
end

module I = Merlin_parser.Integrate (P)

type t = {
  btype_cache: Btype.cache;
  env_cache: Env.cache;
  extensions : Extension.set;
  typer : I.t;
}

let fluid_btype = Fluid.from_ref Btype.cache
let fluid_env = Fluid.from_ref Env.cache

let protect_typer ~btype ~env f =
  let caught = ref [] in
  let (>>=) f x = f x in
  Fluid.let' fluid_btype btype >>= fun () ->
  Fluid.let' fluid_env env >>= fun () ->
  Either.join (Parsing_aux.catch_warnings caught >>= fun () ->
               Typing_aux.catch_errors caught >>= fun () ->
               f caught)

let fresh extensions =
  let btype_cache = Btype.new_cache () in
  let env_cache = Env.new_cache () in
  let result = protect_typer ~btype:btype_cache ~env:env_cache
      (fun exns -> I.empty (extensions,exns))
  in
  {
    typer = Either.get result;
    extensions; env_cache; btype_cache;
  }

let update parser t =
  let result =
    protect_typer ~btype:t.btype_cache ~env:t.env_cache
      (fun exns -> I.update' (t.extensions,exns) parser t.typer)
  in
  {t with typer = Either.get result}

let env t = (I.value t.typer).P.env
let structures t = (I.value t.typer).P.structures
let exns t = (I.value t.typer).P.exns
let extensions t = t.extensions

let is_valid t =
  match protect_typer ~btype:t.btype_cache ~env:t.env_cache
          (fun _ -> Env.check_cache_consistency ())
  with
  | Either.L _exn -> false
  | Either.R result -> result
