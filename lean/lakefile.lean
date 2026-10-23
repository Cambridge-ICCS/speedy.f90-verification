import Lake
open Lake DSL

package speedy_lean where
  leanOptions := #[⟨`autoImplicit, false⟩]

require mathlib from git
  "https://github.com/leanprover-community/mathlib4" @ "v4.34.1"

/-- Executable kernels. Imports only Lean core so that the generated C can be
linked into SPEEDY without pulling in Mathlib. -/
lean_lib SpeedyKernel

/-- Proofs about the kernels, over ℝ, using Mathlib. Never linked into SPEEDY. -/
@[default_target]
lean_lib SpeedyProofs
