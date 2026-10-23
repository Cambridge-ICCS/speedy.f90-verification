/-!
# SPEEDY vertical diffusion and shallow convection

A transcription of `get_vertical_diffusion_tend` from `source/vertical_diffusion.f90`.

The scheme is written once, generically over a scalar type `α`. It is executed at
`α = Float` (exported to C and linked into SPEEDY in place of the Fortran routine), and
reasoned about at `α = ℝ` in `SpeedyProofs.VerticalDiffusion`.

To reproduce the Fortran bit-for-bit, every floating-point operation below is performed in
the same order, with the same association, as in the Fortran source (compiled with strict
IEEE semantics, see `source/gfortran.makefile`). Comments give the Fortran each line mirrors.

Indexing: Fortran levels `k = 1..kx` (top to bottom) become `0..n-1` here. Fortran's
half-level array `sigh(0:kx)` keeps its indices, so the bottom of level `j` is `sigh[j+1]`.
-/

namespace Speedy.VerticalDiffusion

/-- Scheme constants (the `parameter`s at the top of the Fortran module). -/
structure Params (α : Type) where
  /-- Relaxation time (hours) for shallow convection. -/
  trshc : α
  /-- Relaxation time (hours) for moisture diffusion. -/
  trvdi : α
  /-- Relaxation time (hours) for super-adiabatic conditions. -/
  trvds : α
  /-- Reduction factor of shallow convection in areas of deep convection. -/
  redshc : α
  /-- Maximum gradient of relative humidity (d_RH/d_sigma). -/
  rhgrad : α
  /-- Minimum gradient of dry static energy (d_DSE/d_phi). -/
  segrad : α

/-- Vertical grid and physical constants, supplied by SPEEDY's `geometry` and
`physical_constants` modules. -/
structure Grid (α : Type) (n : Nat) where
  /-- Full sigma levels. -/
  fsg : Vector α n
  /-- Sigma level thicknesses. -/
  dhs : Vector α n
  /-- Half-level sigma, `sigh(0:kx)`. -/
  sigh : Vector α (n + 1)
  /-- Specific heat at constant pressure. -/
  cp : α
  /-- Latent heat of condensation. -/
  alhc : α

/-- Column-independent coefficients, computed once per call (section 1 of the Fortran). -/
structure Coeffs (α : Type) (n : Nat) where
  fshcq : α
  fshcse : α
  fvdiq : α
  fvdise : α
  /-- `1 / dhs(k)`. -/
  rsig : Vector α n
  /-- `1 / (1 - sigh(k))`, used for levels `0..n-2`. -/
  rsig1 : Vector α n

/-- The fields of one atmospheric column that the scheme reads. -/
structure Column (α : Type) (n : Nat) where
  /-- Dry static energy. -/
  se : Vector α n
  /-- Relative humidity. -/
  rh : Vector α n
  /-- Specific humidity. -/
  qa : Vector α n
  /-- Saturation specific humidity. -/
  qsat : Vector α n
  /-- Geopotential. -/
  phi : Vector α n
  /-- Whether deep convection is active (`icnv(i,j) > 0`). -/
  deep : Bool

variable {α : Type} {n : Nat}

/-- Read level `i`, or `0` if out of range (never happens for `n ≥ 2`). -/
@[inline] def get [OfNat α 0] (v : Vector α n) (i : Nat) : α :=
  if h : i < n then v[i] else 0

/-- Apply `f` to level `i`, if it is in range. -/
@[inline] def modify (v : Vector α n) (i : Nat) (f : α → α) : Vector α n :=
  if h : i < n then v.set i (f v[i]) else v

section Scheme

variable [Add α] [Sub α] [Mul α] [Div α] [Neg α] [LT α] [LE α]
  [DecidableRel (α := α) (· < ·)] [DecidableRel (α := α) (· ≤ ·)]
  [OfNat α 0] [OfNat α 1] [NatCast α]

