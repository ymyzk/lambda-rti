open Format
open Lambda_rti

let debug = ref false

let empty_formatter = make_formatter (fun _ _ _ -> ()) (fun _ -> ())

let rec read_eval_print lexbuf env tyenv =
  (* Used in all modes *)
  let print f = fprintf std_formatter f in
  (* Used in debug mode *)
  let print_debug f =
    if !debug then
      fprintf err_formatter f
    else
      fprintf empty_formatter f
  in
  flush stderr;
  flush stdout;
  print "# @?";
  begin try
      (* Parsing *)
      print_debug "***** Parser *****\n";
      let e = Parser.toplevel Lexer.main lexbuf in
      print_debug "e: %a\n" Pp.GTLC.pp_program e;

      (* Type inference *)
      print_debug "***** Typing *****\n";
      let tyenv, e, u = Typing.GTLC.type_of_program tyenv e in
      print_debug "e: %a\n" Pp.GTLC.pp_program e;
      print_debug "U: %a\n" Pp.pp_ty u;

      (* NOTE: Typing.GTLC.translate and Typing.CC.type_of_program expect
       * normalized input *)
      let tyenv, e, u = Typing.GTLC.normalize tyenv e u in

      (* Translation *)
      print_debug "***** Cast-insertion *****\n";
      let f, u' = Typing.GTLC.translate tyenv e in
      print_debug "f: %a\n" Pp.CC.pp_program f;
      print_debug "U: %a\n" Pp.pp_ty u';
      assert (Typing.is_equal u u');
      let u'' = Typing.CC.type_of_program tyenv f in
      assert (Typing.is_equal u u'');

      (* Evaluation *)
      print_debug "***** Eval *****\n";
      let env, x, v = Eval.eval_program env f ~debug:!debug in
      print "%a : %a = %a\n"
        pp_print_string x
        Pp.pp_ty2 u
        Pp.CC.pp_value v;
      read_eval_print lexbuf env tyenv
    with
    | Failure message ->
      print "Failure: %s\n" message;
      Lexing.flush_input lexbuf
    | Parser.Error -> (* Menhir *)
      let token = Lexing.lexeme lexbuf in
      print "Parser.Error: unexpected token %s\n" token;
      Lexing.flush_input lexbuf
    | Typing.Type_error message ->
      print "Type_error: %s\n" message
    | Eval.Blame (r, p) -> begin
        match p with
        | Pos -> print "Blame on the expression side:\n%a\n" Utils.Error.pp_range r
        | Neg -> print "Blame on the environment side:\n%a\n" Utils.Error.pp_range r
      end
  end;
  read_eval_print lexbuf env tyenv

let () =
  let usage = "Interpreter of the ITGL with runtime type inference" in
  let options = Arg.align [
      ("-d", Arg.Set debug, " Enable debug mode");
    ] in
  Arg.parse options (fun _ -> ()) usage;
  let lexbuf = Lexing.from_channel stdin in
  let env, tyenv = Stdlib.pervasives in
  read_eval_print lexbuf env tyenv
