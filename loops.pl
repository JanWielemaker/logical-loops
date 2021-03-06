/*  Part of SWI-Prolog

    Author:        Joachim Schimpf,
		   Jan Wielemaker (SWI-Prolog port)
    E-mail:        J.Wielemaker@vu.nl
    WWW:           http://www.swi-prolog.org
*/

% ----------------------------------------------------------------------
% This code accompanies the article
%
%	J. Schimpf: Logical Loops, ICLP 2002
%
% Author: Joachim Schimpf, IC-Parc, Imperial College, London
% Copyright (C) Imperial College London and Parc Technologies 1997-2002
%
% This source code is provided "as is" without any warranty express or
% implied, including but not limited to the warranty of non-infringement
% and the implied warranties of merchantability and fitness for a
% particular purpose.  You may use this code, copy it, distribute it,
% modify it or sell it, provided that this copyright notice is preserved.
% ----------------------------------------------------------------------

:- module(loops,
	  [ do/2,			% +Specs, +PredTemplace
	    op(1100, xfy, do)
	  ]).
:- use_module(library(error)).
:- use_module(library(lists)).
:- use_module(library(ordsets)).
:- use_module(library(apply)).

/** <module> Logical loops

This module implements _logical loops_, initially introduced in ECLiPSe.
The implementation is based on  the  original   version  as  it is found
[here](http://eclipseclp.org/software/loops/index.html). This version is
also used by SICStus 4.0.

Logical loops allow for interating  over  the   members  of  one or more
collections. The loop is rewritten  at   compile  time  into an auxilery
recursive  predicate.  This  implies  that   it  uses  normal  _forward_
execution  of  Prolog,  as  opposed  to  forall(member(X,List),Goal)  or
findall(R, member(X,List),process(X,R), Result).
*/

%%	(+Spec do :Body)
%
%	Logical loop. Body is executed for   each iteration as specified
%	by Spec. The do/2 construct is compiled to a recursive predicate
%	using expand_goal/2. The execution is   _forwards_  and bindings
%	introduced by Body are  thus   retained.  The  following example
%	creates a list with 5 a's:
%
%	  ==
%	  ?- length(List,5), (foreach(X,List) do X = a).
%	  List = [a,a,a,a,a].
%	  ==
%
%	Multiple iterators may be separated by   the  =|,|= (comma). All
%	_terminating_ iterators must terminate at  the same iteration or
%	the goal fails. The above may be  re-written as below, using the
%	for(Var,Low,High) iterator to specify the   number of iterations
%	and the foreach(X,List) to generate the _List_.
%
%	  ==
%	  ?- (for(_,1,5), foreach(X,List) do X = a).
%	  List = [a,a,a,a,a].
%	  ==
%
%	The following iterators are defined:
%
%	  * foreach(-Elem,?List)
%	  Iterate over all elements of List.  Acts as a terminating
%	  iterator if List is bound to a proper list.  Builds a list
%	  if List is unbound.
%	  * foreacharg(-Arg,+Compound)
%	  Iterate over all argument of a compound term.  Acts as a
%	  terminating iterator.
%	  * foreacharg(-Arg,+Compound,-Index)
%	  As foreacharg(-Arg,+Compound), but also makes the argument
%	  index (1..) available to Body.
%	  * for(-I,+Low,+High)
%	  Iterate over Low..High with steps of one.  Same as
%	  for(I,Low,High,1)
%	  * for(-I,+Low,+High,+Step)
%	  Iterate over Low..High with steps of size Step.
%	  * count(-I,+Low,?High)
%	  Same as for(I,Low,High), but High may be unbound, creating
%	  a non-terminating iterator that binds High to
%	  `Low+Iterations`.
%	  * fromto(?From,?I0,?I1,?To)
%	  This is the most general interator.  The Body steps I0 to
%	  I1.  The initial value is From and the iteration stops at
%	  To.  For example, a counting loop can be implemented using
%
%	    ==
%	    ?- fromto(1,I0,I1,5) do writeln(I0), I1 is I0+1.
%	    ==
%
%	  This construct is typically used as an aggregator though.
%	  For example:
%
%	    ==
%	    sumlist(List,Sum) :-
%	       (   foreach(X,List),
%		   fromto(0,S0,S1,Sum)
%	       do  S1 is S0+X
%	       ).
%	    ==
%
%	 In addition to interators, Spec   may define *parameters* using
%	 the construct param(Var1,  ...),  i.e.,   a  term  with functor
%	 `param` and 1 or more (variable)  arguments. Where variables in
%	 Body are by default  local  to   body,  variables  declared  as
%	 parameters are _shared_ with the rest of the clause.
%
%	 *Issues and discussion*
%
%	  - The _base clause_ of the generated recursive predicate is
%	    uses a cut (!).  Non-determinism of the Body is retained.
%	    For iterators such as _count_, this is probably correct.
%	    For e.g., _foreach_, non-determinism seems more logical.
%
%	@compat	The current set of iterators is compatible with
%		SICStus 4.  Current ECLiPSe versions have a more
%		extended set.
%	@compat	The param(Param, ...) declaration is optional.  If
%		omitted, variables that are shared with the enclosing
%		clause are considered parameters.

