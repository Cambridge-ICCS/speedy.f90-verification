!> Parametrization of vertical diffusion, computed by the Lean kernel in
!  lean/SpeedyKernel/VerticalDiffusion.lean (see lean/SpeedyProofs for its
!  verified properties).
!
! Drop-in replacement for source/vertical_diffusion.f90, used by `build.sh --lean`.
!
! Compiled with -DSHADOW_CHECK (`build.sh --lean --shadow`), every call also runs the
! original Fortran routine (built from source/vertical_diffusion.f90 as module
! vertical_diffusion_fortran) and stops the run if the results differ in any bit.
module vertical_diffusion
    use types, only: p
    use params
    use iso_c_binding, only: c_int, c_double

    implicit none

    private
    public get_vertical_diffusion_tend

#ifdef SHADOW_CHECK
    logical :: check_announced = .false.
    integer :: ncalls = 0
#endif

    interface
        subroutine speedy_vd_lean(ncol, nlev, cp, alhc, fsg, dhs, sigh, se, rh, qa, qsat, phi, &
            & icnv, ttend, qtend) bind(c, name="speedy_vd_lean")
            import c_int, c_double
            integer(c_int), value :: ncol, nlev
            real(c_double), value :: cp, alhc
            real(c_double), intent(in) :: fsg(*), dhs(*), sigh(*)
            real(c_double), intent(in) :: se(*), rh(*), qa(*), qsat(*), phi(*)
            integer(c_int), intent(in) :: icnv(*)
            real(c_double), intent(out) :: ttend(*), qtend(*)
        end subroutine
    end interface

contains
    !> Compute tendencies of momentum, energy and moisture due to vertical diffusion
    !  and shallow convection
    subroutine get_vertical_diffusion_tend(se, rh, qa, qsat, phi, icnv, utenvd, vtenvd, &
        & ttenvd, qtenvd)
        use physical_constants, only: cp, alhc, sigh
        use geometry, only: fsg, dhs

        real(p), intent(in)    :: se(ix,il,kx)     !! Dry static energy
        real(p), intent(in)    :: rh(ix,il,kx)     !! Relative humidity
        real(p), intent(in)    :: qa(ix,il,kx)     !! Specific humidity [g/kg]
        real(p), intent(in)    :: qsat(ix,il,kx)   !! Saturated specific humidity [g/kg]
        real(p), intent(in)    :: phi(ix,il,kx)    !! Geopotential
        integer, intent(in)    :: icnv(ix,il)      !! Sigma-level index of deep convection
        real(p), intent(out)   :: utenvd(ix,il,kx) !! u-wind tendency
        real(p), intent(out)   :: vtenvd(ix,il,kx) !! v-wind tendency
        real(p), intent(out)   :: ttenvd(ix,il,kx) !! Temperature tendency
        real(p), intent(out)   :: qtenvd(ix,il,kx) !! Specific humidity tendency

        utenvd = 0.0
        vtenvd = 0.0

        call speedy_vd_lean(ix*il, kx, cp, alhc, fsg, dhs, sigh, se, rh, qa, qsat, phi, icnv, &
            & ttenvd, qtenvd)

#ifdef SHADOW_CHECK
        if (.not. check_announced) then
            write (*,'(A)') "Lean vertical diffusion: shadow-checking against Fortran (bitwise)"
            check_announced = .true.
        end if
        call check_against_fortran(se, rh, qa, qsat, phi, icnv, ttenvd, qtenvd)
#endif
    end

#ifdef SHADOW_CHECK

    subroutine check_against_fortran(se, rh, qa, qsat, phi, icnv, ttenvd, qtenvd)
        use iso_fortran_env, only: int64
        use vertical_diffusion_fortran, only: fortran_tend => get_vertical_diffusion_tend

        real(p), intent(in) :: se(ix,il,kx), rh(ix,il,kx), qa(ix,il,kx), qsat(ix,il,kx)
        real(p), intent(in) :: phi(ix,il,kx), ttenvd(ix,il,kx), qtenvd(ix,il,kx)
        integer, intent(in) :: icnv(ix,il)
        real(p), dimension(ix,il,kx) :: uref, vref, tref, qref

        ncalls = ncalls + 1
        call fortran_tend(se, rh, qa, qsat, phi, icnv, uref, vref, tref, qref)
        call compare("ttenvd", ttenvd, tref)
        call compare("qtenvd", qtenvd, qref)
    end subroutine

    subroutine compare(name, lean, ref)
        use iso_fortran_env, only: int64

        character(len=*), intent(in) :: name
        real(p), intent(in) :: lean(ix,il,kx), ref(ix,il,kx)
        integer :: i, j, k

        do k = 1, kx
            do j = 1, il
                do i = 1, ix
                    if (transfer(lean(i,j,k), 0_int64) /= transfer(ref(i,j,k), 0_int64)) then
                        write (*,'(A,I0,A,3(I0,A))') "Lean vertical diffusion MISMATCH at call ", &
                            & ncalls, ": "//name//"(", i, ",", j, ",", k, ")"
                        write (*,'(A,ES25.17,A,Z16.16)') "  Lean:    ", lean(i,j,k), "  0x", &
                            & lean(i,j,k)
                        write (*,'(A,ES25.17,A,Z16.16)') "  Fortran: ", ref(i,j,k), "  0x", &
                            & ref(i,j,k)
                        flush (6)
                        error stop 1
                    end if
                end do
            end do
        end do
    end subroutine
#endif
end module