/-- Section 1 of the Fortran: column-independent coefficients. -/
def coeffs (p : Params α) (g : Grid α n) : Coeffs α n :=
  let nl1 := n - 1   -- Fortran `nl1 = kx - 1` (as a Fortran index, i.e. 1-based)
  -- cshc = dhs(kx)/3600.0
  let cshc := get g.dhs (n - 1) / (3600 : Nat)
  -- cvdi = (sigh(nl1) - sigh(1))/((nl1 - 1)*3600.0)
  let cvdi := (get g.sigh nl1 - get g.sigh 1) / (((nl1 - 1 : Nat) : α) * ((3600 : Nat) : α))
  { fshcq  := cshc / p.trshc                   -- fshcq  = cshc/trshc
    fshcse := cshc / (p.trshc * g.cp)          -- fshcse = cshc/(trshc*cp)
    fvdiq  := cvdi / p.trvdi                   -- fvdiq  = cvdi/trvdi
    fvdise := cvdi / (p.trvds * g.cp)          -- fvdise = cvdi/(trvds*cp)
    rsig   := Vector.ofFn fun k ↦ 1 / g.dhs[k]                      -- rsig(k) = 1.0/dhs(k)
    rsig1  := Vector.ofFn fun k ↦ 1 / (1 - get g.sigh (k.val + 1)) } -- rsig1(k) = 1.0/(1.0 - sigh(k))

/-- Section 2: shallow convection between the lowest two levels `a = n-2` and `b = n-1`.
Starts from zero tendencies, so it assigns rather than accumulates (as the Fortran does). -/
def shallowConvection (p : Params α) (g : Grid α n) (c : Coeffs α n) (x : Column α n)
    (t q : Vector α n) : Vector α n × Vector α n :=
  let a := n - 2
  let b := n - 1
  -- drh0 = rhgrad*(fsg(kx) - fsg(nl1)); fvdiq2 = fvdiq*sigh(nl1)
  let drh0 := p.rhgrad * (get g.fsg b - get g.fsg a)
  let fvdiq2 := c.fvdiq * get g.sigh (n - 1)
  -- dmse = se(kx) - se(nl1) + alhc*(qa(kx) - qsat(nl1)); drh = rh(kx) - rh(nl1)
  let dmse := get x.se b - get x.se a + g.alhc * (get x.qa b - get x.qsat a)
  let drh := get x.rh b - get x.rh a
  if 0 ≤ dmse then
    let fcnv : α := if x.deep then p.redshc else 1
    let fluxse := fcnv * c.fshcse * dmse
    let t := modify (modify t a fun _ ↦ fluxse * get c.rsig a) b fun _ ↦ -(fluxse * get c.rsig b)
    if 0 ≤ drh then
      let fluxq := fcnv * c.fshcq * get x.qsat b * drh
      (t, modify (modify q a fun _ ↦ fluxq * get c.rsig a) b fun _ ↦ -(fluxq * get c.rsig b))
    else (t, q)
  else if drh0 < drh then
    let fluxq := fvdiq2 * get x.qsat a * drh
    (t, modify (modify q a fun _ ↦ fluxq * get c.rsig a) b fun _ ↦ -(fluxq * get c.rsig b))
  else (t, q)

/-- One level of section 3: moisture diffusion between levels `j` and `j+1`
(Fortran `k = j+1`, run for `k = 3..kx-2`). -/
def moistureDiffusionStep (p : Params α) (g : Grid α n) (c : Coeffs α n) (x : Column α n)
    (q : Vector α n) (j : Nat) : Vector α n :=
  -- if (sigh(k) > 0.5)
  if (1 : α) / (1 + 1) < get g.sigh (j + 1) then
    let drh0 := p.rhgrad * (get g.fsg (j + 1) - get g.fsg j)
    let fvdiq2 := c.fvdiq * get g.sigh (j + 1)
    let drh := get x.rh (j + 1) - get x.rh j
    if drh0 ≤ drh then
      let fluxq := fvdiq2 * get x.qsat j * drh
      modify (modify q j fun v ↦ v + fluxq * get c.rsig j) (j + 1) fun v ↦ v - fluxq * get c.rsig (j + 1)
    else q
  else q