(Specs do PredTemplate) :-
	get_specs(Specs, Firsts, BaseHead,
		  PreGoals, RecHead, AuxGoals, RecCall), !,
	call(PreGoals),
	do_loop(Firsts, body(RecHead,(AuxGoals,PredTemplate),RecCall), BaseHead).
(Specs do _PredTemplate) :-
	type_error(do_loop_specifier, Specs).

do_loop(Args, _BodyTemplate, BaseHead) :-
	copy_term(BaseHead, Copy),
	Copy = Args, !.
do_loop(Args, BodyTemplate, BaseHead) :-
	copy_term(BodyTemplate, Copy),
	Copy = body(Args, Goal, RecArgs),
	call(Goal),
	do_loop(RecArgs, BodyTemplate, BaseHead).


		 /*******************************
		 * COMPILE-TIME TRANSFORMATION	*
		 *******************************/

t_do((Specs do PredTemplate), Name, NewGoal, NewClauses) :-
	get_specs(Specs, Firsts, Lasts, PreGoals, RecHeadArgs,
		  AuxGoals, RecCallArgs), !,
	FirstCall =.. [Name|Firsts],		% make replacement goal
	flatten_and_clean(PreGoals, FirstCall, NewGoal),
	BaseHead =.. [Name|Lasts],		% make auxiliary predicate
	RecHead =.. [Name|RecHeadArgs],
	RecCall =.. [Name|RecCallArgs],
	flatten_and_clean((AuxGoals,PredTemplate), RecCall, BodyGoals),
	NewClauses = [
	    (BaseHead :- !),
	    (RecHead :- BodyGoals)
	].
t_do((Specs do _PredTemplate), _, _, _) :-
	type_error(do_loop_specifier, Specs).

flatten_and_clean(G, Gs, (G,Gs)) :- var(G), !.
flatten_and_clean(true, Gs, Gs) :- !.
flatten_and_clean((G1,G2), Gs0, Gs) :- !,
	flatten_and_clean(G1, Gs1, Gs),
	flatten_and_clean(G2, Gs0, Gs1).
flatten_and_clean(G, Gs, (G,Gs)).


% get_spec defines the meaning of each iteration specifier

get_specs(Specs, Firsts, Lasts, Pregoals, RecHead, AuxGoals, RecCall) :-
	get_specs(Specs,
		  Firsts, [], Lasts, [],
		  Pregoals, true, RecHead, [],
		  AuxGoals, true, RecCall, []).

