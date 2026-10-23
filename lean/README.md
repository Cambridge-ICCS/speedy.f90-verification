# Verified kernels for SPEEDY

A proof of concept: a component of SPEEDY rewritten in Lean 4, with properties proved
about it, compiled to C and linked back into the Fortran model in place of the original.

The component is vertical diffusion and shallow convection
(`get_vertical_diffusion_tend` in `source/vertical_diffusion.f90`).

## Layout

| Path | What |
|------|------|
| `SpeedyKernel/VerticalDiffusion.lean` | The scheme, written once over a generic scalar type, plus a `Float` entry point exported to C. Imports only Lean core. |
| `SpeedyProofs/VerticalDiffusion.lean` | Proofs about the same definitions at `ℝ`, using Mathlib. Never linked into SPEEDY. |
| `../source/lean/vertical_diffusion.f90` | Drop-in Fortran module that calls the Lean kernel. |
| `../source/lean/vertical_diffusion_shim.c` | C glue: Lean runtime start-up, array copies. |

## What is proved

`scheme_conserves`: for every column state and every value of the scheme's tuning
constants, on any well-formed vertical grid (positive layer thicknesses that tile the
column down to σ = 1) with at least two levels, the scheme's temperature and humidity
tendencies have zero mass-weighted column integral:

    Σₖ Δσₖ · ttendₖ = 0    and    Σₖ Δσₖ · qtendₖ = 0

The scheme only moves dry static energy and moisture between levels. It never creates or
destroys them. The proof uses only the standard axioms (`propext`, `Classical.choice`,
`Quot.sound`).

## What is not proved (the trust base)

- **Rounding.** The theorem is about real-number arithmetic. The executed code uses IEEE
  doubles, so in the model the column sums are zero only up to rounding.
- **That the Lean matches the Fortran.** This is tested, not proved. The kernel performs
  the Fortran's floating-point operations in the same order. The shadow check (below)
  confirms bit-identical results on every call over a 10-day run.
- **Glue.** The `field` loop (extracting columns from Fortran-ordered arrays), the C shim
  and the Fortran wrapper are not verified.

## Building and checking

    lake build                              # check the proofs (first: lake exe cache get)
    ../build.sh --lean                      # build SPEEDY with the Lean kernel
    ../build.sh --lean --shadow             # ... plus the bitwise shadow check
    ../scripts/check_golden.sh --lean       # build (with shadow check), run, compare
    ../scripts/benchmark.py                 # time the Fortran and Lean builds

The Fortran module being replaced is compiled with strict IEEE semantics
(`-O2 -ffp-contract=off`, see `source/gfortran.makefile`), as is the generated C. This is
what makes bit-for-bit agreement possible. `golden/reference` is produced from that build
by `scripts/make_golden.sh`.

The shadow check (`--shadow`, which `check_golden.sh --lean` uses) links the original
Fortran routine into the Lean build. Every call to the Lean kernel also runs the Fortran,
and the run stops on the first differing bit. The golden comparison alone is not enough:
the outputs are float32, so a one-ulp difference in a double inside the kernel can vanish
from them. Without `--shadow` the Lean build contains no Fortran version of the routine,
so its timings are a fair comparison.

## Performance

`scripts/benchmark.py` builds both variants and runs each several times, interleaved, with
model output switched off. It reports whole-process time, main-loop time, and time inside
the vertical diffusion routine, taken from timers in `source/timing.f90` that are identical
in both builds. On an Apple Silicon Mac (10 simulated days, 5 reps):

| | Fortran | Lean | Lean / Fortran |
|---|---|---|---|
| whole process | 2.29 s | 4.01 s | 1.75× |
| vertical diffusion (362 calls) | 0.036 s | 1.78 s | 49.5× |

The Lean kernel is not yet optimised. It builds boxed-`Float` vectors for every column, and
its loops allocate lists and closures.
