% ----------------------------------------------------------------------
% Wrapper for SWI Prolog
% ----------------------------------------------------------------------

:- [loops].

goal_expansion(Goal, NewGoal) :-
	Goal = (_ do _),
	aux_pred_name(Name),
	t_do(Goal, Name, NewGoal, [Clause1,Clause2]),
	assert(Clause1),
	assert(Clause2).

:- assert(name_ctr(0)).

aux_pred_name(Name) :-
	retract(name_ctr(I)),
	I1 is I+1,
	assert(name_ctr(I1)),
	number_codes(I, IC),
	atom_codes(IA, IC),
	atom_concat(do__, IA, Name).