get_specs((Specs1,Specs2),
	  Firsts, Firsts0, Lasts, Lasts0,
	  Pregoals, Pregoals0, RecHead, RecHead0,
	  AuxGoals, AuxGoals0, RecCall, RecCall0) :- !,
	get_specs(Specs1,
		  Firsts, Firsts1, Lasts, Lasts1,
		  Pregoals, Pregoals1, RecHead, RecHead1,
		  AuxGoals, AuxGoals1, RecCall, RecCall1),
	get_specs(Specs2,
		  Firsts1, Firsts0, Lasts1, Lasts0,
		  Pregoals1, Pregoals0, RecHead1, RecHead0,
		  AuxGoals1, AuxGoals0, RecCall1, RecCall0).
get_specs(Spec,
	  Firsts, Firsts0, Lasts, Lasts0,
	  Pregoals, Pregoals0, RecHead, RecHead0,
	  AuxGoals, AuxGoals0, RecCall, RecCall0) :-
	get_spec(Spec,
		 Firsts, Firsts0, Lasts, Lasts0,
		 Pregoals, Pregoals0, RecHead, RecHead0,
		 AuxGoals, AuxGoals0, RecCall, RecCall0).

%:- mode get_spec(+,-,+,-,+,-,+,-,+,-,+,-,+).
get_spec(foreach(E,List),
	[List|Firsts], Firsts,
	[[]|Lasts], Lasts,
	Pregoals, Pregoals,
	[[E|T]|RecHeads], RecHeads,
	Goals, Goals,
	[T|RecCalls], RecCalls) :- !.
get_spec(foreacharg(A,Struct),
	[Struct,1,N1|Firsts], Firsts,
	[_,I0,I0|Lasts], Lasts,
	(functor(Struct,_,N),N1 is N+1,Pregoals), Pregoals,
	[S,I0,I2|RecHeads], RecHeads,
	(I1 is I0+1,arg(I0,S,A),Goals), Goals,
	[S,I1,I2|RecCalls], RecCalls) :- !.
get_spec(foreacharg(A,Struct,I0),
	[Struct,1,N1|Firsts], Firsts,
	[_,I0,I0|Lasts], Lasts,
	(functor(Struct,_,N),N1 is N+1,Pregoals), Pregoals,
	[S,I0,I2|RecHeads], RecHeads,
	(I1 is I0+1,arg(I0,S,A),Goals), Goals,
	[S,I1,I2|RecCalls], RecCalls) :- !.
get_spec(fromto(From,I0,I1,To),		% accumulator pair needed
	[From,To|Firsts], Firsts,
	[L0,L0|Lasts], Lasts,
	Pregoals, Pregoals,
	[I0,L1|RecHeads], RecHeads,
	Goals, Goals,
	[I1,L1|RecCalls], RecCalls ) :-
	\+ ground(To), !.
get_spec(fromto(From,I0,I1,To),		% ground(To), only one arg
	[From|Firsts], Firsts,
	[To|Lasts], Lasts,
	Pregoals, Pregoals,
	[I0|RecHeads], RecHeads,
	Goals, Goals,
	[I1|RecCalls], RecCalls) :- !.
get_spec(count(I,FromExpr,To),		% accumulator pair needed
	[From,To|Firsts], Firsts,
	[L0,L0|Lasts], Lasts,
	Pregoals, Pregoals0,
	[I0,L1|RecHeads], RecHeads,
	(I is I0+1,Goals), Goals,
	[I,L1|RecCalls], RecCalls) :-
	var(I), \+ ground(To), !,
	(   number(FromExpr)
	->  Pregoals = Pregoals0,
	    From is FromExpr-1
	;   Pregoals = (From is FromExpr-1, Pregoals0)
	).
get_spec(count(I,FromExpr,To),
	[From|Firsts], Firsts,
	[To|Lasts], Lasts,
	Pregoals, Pregoals0,
	[I0|RecHeads], RecHeads,
	(I is I0+1,Goals), Goals,
	[I|RecCalls], RecCalls) :-
	var(I), integer(To), !,
	(   number(FromExpr)
	->  Pregoals = Pregoals0,
	    From is FromExpr-1
	;   Pregoals = (From is FromExpr-1, Pregoals0)
	).