/-- Section 3: vertical diffusion of moisture above the PBL, Fortran `k = 3..kx-2`. -/
def moistureDiffusion (p : Params α) (g : Grid α n) (c : Coeffs α n) (x : Column α n)
    (q : Vector α n) : Vector α n :=
  (List.range' 2 (n - 4)).foldl (moistureDiffusionStep p g c x) q

/-- Subtract `d` from every level `j+1..n-1`. -/
def subBelow (t : Vector α n) (j : Nat) (d : α) : Vector α n :=
  (List.range' (j + 1) (n - (j + 1))).foldl (fun t m ↦ modify t m fun v ↦ v - d) t

/-- One level of section 4: damping of a super-adiabatic lapse rate at level `j`
(Fortran `k = j+1`). Heat added at level `j` is removed evenly from all levels below. -/
def superAdiabaticStep (p : Params α) (c : Coeffs α n) (x : Column α n)
    (t : Vector α n) (j : Nat) : Vector α n :=
  -- se0 = se(k+1) + segrad*(phi(k) - phi(k+1))
  let se0 := get x.se (j + 1) + p.segrad * (get x.phi j - get x.phi (j + 1))
  if get x.se j < se0 then
    let fluxse := c.fvdise * (se0 - get x.se j)
    let t := modify t j fun v ↦ v + fluxse * get c.rsig j
    subBelow t j (fluxse * get c.rsig1 j)
  else t

/-- Section 4: damping of super-adiabatic lapse rate, Fortran `k = 1..nl1`. -/
def superAdiabatic (p : Params α) (c : Coeffs α n) (x : Column α n)
    (t : Vector α n) : Vector α n :=
  (List.range (n - 1)).foldl (superAdiabaticStep p c x) t

/-- Temperature and specific-humidity tendencies for one column. (The u and v tendencies of
this scheme are identically zero.) -/
def column (p : Params α) (g : Grid α n) (c : Coeffs α n) (x : Column α n) :
    Vector α n × Vector α n :=
  let zero := Vector.replicate n 0
  let (t, q) := shallowConvection p g c x zero zero
  let q := moistureDiffusion p g c x q
  let t := superAdiabatic p c x t
  (t, q)

end Scheme

/-! ## Executable instance at `Float` -/

instance : NatCast Float := ⟨Float.ofNat⟩

/-- SPEEDY's values of the scheme constants. These are default-real (single precision)
literals in the Fortran, widened to double; `0.1` is not exact, hence the `Float32`. -/
def speedyParams : Params Float where
  trshc  := 6
  trvdi  := 24
  trvds  := 6
  redshc := (0.5 : Float32).toFloat
  rhgrad := (0.5 : Float32).toFloat
  segrad := (0.1 : Float32).toFloat

/-- Run the scheme over a whole field of `ncol` columns with `n` levels, in Fortran
(column-major) layout: level `k` of column `i` is at `i + ncol * k`. `icnv` holds the deep
convection index as a float. Returns the temperature tendencies followed by the
specific-humidity tendencies, in the same layout. -/
def field (ncol n : Nat) (cp alhc : Float) (fsg dhs sigh : FloatArray)
    (se rh qa qsat phi icnv : FloatArray) : FloatArray := Id.run do
  let g : Grid Float n :=
    { fsg := Vector.ofFn fun k ↦ fsg[k.val]!, dhs := Vector.ofFn fun k ↦ dhs[k.val]!,
      sigh := Vector.ofFn fun k ↦ sigh[k.val]!, cp, alhc }
  let c := coeffs speedyParams g
  let mut out := FloatArray.mk (Array.replicate (2 * ncol * n) 0)
  for i in [0:ncol] do
    let col (f : FloatArray) : Vector Float n := Vector.ofFn fun k ↦ f[i + ncol * k.val]!
    let x : Column Float n :=
      { se := col se, rh := col rh, qa := col qa, qsat := col qsat, phi := col phi,
        deep := icnv[i]! > 0 }
    let (t, q) := column speedyParams g c x
    for h : k in [0:n] do
      out := out.set! (i + ncol * k) t[k]
      out := out.set! (ncol * n + i + ncol * k) q[k]
  return out

@[export speedy_vertical_diffusion]
def fieldExport (ncol n : USize) (cp alhc : Float) (fsg dhs sigh : FloatArray)
    (se rh qa qsat phi icnv : FloatArray) : FloatArray :=
  field ncol.toNat n.toNat cp alhc fsg dhs sigh se rh qa qsat phi icnv

end Speedy.VerticalDiffusion
