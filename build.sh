#!/bin/bash

# Check that NetCDF variable is set
if [ -z "$NETCDF" ]; then
    echo "\$NETCDF variable not set"
    echo "Aborting build"
    exit 1
fi

# Name of makefile
MAKE=gfortran.makefile

# Define directory names
ROOT=`pwd`
SRC=$ROOT/source
BIN=$ROOT/bin

# Make binary directory
rm -rf $BIN
mkdir $BIN
cd $BIN

# Options:
#   --profile  gprof build
#   --lean     use the verified Lean kernels in place of the Fortran routines they replace
#   --shadow   (with --lean) also link the original Fortran routines and check, on every
#              call, that the Lean results are bit-identical; stops the run on a mismatch
TARGET=default
USE_LEAN=0
SHADOW=0
for arg in "$@"; do
    case "$arg" in
        --profile) TARGET=profile ;;
        --lean)    USE_LEAN=1 ;;
        --shadow)  SHADOW=1 ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done
if [ $SHADOW = 1 ] && [ $USE_LEAN = 0 ]; then
    echo "--shadow requires --lean"
    exit 1
fi

# Copy source files
cp $SRC/*.f90    .
cp $SRC/$MAKE .

EXTRA_OBJS=
EXTRA_LIBS=
SHADOW_OBJS=
VD_FPPFLAGS=
if [ $USE_LEAN = 1 ]; then
    # Build the Lean kernels, compile their generated C (and the C glue) with
    # Lean's C compiler, and swap in the Fortran wrappers that call them.
    LEAN_DIR=$ROOT/lean
    echo 'Compiling Lean kernels'
    (cd $LEAN_DIR && lake build SpeedyKernel) || { echo "Lean build failed"; exit 1; }
    LEAN_PREFIX=$(cd $LEAN_DIR && lean --print-prefix)
    # Only the kernel modules: the proofs (SpeedyProofs) depend on Mathlib and are never linked
    for c in $(cd $LEAN_DIR/.lake/build/ir && find . -path './SpeedyKernel*' -name '*.c'); do
        obj=lean_$(echo ${c#./} | tr / _ | sed 's/\.c$/.o/')
        (cd $LEAN_DIR && leanc -c -O3 -DNDEBUG .lake/build/ir/$c -o $BIN/$obj) \
            || { echo "Compiling $c failed"; exit 1; }
        EXTRA_OBJS="$EXTRA_OBJS $obj"
    done
    for c in $SRC/lean/*.c; do
        obj=$(basename ${c%.c}).o
        cc -c -O2 -ffp-contract=off -I$LEAN_PREFIX/include $c -o $BIN/$obj \
            || { echo "Compiling $c failed"; exit 1; }
        EXTRA_OBJS="$EXTRA_OBJS $obj"
    done
    cp $SRC/lean/*.f90 .
    VD_FPPFLAGS=-cpp
    if [ $SHADOW = 1 ]; then
        # Keep the original Fortran routine, renamed, for shadow checking
        sed 's/^module vertical_diffusion$/module vertical_diffusion_fortran/' \
            $SRC/vertical_diffusion.f90 > vertical_diffusion_fortran.f90
        SHADOW_OBJS=vertical_diffusion_fortran.o
        VD_FPPFLAGS="-cpp -DSHADOW_CHECK"
    fi
    EXTRA_LIBS="-L$LEAN_PREFIX/lib/lean -L$LEAN_PREFIX/lib -lInit -lleanrt -lgmp -luv -lc++"
fi

# Compile SPEEDY and delete source files
make -f $MAKE -s clean
echo 'Compiling SPEEDY'
make -f $MAKE -s FC="$FC" EXTRA_OBJS="$EXTRA_OBJS" EXTRA_LIBS="$EXTRA_LIBS" \
    SHADOW_OBJS="$SHADOW_OBJS" VD_FPPFLAGS="$VD_FPPFLAGS" $TARGET \
    || { echo "Compilation failed"; exit 1; }

rm -f *.f90 *.o $MAKE *.mod