get_spec(for(I,From,To),
	Firsts, Firsts0, Lasts, Lasts0, Pregoals, Pregoals0,
	RecHead, RecHead0, AuxGoals, AuxGoals0, RecCall, RecCall0) :- !,
	get_spec(for(I,From,To,1), Firsts, Firsts0, Lasts, Lasts0, Pregoals, Pregoals0,
		 RecHead, RecHead0, AuxGoals, AuxGoals0, RecCall, RecCall0).
get_spec(for(I,FromExpr,To,Step),	% Special cases, only 1 arg needed
	[From|Firsts], Firsts,
	[Stop|Lasts], Lasts,
	Pregoals, Pregoals0,
	[I|RecHeads], RecHeads,
	(I1 is I+Step,Goals), Goals,
	[I1|RecCalls], RecCalls) :-
	var(I),
	integer(Step),
	number(To),
	(   number(FromExpr)
	->  From = FromExpr,
	    Pregoals = Pregoals0,
	    compute_stop(From,To,Step,Stop,StopGoal),
	    call(StopGoal)		% compute Stop now
	;   Step == 1
	->  Stop is To+1,
	    Pregoals = (From is min(FromExpr,Stop), Pregoals0)
	;   Step == -1
	->  Stop is To-1,
	    Pregoals = (From is max(FromExpr,Stop), Pregoals0)
	;   fail			% general case
	), !.
get_spec(for(I,FromExpr,ToExpr,Step),	% Step constant: 2 args needed
	[From,Stop|Firsts], Firsts,
	[L0,L0|Lasts], Lasts,
	Pregoals, Pregoals0,
	[I,L1|RecHeads], RecHeads,
	(I1 is I+Step,Goals), Goals,
	[I1,L1|RecCalls], RecCalls) :-
	var(I), integer(Step), !,
	compute_stop(From,ToExpr,Step,Stop,StopGoal),
	Pregoals1 = (StopGoal,Pregoals0),
	(   number(FromExpr)
	->  Pregoals = Pregoals1, From = FromExpr
	;   var(FromExpr)
	->  Pregoals = Pregoals1, From = FromExpr
	;   Pregoals = (From is FromExpr, Pregoals1)
	).
get_spec(Param,
	GlobsFirsts, Firsts,
	GlobsLasts, Lasts,
	Pregoals, Pregoals,
	GlobsRecHeads, RecHeads,
	Goals, Goals,
	GlobsRecCalls, RecCalls) :-
	Param =.. [param|Globs], Globs = [_|_], !,
	append(Globs, Firsts, GlobsFirsts),
	append(Globs, Lasts, GlobsLasts),
	append(Globs, RecHeads, GlobsRecHeads),
	append(Globs, RecCalls, GlobsRecCalls).


%%	compute_stop(+From, +To, +Step, ?Stop, -Goal) is det.
%
%	Goal is a body term that contains   Stop. When executed, Stop is
%	unified with the final iteration value.

compute_stop(From, To, 1, Stop, Goal) :- !,
	Goal = (Stop is max(From, To+1)).
compute_stop(From, To, -1, Stop, Goal) :- !,
	Goal = (Stop is min(From,To-1)).
compute_stop(From, To, Step, Stop, Goal) :- Step > 0, !,
	Goal = (Dist is max(To-From+Step,0),
		Stop is From + Dist - (Dist mod Step)).
compute_stop(From, To, Step, Stop, Goal) :- Step < 0, !,
	Goal = (Dist is max(From-To-Step,0),
		Stop is From - Dist + (Dist mod Step)).


		 /*******************************
		 *	     EXPANSION		*
		 *******************************/

