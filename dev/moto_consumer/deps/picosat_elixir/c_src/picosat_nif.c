#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>

#include "erl_nif.h"

#include "picosat.h"

static ERL_NIF_TERM solve_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  unsigned list_length, list_length2;
  ERL_NIF_TERM head, tail, head2, tail2;

  enif_get_list_length(env, argv[0], &list_length);

  PicoSAT *sat = picosat_init();

  tail = argv[0];
  while(enif_get_list_cell(env, tail, &head, &tail) != 0) {
    tail2 = head;
    enif_get_list_length(env, tail2, &list_length2);

    while(enif_get_list_cell(env, tail2, &head2, &tail2) != 0) {
      int x;

      if (!enif_get_int(env, head2, &x)) {
        return enif_make_badarg(env);
      }

      picosat_add(sat, x);
    }

    picosat_add(sat, 0);
  }

  int res = picosat_sat(sat, -1);
  if (res == PICOSAT_UNSATISFIABLE) {
    picosat_reset(sat);
    return enif_make_atom(env, "unsatisfiable");
  } else if (res == PICOSAT_UNKNOWN) {
    picosat_reset(sat);
    return enif_make_atom(env, "unknown");
  } else if (res == PICOSAT_SATISFIABLE) {
    unsigned int vars = picosat_variables(sat);
    ERL_NIF_TERM *solution = malloc(vars * sizeof(ERL_NIF_TERM));

    for(int i=1;i<=vars;i++) {
      solution[i-1] = enif_make_int(env, i * picosat_deref(sat, i));
    }

    picosat_reset(sat);
    ERL_NIF_TERM ret = enif_make_list_from_array(env, solution, vars);
    free(solution);
    return ret;
  } else {
    picosat_reset(sat);
    return enif_make_atom(env, "picosat_error");
  }
}

static ErlNifFunc nif_funcs[] = {
  {"solve", 1, solve_nif}
};

ERL_NIF_INIT(picosat_nif, nif_funcs, NULL, NULL, NULL, NULL);
