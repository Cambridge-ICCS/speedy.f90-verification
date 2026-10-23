import Mathlib
import SpeedyKernel.VerticalDiffusion

/-!
# Conservation properties of SPEEDY's vertical diffusion scheme

We prove that the vertical diffusion and shallow convection scheme
(`Speedy.VerticalDiffusion.column`, the same definition that is compiled and linked into
SPEEDY) conserves column-integrated dry static energy and moisture: the mass-weighted
column sums of its temperature and humidity tendencies are both zero. The scheme only
redistributes heat and moisture between levels.

The proofs are about the real-number semantics of the scheme (`α = ℝ`). They hold for
every value of the scheme's tuning constants and for any column state, assuming only a
well-formed vertical grid. They say nothing about floating-point rounding error.
-/

namespace Speedy.VerticalDiffusion

open Finset

variable {n : Nat}

/-- Mass-weighted column integral `∑ₖ Δσₖ vₖ`. Multiplied by `p_s / g` (and `c_p` for
temperature) this is the column-integrated energy or moisture change. -/
noncomputable def colSum (dhs v : Vector ℝ n) : ℝ :=
  ∑ k ∈ range n, get dhs k * get v k

/-- A well-formed vertical grid: layers have positive thickness and tile the column, from
`sigh[0]` at the top down to `sigh[n] = 1` at the surface. -/
structure Grid.WellFormed (g : Grid ℝ n) : Prop where
  dhs_pos : ∀ k < n, 0 < get g.dhs k
  dhs_eq : ∀ k < n, get g.dhs k = get g.sigh (k + 1) - get g.sigh k
  sigh_bottom : get g.sigh n = 1

/-- The coefficients the conservation argument depends on: the reciprocal layer thicknesses
and the reciprocal depth below each half level. -/
structure Coeffs.Valid (g : Grid ℝ n) (c : Coeffs ℝ n) : Prop where
  rsig : ∀ k < n, get c.rsig k = 1 / get g.dhs k
  rsig1 : ∀ k < n, get c.rsig1 k = 1 / (1 - get g.sigh (k + 1))

/-! ### Reading and updating levels -/

theorem get_modify (v : Vector ℝ n) {i : Nat} (hi : i < n) (f : ℝ → ℝ) (k : Nat) :
    get (modify v i f) k = if k = i then f (get v i) else get v k := by
  unfold get modify
  by_cases hk : k < n
  · simp only [hi, hk, dite_true, Vector.getElem_set]
    by_cases h : k = i
    · subst h; simp
    · simp [h, Ne.symm h]
  · have : k ≠ i := by omega
    simp [hk, this]

theorem get_modify_ne (v : Vector ℝ n) {i : Nat} (hi : i < n) (f : ℝ → ℝ) {k : Nat} (h : k ≠ i) :
    get (modify v i f) k = get v k := by
  simp [get_modify v hi, h]

