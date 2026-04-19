-module(picosat_nif).
-on_load(init/0).

-export([solve/1]).

init() ->
    PrivDir = code:priv_dir(picosat_elixir),
    Path = filename:join(PrivDir, "picosat_nif"),
    ok = erlang:load_nif(Path, 0).


solve(_) ->
    erlang:nif_error(not_loaded).
