!> Wall-clock timers, for comparing alternative implementations of model
!  components (e.g. the Fortran and Lean versions of vertical diffusion).
module timing
    use iso_fortran_env, only: int64

    implicit none

    private
    public timer_start, timer_stop, report_timers
    public timer_main_loop, timer_vertical_diffusion

    integer, parameter :: timer_main_loop = 1
    integer, parameter :: timer_vertical_diffusion = 2
    integer, parameter :: ntimers = 2

    character(len=20), parameter :: names(ntimers) = [character(len=20) :: &
        & "main loop", "vertical diffusion"]

    integer(int64) :: started(ntimers) = 0 !! Clock count when each timer was last started
    integer(int64) :: elapsed(ntimers) = 0 !! Accumulated clock counts
    integer :: ncalls(ntimers) = 0         !! Number of start/stop intervals

contains
    subroutine timer_start(id)
        integer, intent(in) :: id

        call system_clock(started(id))
    end subroutine

    subroutine timer_stop(id)
        integer, intent(in) :: id
        integer(int64) :: now

        call system_clock(now)
        elapsed(id) = elapsed(id) + (now - started(id))
        ncalls(id) = ncalls(id) + 1
    end subroutine

    !> Print each timer as "Timer <name>: <seconds> s over <n> calls"
    subroutine report_timers
        integer(int64) :: rate
        integer :: id

        call system_clock(count_rate=rate)
        do id = 1, ntimers
            write (*,'(A,A,A,F12.6,A,I0,A)') "Timer ", trim(names(id)), ": ", &
                & real(elapsed(id), kind=8)/real(rate, kind=8), " s over ", ncalls(id), " calls"
        end do
    end subroutine
end module