theorem colSum_modify (d v : Vector ℝ n) {i : Nat} (hi : i < n) (f : ℝ → ℝ) :
    colSum d (modify v i f) = colSum d v + get d i * (f (get v i) - get v i) := by
  unfold colSum
  have : ∀ k ∈ range n, get d k * get (modify v i f) k =
      get d k * get v k + if k = i then get d i * (f (get v i) - get v i) else 0 := by
    intro k _
    rw [get_modify v hi]
    split_ifs with h
    · subst h; ring
    · ring
  rw [sum_congr rfl this, sum_add_distrib, sum_ite_eq' (range n) i]
  simp [hi]

theorem colSum_replicate_zero (d : Vector ℝ n) : colSum d (Vector.replicate n 0) = 0 := by
  unfold colSum get
  apply sum_eq_zero
  intro k hk
  simp only [mem_range.1 hk, dite_true, Vector.getElem_replicate, mul_zero]

/-- A fold whose every step preserves `F` preserves `F`. -/
theorem foldl_preserves {β γ : Type} (F : β → ℝ) (f : β → γ → β) (l : List γ)
    (P : γ → Prop) (hl : ∀ x ∈ l, P x) (hf : ∀ b x, P x → F (f b x) = F b) (b : β) :
    F (l.foldl f b) = F b := by
  induction l generalizing b with
  | nil => rfl
  | cons x xs ih =>
    rw [List.foldl_cons, ih (fun y hy ↦ hl y (List.mem_cons_of_mem x hy)), hf b x (hl x (by simp))]

/-! ### Grid facts -/

/-- `Δσₖ · (1/Δσₖ) = 1`: a flux divided by a layer thickness, integrated over that layer,
gives the flux back. -/
theorem dhs_mul_rsig {g : Grid ℝ n} {c : Coeffs ℝ n} (hg : g.WellFormed) (hc : c.Valid g)
    {k : Nat} (hk : k < n) (F : ℝ) : get g.dhs k * (F * get c.rsig k) = F := by
  rw [hc.rsig k hk]
  have := (hg.dhs_pos k hk).ne'
  field_simp

/-- The layers `s, …, s+m-1` have total thickness `sigh[s+m] - sigh[s]` (telescoping). -/
theorem sum_dhs_range' {g : Grid ℝ n} (hg : g.WellFormed) (s m : Nat) (h : s + m ≤ n) :
    ((List.range' s m).map (get g.dhs)).sum = get g.sigh (s + m) - get g.sigh s := by
  induction m generalizing s with
  | zero => simp
  | succ m ih =>
    rw [List.range'_succ, List.map_cons, List.sum_cons, ih (s + 1) (by omega),
      hg.dhs_eq s (by omega)]
    rw [show s + 1 + m = s + (m + 1) by omega]
    ring

/-- Everything below half level `j+1` has positive thickness, so `1 - sigh[j+1] > 0`. -/
theorem one_sub_sigh_pos {g : Grid ℝ n} (hg : g.WellFormed) {j : Nat} (hj : j + 1 < n) :
    0 < 1 - get g.sigh (j + 1) := by
  have hsum := sum_dhs_range' hg (j + 1) (n - (j + 1)) (by omega)
  rw [show j + 1 + (n - (j + 1)) = n by omega, hg.sigh_bottom] at hsum
  rw [← hsum]
  apply List.sum_pos
  · intro x hx
    obtain ⟨m, hm, rfl⟩ := List.mem_map.1 hx
    exact hg.dhs_pos m (by simp [List.mem_range'] at hm; omega)
  · simp; omega

/-! ### Section 2: shallow convection -/

/-- Setting the top level of a pair to `F/Δσ_a` and the bottom to `-F/Δσ_b`, starting from
zero, gives zero column sum. -/
theorem colSum_pair {g : Grid ℝ n} {c : Coeffs ℝ n} (hg : g.WellFormed) (hc : c.Valid g)
    (hn : 2 ≤ n) (F : ℝ) :
    colSum g.dhs (modify (modify (Vector.replicate n 0) (n - 2) fun _ ↦ F * get c.rsig (n - 2))
      (n - 1) fun _ ↦ -(F * get c.rsig (n - 1))) = 0 := by
  rw [colSum_modify _ _ (by omega), colSum_modify _ _ (by omega), colSum_replicate_zero,
    get_modify_ne _ (by omega) _ (by omega)]
  have h0 : ∀ k, get (Vector.replicate n (0 : ℝ)) k = 0 := fun k ↦ by
    unfold get; split_ifs <;> simp
  rw [h0, h0]
  have ha := dhs_mul_rsig hg hc (show n - 2 < n by omega) F
  have hb := dhs_mul_rsig hg hc (show n - 1 < n by omega) F
  linear_combination ha - hb

theorem shallowConvection_conserves (p : Params ℝ) {g : Grid ℝ n} {c : Coeffs ℝ n}
    (hg : g.WellFormed) (hc : c.Valid g) (hn : 2 ≤ n) (x : Column ℝ n) :
    let r := shallowConvection p g c x (Vector.replicate n 0) (Vector.replicate n 0)
    colSum g.dhs r.1 = 0 ∧ colSum g.dhs r.2 = 0 := by
  simp only [shallowConvection]
  split_ifs <;> simp only [colSum_pair hg hc hn, colSum_replicate_zero, and_self]

/-! ### Section 3: moisture diffusion above the boundary layer -/

theorem moistureDiffusionStep_conserves (p : Params ℝ) {g : Grid ℝ n} {c : Coeffs ℝ n}
    (hg : g.WellFormed) (hc : c.Valid g) (x : Column ℝ n) (q : Vector ℝ n) {j : Nat}
    (hj : j + 1 < n) :
    colSum g.dhs (moistureDiffusionStep p g c x q j) = colSum g.dhs q := by
  unfold moistureDiffusionStep
  dsimp only
  split_ifs
  · rw [colSum_modify _ _ (by omega), colSum_modify _ _ (by omega),
      get_modify_ne _ (by omega) _ (by omega)]
    set F := (c.fvdiq * get g.sigh (j + 1)) * get x.qsat j * (get x.rh (j + 1) - get x.rh j)
    have ha := dhs_mul_rsig hg hc (show j < n by omega) F
    have hb := dhs_mul_rsig hg hc hj F
    linear_combination ha - hb
  all_goals rfl

theorem moistureDiffusion_conserves (p : Params ℝ) {g : Grid ℝ n} {c : Coeffs ℝ n}
    (hg : g.WellFormed) (hc : c.Valid g) (x : Column ℝ n) (q : Vector ℝ n) :
    colSum g.dhs (moistureDiffusion p g c x q) = colSum g.dhs q :=
  foldl_preserves (colSum g.dhs) _ _ (fun j ↦ j + 1 < n)
    (fun j hj ↦ by simp [List.mem_range'] at hj; omega)
    (fun q _ hj ↦ moistureDiffusionStep_conserves p hg hc x q hj) q

/-! ### Section 4: damping of super-adiabatic lapse rates -/

theorem colSum_subBelow (d t : Vector ℝ n) (j : Nat) (D : ℝ) :
    colSum d (subBelow t j D) =
      colSum d t - D * ((List.range' (j + 1) (n - (j + 1))).map (get d)).sum := by
  unfold subBelow
  have key : ∀ (l : List Nat), (∀ m ∈ l, m < n) → ∀ t : Vector ℝ n,
      colSum d (l.foldl (fun t m ↦ modify t m fun v ↦ v - D) t) =
        colSum d t - D * (l.map (get d)).sum := by
    intro l
    induction l with
    | nil => simp
    | cons m ms ih =>
      intro hl t
      rw [List.foldl_cons, ih (fun y hy ↦ hl y (List.mem_cons_of_mem m hy)),
        colSum_modify _ _ (hl m (by simp))]
      simp only [List.map_cons, List.sum_cons]
      ring
  exact key _ (fun m hm ↦ by simp [List.mem_range'] at hm; omega) t

theorem superAdiabaticStep_conserves (p : Params ℝ) {g : Grid ℝ n} {c : Coeffs ℝ n}
    (hg : g.WellFormed) (hc : c.Valid g) (x : Column ℝ n) (t : Vector ℝ n) {j : Nat}
    (hj : j + 1 < n) :
    colSum g.dhs (superAdiabaticStep p c x t j) = colSum g.dhs t := by
  unfold superAdiabaticStep
  dsimp only
  split_ifs
  · rw [colSum_subBelow, colSum_modify _ _ (by omega),
      sum_dhs_range' hg (j + 1) (n - (j + 1)) (by omega),
      show j + 1 + (n - (j + 1)) = n by omega, hg.sigh_bottom, hc.rsig1 j (by omega)]
    set F := c.fvdise * (get x.se (j + 1) + p.segrad * (get x.phi j - get x.phi (j + 1)) -
      get x.se j)
    have ha := dhs_mul_rsig hg hc (show j < n by omega) F
    have hpos := (one_sub_sigh_pos hg hj).ne'
    have hb : F * (1 / (1 - get g.sigh (j + 1))) * (1 - get g.sigh (j + 1)) = F := by
      field_simp
    linear_combination ha - hb
  · rfl

theorem superAdiabatic_conserves (p : Params ℝ) {g : Grid ℝ n} {c : Coeffs ℝ n}
    (hg : g.WellFormed) (hc : c.Valid g) (x : Column ℝ n) (t : Vector ℝ n) :
    colSum g.dhs (superAdiabatic p c x t) = colSum g.dhs t :=
  foldl_preserves (colSum g.dhs) _ _ (fun j ↦ j + 1 < n)
    (fun j hj ↦ by simp at hj; omega)
    (fun t _ hj ↦ superAdiabaticStep_conserves p hg hc x t hj) t

/-! ### The whole scheme -/

/-- **Conservation.** For any valid coefficients, the column tendencies of temperature
(dry static energy) and specific humidity both have zero mass-weighted column integral. -/
theorem column_conserves (p : Params ℝ) {g : Grid ℝ n} {c : Coeffs ℝ n}
    (hg : g.WellFormed) (hc : c.Valid g) (hn : 2 ≤ n) (x : Column ℝ n) :
    colSum g.dhs (column p g c x).1 = 0 ∧ colSum g.dhs (column p g c x).2 = 0 := by
  obtain ⟨ht, hq⟩ := shallowConvection_conserves p hg hc hn x
  unfold column
  exact ⟨by rw [superAdiabatic_conserves p hg hc]; exact ht,
    by rw [moistureDiffusion_conserves p hg hc]; exact hq⟩

/-- The coefficients computed by the scheme (`coeffs`) are valid on a well-formed grid. -/
theorem coeffs_valid (p : Params ℝ) (g : Grid ℝ n) : (coeffs p g).Valid g where
  rsig k hk := by simp [coeffs, get, hk]
  rsig1 k hk := by simp [coeffs, get, hk]

/-- **Conservation, end to end.** The scheme as run by SPEEDY (coefficients computed by
`coeffs`) conserves column-integrated dry static energy and moisture, for every value of
the scheme's constants and every column state, on any well-formed grid with at least two
levels. -/
theorem scheme_conserves (p : Params ℝ) {g : Grid ℝ n} (hg : g.WellFormed) (hn : 2 ≤ n)
    (x : Column ℝ n) :
    colSum g.dhs (column p g (coeffs p g) x).1 = 0 ∧
      colSum g.dhs (column p g (coeffs p g) x).2 = 0 :=
  column_conserves p hg (coeffs_valid p g) hn x

end Speedy.VerticalDiffusion
