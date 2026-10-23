/* C glue between SPEEDY (Fortran) and the Lean vertical diffusion kernel
 * (lean/SpeedyKernel/VerticalDiffusion.lean).
 *
 * Copies the Fortran arrays into Lean FloatArrays, calls the exported Lean
 * function and copies the tendencies back. The Lean runtime is initialised on
 * the first call. */

#include <lean/lean.h>
#include <stdlib.h>
#include <string.h>

void lean_initialize_runtime_module(void);
lean_object *initialize_speedy__lean_SpeedyKernel(uint8_t builtin);
lean_object *speedy_vertical_diffusion(size_t ncol, size_t nlev, double cp, double alhc,
                                       lean_object *fsg, lean_object *dhs, lean_object *sigh,
                                       lean_object *se, lean_object *rh, lean_object *qa,
                                       lean_object *qsat, lean_object *phi, lean_object *icnv);

static void ensure_lean_initialized(void) {
    static int initialized = 0;
    if (initialized) return;
    lean_initialize_runtime_module();
    lean_object *res = initialize_speedy__lean_SpeedyKernel(1);
    if (!lean_io_result_is_ok(res)) {
        lean_io_result_show_error(res);
        abort();
    }
    lean_dec_ref(res);
    lean_io_mark_end_initialization();
    initialized = 1;
}

static lean_object *float_array(const double *src, size_t n) {
    lean_object *a = lean_alloc_sarray(sizeof(double), n, n);
    memcpy(lean_float_array_cptr(a), src, n * sizeof(double));
    return a;
}

/* Called from Fortran (bind(c)). Field arrays are (ix, il, nlev) in Fortran
 * order with ncol = ix*il; sigh has nlev+1 entries. */
void speedy_vd_lean(int ncol, int nlev, double cp, double alhc,
                    const double *fsg, const double *dhs, const double *sigh,
                    const double *se, const double *rh, const double *qa,
                    const double *qsat, const double *phi, const int *icnv,
                    double *ttend, double *qtend) {
    ensure_lean_initialized();

    size_t nf = (size_t)ncol * (size_t)nlev;

    lean_object *icnv_arr = lean_alloc_sarray(sizeof(double), ncol, ncol);
    double *icnv_f = lean_float_array_cptr(icnv_arr);
    for (int i = 0; i < ncol; i++) icnv_f[i] = (double)icnv[i];

    /* The exported function takes ownership of its arguments. */
    lean_object *out = speedy_vertical_diffusion(
        (size_t)ncol, (size_t)nlev, cp, alhc,
        float_array(fsg, nlev), float_array(dhs, nlev), float_array(sigh, nlev + 1),
        float_array(se, nf), float_array(rh, nf), float_array(qa, nf),
        float_array(qsat, nf), float_array(phi, nf), icnv_arr);

    const double *res = lean_float_array_cptr(out);
    memcpy(ttend, res, nf * sizeof(double));
    memcpy(qtend, res + nf, nf * sizeof(double));
    lean_dec_ref(out);
}