system:goal_expansion(Goal, NewGoal) :-
	Goal = (Spec do PredTemplate),
	prolog_load_context(module, M),
	predicate_property(M:do(_,_), imported_from(loops)),
	(   shared_variables(Goal, Params)
	->  consistent_params(Spec, Params),
	    Loop = ((Params,Spec) do PredTemplate)
	;   consistent_params(Spec, param()),
	    Loop = Goal
	),
	copy_term_nat(Loop, Copy),
	variant_sha1(Copy, Name),
	t_do(Loop, Name, NewGoal, Clauses),
	(   functor(NewGoal, Name, Arity),
	    current_predicate(Name/Arity)
	->  true
	;   compile_aux_clauses(Clauses)
	).

%%	consistent_params(+Spec, +ImplicitParms) is det.
%
%	Test that the  declared  parameters   are  consistent  with  the
%	implicit parameters. The declaration is considered consistent if
%	it is missing or it is   consistent with the implicitly computed
%	parameters.

consistent_params(Spec, SharedT) :-
	compound_name_arguments(SharedT, _, Shared),
	phrase(spec_params(Spec), Params0),
	sort(Params0, Params),
	(   Params == Shared
	->  true
	;   Params == []
	->  true
	;   ord_subtract(Shared, Params, NotDecl),
	    ord_subtract(Params, Shared, NotShared),
	    print_message(warning, loop(wrong_param_decl(NotDecl, NotShared)))
	).

spec_params(Var) -->
	{ var(Var), !,
	  instantiation_error(Var)
	}.
spec_params((A,B)) -->
	spec_params(A),
	spec_params(B).
spec_params(Param) -->
	{ Param =.. [param|Parms] }, !,
	list(Parms).
spec_params(_) -->
	[].

list([]) --> [].
list([H|T]) --> [H], list(T).


%%	shared_variables(+Goal, -Params) is semidet.
%
%	True when Params is a term param(Param1, ...), where Param1, ...
%	are variables shared with the remainder of the clause.

shared_variables(Goal, Params) :-
	prolog_load_context(term, Clause),
	copy_term_except(Goal, Clause, Clause2),
	term_variables(Clause2, EnvVars),
	term_variables(Goal, TemplateVars),
	sort(EnvVars, EnvVarsS),
	sort(TemplateVars, TemplateVarsS),
	ord_intersection(EnvVarsS, TemplateVarsS, Shared),
	Shared \== [],
	Params =.. [param|Shared].

copy_term_except(Except, Term, Copy) :-
	==(Term, Except), !,
	Copy = [].
copy_term_except(Except, Term, Copy) :-
	compound(Term), !,
	compound_name_arguments(Term, Name, Args0),
	maplist(copy_term_except(Except), Args0, Args),
	compound_name_arguments(Copy, Name, Args).
copy_term_except(_, Term, Term).


		 /*******************************
		 *	      MESSAGES		*
		 *******************************/

:- multifile
	prolog:message//1.

prolog:message(loop(wrong_param_decl(NotDecl, NotShared))) -->
	[ 'do/2: inconsistent parameter declaration'-[], nl ],
	not_declared(NotDecl),
	not_shared(NotShared).

not_declared([]) --> [].
not_declared(Vars) -->
	[ '\tShared but not declared: '-[] ], vars(Vars).

not_shared([]) --> [].
not_shared(Vars) -->
	[ '\tDeclared but not shared: '-[] ], vars(Vars).

vars([]) --> [].
vars([H|T]) -->
	var(H),
	(   {T==[]}
	->  []
	;   {T=[Last]}
	->  [' and '-[] ],
	    var(Last)
	;   [', '-[]],
	    vars(T)
	).

var(H) -->
	{ prolog_load_context(variable_names, Names),
	  member(Name=Var, Names),
	  Var == H, !
	},
	[ '~w'-[Name] ].
var(H) -->
	[ '~p'-[H] ].
