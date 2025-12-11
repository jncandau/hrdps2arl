!===============================================================================
! PROGRAM: hrdps2arl
!===============================================================================
!
! PURPOSE:
!   Converts High Resolution Deterministic Prediction System (HRDPS) GRIB2 data
!   to NOAA ARL (Air Resources Laboratory) packed format for use with HYSPLIT
!   (Hybrid Single-Particle Lagrangian Integrated Trajectory) model.
!
! DESCRIPTION:
!   This program reads HRDPS meteorological data from GRIB2 files (both pressure
!   level and surface fields) and converts them to the ARL packed binary format
!   required by HYSPLIT for trajectory and dispersion calculations.
!
! INPUT FILES:
!   - Pressure level GRIB2 file (3D variables: temperature, wind, humidity, etc.)
!   - Surface GRIB2 file (2D variables: surface pressure, 10m winds, etc.)
!   - Configuration file (hrdps2arl.cfg) specifying variables to extract
!
! OUTPUT FILES:
!   - ARL packed data file (DATA.ARL)
!   - ARL configuration file (arldata.cfg)
!   - HRDPS configuration file (hrdps2arl.cfg)
!   - Log file (HRDPS2ARL.MESSAGE)
!
! USAGE:
!   hrdps2arl [-d config_file] [-l level_grib] [-s surface_grib] [-o output] [-t step]
!
! OPTIONS:
!   -d  Decoding configuration file (default: hrdps2arl.cfg)
!   -l  Input GRIB2 file with pressure level fields (default: LVL.GRIB)
!   -s  Input GRIB2 file with surface fields (default: SFC.GRIB)
!   -o  Output ARL data file (default: DATA.ARL)
!   -t  Time step skip interval (default: 1 = all times)
!
! DEPENDENCIES:
!   - ECMWF ecCodes library for GRIB2 decoding
!   - HYSPLIT library (libhysplit.a) for ARL packing routines
!
! AUTHOR:
!   JEAN-NOEL CANDAU (JEAN.NOEL.CANDAU @ google mail dot com)
!
! REFERENCES:
!   - HRDPS data: https://eccc-msc.github.io/open-data/msc-data/nwp_hrdps/
!   - HYSPLIT: https://www.ready.noaa.gov/hysplitusersguide/
!
!===============================================================================

PROGRAM hrdps2arl

    use eccodes
    implicit none

    !---------------------------------------------------------------------------
    ! VARIABLE DECLARATIONS
    !---------------------------------------------------------------------------

    ! --- Loop counters and indices ---
    integer :: i, j, k, m, n          ! General loop counters
    integer :: iii                     ! Time period counter
    integer :: kl, kv                  ! Level and variable indices

    ! --- Time-related variables ---
    integer :: fff                     ! Number of time periods in file
    integer :: tstep                   ! Time step skip interval
    integer :: iyr, imo, ida, ihr, imn ! Date/time: year, month, day, hour, minute
    integer :: fiyr, fimo, fida        ! Forecast date: year, month, day
    integer :: fihr, fimn              ! Forecast time: hour, minute
    integer :: pimn                    ! Previous time (for detecting time changes)
    integer :: zero                    ! Zero value for initialization flag

    ! --- File handling variables ---
    integer :: num_files               ! Number of input GRIB files
    integer :: tfile, afile, ffile     ! File type flags (3D level, 2D analysis, 2D forecast)
    integer :: ifile                   ! ecCodes file identifier
    integer :: iret                    ! ecCodes return code
    integer, dimension(2) :: ftype     ! File type array
    logical :: ftest                   ! File existence test flag

    ! --- GRIB message arrays ---
    integer, allocatable :: igrib(:)   ! GRIB handles for pressure level file
    integer, allocatable :: agrib(:)   ! GRIB handles for surface analysis file
    integer, allocatable :: fgrib(:)   ! GRIB handles for surface forecast file

    ! --- Message counts ---
    integer :: num_msg                 ! Messages in current file
    integer :: anum_msg                ! Messages in analysis file
    integer :: fnum_msg                ! Messages in forecast file

    ! --- Message index arrays (map messages to variables/levels) ---
    integer, allocatable :: msglev(:)  ! Level index for each pressure level message
    integer, allocatable :: msgvar(:)  ! Variable index for each pressure level message
    integer, allocatable :: amsglev(:) ! Level index for each surface analysis message
    integer, allocatable :: amsgvar(:) ! Variable index for each surface analysis message
    integer, allocatable :: fmsglev(:) ! Level index for each surface forecast message
    integer, allocatable :: fmsgvar(:) ! Variable index for each surface forecast message
    integer, allocatable :: ndxlevels(:) ! Active pressure levels

    ! --- Grid parameters ---
    integer :: nxp, nyp, nzp           ! Grid dimensions (x, y, z)
    integer :: anxp, anyp              ! Surface grid dimensions (for verification)
    real :: clat, clon                 ! Lower-left corner coordinates
    real :: clat2, clon2               ! Upper-right corner coordinates
    real :: aclat, aclon               ! Surface file lower-left corner
    real :: aclat2, aclon2             ! Surface file upper-right corner
    real :: dlat, dlon                 ! Grid spacing in degrees
    real :: adlat, adlon               ! Surface grid spacing
    real :: rlat, rlon                 ! Reference point coordinates
    real :: tlat1, tlat2               ! Tangent latitudes (for projections)

    ! --- Data arrays ---
    real, allocatable :: values(:)     ! 1D array for GRIB values
    real, allocatable :: rvalue(:,:)   ! 2D array for output data
    real, allocatable :: tvalue(:,:)   ! Temporary 2D array
    real, allocatable :: var2d(:,:)    ! 2D array for difference fields
    character(len=1), allocatable :: cvar(:) ! Packed character array for ARL output
    integer :: numberOfValues          ! Size of values array

    ! --- GRIB metadata ---
    integer :: pcat                    ! Parameter category
    integer :: levhgt                  ! Level height/pressure value
    real :: units                      ! Unit conversion factor
    character(len=256) :: value        ! Generic string value from GRIB
    character(len=256) :: pdate        ! Previous date (for time period detection)
    character(len=8) :: ltype          ! Level type string

    ! --- Character strings for I/O ---
    character(len=4) :: model          ! Model identifier (HRDP)
    character(len=4) :: param          ! Parameter name for ARL
    character(len=80) :: message       ! Error/status message
    character(len=80) :: project       ! Map projection type

    ! --- File names ---
    character(len=80) :: apicfg_name   ! Decoding configuration file
    character(len=80) :: arlcfg_name   ! ARL packing configuration file
    character(len=80) :: grib_name     ! Current GRIB file being processed
    character(len=80) :: lgrib_name    ! Pressure level GRIB file
    character(len=80) :: sgrib_name    ! Surface GRIB file
    character(len=80) :: data_name     ! Output ARL data file

    ! --- Command line processing ---
    integer :: narg                    ! Number of command line arguments
    integer :: iargc                   ! External function for argument count

    ! --- Processing flags ---
    logical :: invert = .false.        ! Invert latitude order (HRDPS is S to N)
    logical :: warn = .false.          ! Warning flag for ensemble data
    logical :: verbose = .false.       ! Verbose output flag
    integer :: ipp, ipa                ! Processing position indices
    integer :: test1, test2            ! Time matching test variables

    ! --- Constants ---
    integer, parameter :: lunit = 50   ! Output unit for ARL packed data
    integer, parameter :: kunit = 60   ! Log file unit
    integer, parameter :: maxvar = 25  ! Maximum number of variables
    integer, parameter :: maxlev = 30  ! Maximum number of pressure levels

    ! --- Variable/level configuration arrays ---
    integer :: numsfc, numatm, numlev  ! Actual counts of surface vars, atm vars, levels
    integer, dimension(maxvar) :: atmcat, atmnum  ! GRIB2 category/parameter for 3D vars
    integer, dimension(maxvar) :: sfccat, sfcnum  ! GRIB2 category/parameter for 2D vars
    real, dimension(maxvar) :: atmcnv, sfccnv     ! Unit conversion factors
    character(len=6), dimension(maxvar) :: atmgrb, sfcgrb  ! GRIB short names
    character(len=4), dimension(maxvar) :: atmarl, sfcarl  ! ARL variable names
    integer, dimension(maxlev) :: plev             ! Pressure levels (hPa)

    ! --- Variable tracking arrays ---
    integer, dimension(maxvar) :: sfcvar           ! Surface variable found flags
    integer, dimension(maxvar, maxlev) :: atmvar   ! Atmospheric variable found by level

    ! --- Variables for difference fields (DIFW, DIFR) ---
    real :: PREC, VAR1
    integer :: NEXP, KSUM

    !---------------------------------------------------------------------------
    ! NAMELIST DEFINITION
    !---------------------------------------------------------------------------
    ! Configuration namelist read from hrdps2arl.cfg
    NAMELIST/SETUP/ numatm, atmgrb, atmcnv, atmarl,   &
                    numsfc, sfcgrb, sfccnv, sfcarl,   &
                    atmcat, atmnum, sfccat, sfcnum,   &
                    numlev, plev

    ! Common block for ARL packing routines
    COMMON / PAKVAL / PREC, NEXP, VAR1, KSUM

    !---------------------------------------------------------------------------
    ! INTERFACE DECLARATIONS
    ! Interface to ARL packing routines from HYSPLIT library (libhysplit.a)
    !---------------------------------------------------------------------------
    INTERFACE

        !-----------------------------------------------------------------------
        ! MAKNDX: Creates the ARL packing configuration file
        !-----------------------------------------------------------------------
        SUBROUTINE MAKNDX(FILE_NAME, MODEL, NXP, NYP, NZP, CLAT, CLON, DLAT, DLON, &
                          RLAT, RLON, TLAT1, TLAT2, NUMSFC, NUMATM, LEVELS,        &
                          SFCVAR, ATMVAR, ATMARL, SFCARL)
            IMPLICIT NONE
            CHARACTER(80), INTENT(IN) :: file_name
            CHARACTER(4),  INTENT(IN) :: model
            INTEGER,       INTENT(IN) :: nxp, nyp, nzp
            REAL,          INTENT(IN) :: clat, clon, dlat, dlon
            REAL,          INTENT(IN) :: rlat, rlon, tlat1, tlat2
            INTEGER,       INTENT(IN) :: numsfc, numatm
            INTEGER,       INTENT(IN) :: levels(:)
            INTEGER,       INTENT(IN) :: sfcvar(:)
            INTEGER,       INTENT(IN) :: atmvar(:,:)
            CHARACTER(4),  INTENT(IN) :: atmarl(:), sfcarl(:)
        END SUBROUTINE MAKNDX

        !-----------------------------------------------------------------------
        ! PAKREC: Packs a single data record to ARL format
        !-----------------------------------------------------------------------
        SUBROUTINE PAKREC(LUNIT, RVAR, CVAR, NX, NY, NXY, KVAR, &
                          IY, IM, ID, IH, MN, IC, LL, KINI)
            IMPLICIT NONE
            INTEGER,      INTENT(IN)  :: LUNIT, NX, NY, NXY
            REAL,         INTENT(IN)  :: RVAR(NX, NY)
            CHARACTER(1), INTENT(OUT) :: CVAR(NXY)
            CHARACTER(4), INTENT(IN)  :: KVAR
            INTEGER,      INTENT(IN)  :: IY, IM, ID, IH, MN, IC, LL, KINI
        END SUBROUTINE PAKREC

        !-----------------------------------------------------------------------
        ! PAKSET: Initializes the ARL packing common block
        !-----------------------------------------------------------------------
        SUBROUTINE PAKSET(LUNIT, FNAME, KREC1, NXP, NYP, NZP)
            IMPLICIT NONE
            INTEGER,      INTENT(IN)    :: lunit, krec1
            CHARACTER(*), INTENT(INOUT) :: fname
            INTEGER,      INTENT(OUT)   :: nxp, nyp, nzp
        END SUBROUTINE PAKSET

        !-----------------------------------------------------------------------
        ! PAKINP: Unpacks ARL data (for verification)
        !-----------------------------------------------------------------------
        SUBROUTINE PAKINP(RVAR, CVAR, NX, NY, NX1, NY1, LX, LY, &
                          PREC, NEXP, VAR1, KSUM)
            REAL,         INTENT(OUT)   :: rvar(:,:)
            CHARACTER(1), INTENT(IN)    :: cvar(:)
            INTEGER,      INTENT(IN)    :: nx, ny, nx1, ny1, lx, ly
            REAL,         INTENT(IN)    :: prec, var1
            INTEGER,      INTENT(IN)    :: nexp
            INTEGER,      INTENT(INOUT) :: ksum
        END SUBROUTINE PAKINP

    END INTERFACE

    !===========================================================================
    ! MAIN PROGRAM EXECUTION
    !===========================================================================

    !---------------------------------------------------------------------------
    ! SECTION 1: Parse command line arguments
    !---------------------------------------------------------------------------
    narg = iargc()

    ! Display usage if no arguments provided
    if (narg == 0) then
        write(*,*) 'Usage: hrdps2arl [-options]'
        write(*,*) ''
        write(*,*) 'Converts HRDPS GRIB2 data to ARL format for HYSPLIT.'
        write(*,*) ''
        write(*,*) 'One pressure level file and at least one surface file must be input.'
        write(*,*) 'The surface file(s) should have all the time periods that'
        write(*,*) 'pressure level files have but they can have extra time periods.'
        write(*,*) ''
        write(*,*) 'A default hrdps2arl.cfg will be created if none exists or'
        write(*,*) 'alternate name is not specified with the -d option.'
        write(*,*) 'This file specifies variables and pressure levels to be written'
        write(*,*) 'to the ARL file.'
        write(*,*) ''
        write(*,*) 'Options:'
        write(*,*) '  -d[file]  Decoding configuration file (default: hrdps2arl.cfg)'
        write(*,*) '  -l[file]  Input GRIB2 file with pressure levels (default: LVL.GRIB)'
        write(*,*) '  -s[file]  Input GRIB2 file with surface fields (default: SFC.GRIB)'
        write(*,*) '  -o[file]  Output ARL data file (default: DATA.ARL)'
        write(*,*) '  -t[N]     Extract every Nth time period (default: 1 = all)'
        stop
    end if

    ! Set default file names
    arlcfg_name = 'arldata.cfg'
    apicfg_name = 'hrdps2arl.cfg'
    lgrib_name  = 'LVL.GRIB'
    sgrib_name  = 'SFC.GRIB'
    data_name   = 'DATA.ARL'
    tstep       = 1

    ! Parse command line arguments
    do while (narg > 0)
        call getarg(narg, message)
        select case (message(1:2))
            case ('-d', '-D')
                read(message(3:), '(A)') apicfg_name
            case ('-l', '-L')
                read(message(3:), '(A)') lgrib_name
            case ('-s', '-S')
                read(message(3:), '(A)') sgrib_name
            case ('-o', '-O')
                read(message(3:), '(A)') data_name
            case ('-t', '-T')
                read(message(3:), '(I2)') tstep
        end select
        narg = narg - 1
    end do

    ! Report time step setting if skipping
    if (tstep > 1) then
        write(*,*) 'Skipping to every ', tstep, ' time period in GRIB files'
    end if

    !---------------------------------------------------------------------------
    ! SECTION 2: Read or create configuration file
    !---------------------------------------------------------------------------
    inquire(file=trim(apicfg_name), exist=ftest)
    if (.not. ftest) then
        write(*,*) 'Creating new decoding configuration: ', apicfg_name
        call makapi(apicfg_name)
    else
        write(*,*) 'Existing decoding configuration: ', trim(apicfg_name)
    end if

    ! Read configuration namelist
    open(10, file=trim(apicfg_name))
    read(10, SETUP)
    close(10)

    ! Create level index array from configuration
    allocate(ndxlevels(numlev))
    do iii = 1, numlev
        ndxlevels(iii) = plev(iii)
    end do

    ! Open log file and write configuration summary
    open(kunit, file='HRDPS2ARL.MESSAGE')
    write(kunit,*) 'numsfc =', numsfc
    write(kunit,*) 'numatm =', numatm
    write(kunit,*) 'numlev =', numlev
    write(kunit,*) 'levels =', ndxlevels

    !---------------------------------------------------------------------------
    ! SECTION 3: Verify input files exist
    !---------------------------------------------------------------------------
    ftype     = 0
    num_files = 0
    afile     = 0
    ffile     = 0
    tfile     = 0

    ! Check for pressure level file
    inquire(file=trim(lgrib_name), exist=ftest)
    if (ftest) then
        num_files = num_files + 1
        ftype(num_files) = 2  ! Type 2 = pressure level file
        tfile = 1
    else
        write(*,*) 'FILE NOT FOUND: ', lgrib_name
    end if

    ! Check for surface file
    inquire(file=trim(sgrib_name), exist=ftest)
    if (ftest) then
        num_files = num_files + 1
        ftype(num_files) = 1  ! Type 1 = surface file
        afile = 1
    else
        write(*,*) 'FILE NOT FOUND: ', sgrib_name
    end if

    write(*,*) 'We have ', num_files, ' type(s) of input GRIB2 file(s)'
    write(*,*) '--------------------------------------------------------'

    ! Initialize surface variable counter
    sfcvar = 0

    !---------------------------------------------------------------------------
    ! SECTION 4: First pass through GRIB files - determine structure
    !---------------------------------------------------------------------------
    ! Process files: surface first, then pressure levels
    do iii = 1, num_files

        select case (ftype(num_files - iii + 1))
            case (2)
                write(*,*) 'File ', iii, ' is a level file'
                grib_name = lgrib_name
            case (1)
                write(*,*) 'File ', iii, ' is a surface file'
                grib_name = sgrib_name
        end select

        ! Enable multi-field message support
        call grib_multi_support_on(iret)
        if (iret /= grib_success) goto 900

        ! Open GRIB file
        call grib_open_file(ifile, trim(grib_name), 'r', iret)
        if (iret /= grib_success) goto 900
        write(*,*) '  File name: ', grib_name

        ! Count messages in file
        call grib_count_in_file(ifile, num_msg, iret)
        if (iret /= grib_success) goto 900
        write(*,*) '  Message count: ', num_msg

        !-----------------------------------------------------------------------
        ! Process based on file type
        !-----------------------------------------------------------------------
        select case (ftype(num_files - iii + 1))

            !-------------------------------------------------------------------
            ! CASE 2: Pressure level (3D) file
            !-------------------------------------------------------------------
            case (2)
                atmvar = 0  ! Reset atmospheric variable tracking

                ! Allocate arrays for this file
                allocate(igrib(num_msg))
                allocate(msglev(num_msg))
                allocate(msgvar(num_msg))
                igrib  = -1
                msglev = -1
                msgvar = -1

                ! Load all messages into memory
                do i = 1, num_msg
                    call grib_new_from_file(ifile, igrib(i), iret)
                    if (iret /= grib_success) goto 900
                end do
                call grib_close_file(ifile, iret)
                if (iret /= grib_success) goto 900

                write(*,*) '  Processing level GRIB file'

                ! Initialize for time period counting
                pdate = 'no_value'

                ! Analyze each message
                do i = 1, num_msg
                    call grib_get(igrib(i), 'levelType', ltype)

                    ! Count time periods by detecting date/time changes
                    call grib_get(igrib(i), 'validityDate', value)
                    call grib_get(igrib(i), 'validityTime', imn)

                    if (i == 1) then
                        fff = 1
                    else if ((pdate /= value) .or. (pimn /= imn)) then
                        fff = fff + 1
                    end if
                    pdate = value
                    pimn  = imn

                    ! Process only pressure level variables
                    if (trim(ltype) == 'pl') then
                        call grib_get(igrib(i), 'shortName', value)
                        call grib_get(igrib(i), 'parameterCategory', pcat)

                        ! Find variable index in configuration
                        kv = -1
                        do k = 1, numatm
                            if (pcat == atmcat(k) .and. trim(value) == atmgrb(k)) kv = k
                        end do

                        ! If variable found, check if level is configured
                        if (kv /= -1) then
                            call grib_get(igrib(i), 'level', levhgt)
                            write(kunit,*) 'Level found:', trim(value), pcat, levhgt

                            kl = -1
                            do k = 1, numlev
                                if (ndxlevels(k) == levhgt) kl = k
                            end do
                            if (kl == -1) kv = -1

                            ! Store message indices
                            msglev(i) = kl
                            msgvar(i) = kv

                            ! Mark variable/level combination as found
                            if ((kl /= -1) .or. (kv /= -1)) then
                                atmvar(kv, kl) = 1
                            end if
                        end if
                    else
                        write(kunit,*) 'levelType not pl for message: ', i, ltype
                    end if
                end do

                write(*,*) "  Finished processing levels file"
                write(kunit,*) 'Number of time periods found:', fff
                if (warn) then
                    write(*,*) "Warning: File may contain ensemble data"
                end if
                write(*,*) '--------------------------------------------------------'
                warn = .false.

            !-------------------------------------------------------------------
            ! CASE 1: Surface analysis (2D) file
            !-------------------------------------------------------------------
            case (1)
                anum_msg = num_msg
                write(*,*) "  Processing analysis surface file"

                ! Allocate arrays for this file
                allocate(agrib(anum_msg))
                allocate(amsglev(anum_msg))
                allocate(amsgvar(anum_msg))
                agrib   = -1
                amsglev = -1
                amsgvar = -1

                ! Load all messages into memory
                do i = 1, num_msg
                    call grib_new_from_file(ifile, agrib(i), iret)
                    if (iret /= grib_success) goto 900
                end do
                call grib_close_file(ifile, iret)
                if (iret /= grib_success) goto 900

                ! Analyze each message
                do i = 1, num_msg
                    call grib_get(agrib(i), 'levelType', ltype)

                    if (trim(ltype) == 'sfc') then
                        call grib_get(agrib(i), 'shortName', value)
                        call grib_get(agrib(i), 'parameterCategory', pcat)
                        call grib_get(agrib(i), 'level', levhgt)

                        ! Find variable index in configuration
                        kv = -1
                        do k = 1, numsfc
                            if (pcat == sfccat(k)) then
                                if (trim(value) == sfcgrb(k)) kv = k
                                if (trim(value) == 'unknown') kv = k
                            end if
                        end do

                        if (kv /= -1) then
                            amsglev(i) = 0   ! Surface level
                            amsgvar(i) = kv
                            sfcvar(kv) = 1   ! Mark variable as found
                        end if
                    end if
                end do

                write(*,*) "  Finished processing analysis surface file"
                write(*,*) '--------------------------------------------------------'

        end select

    end do  ! End file loop

    !---------------------------------------------------------------------------
    ! SECTION 5: Extract grid information and create ARL configuration
    !---------------------------------------------------------------------------
    model = 'HRDP'

    ! Use message 10 for grid info (arbitrary choice - all should be same)
    i = 10
    call grib_get(igrib(i), 'gridType', project)
    write(kunit,*) 'PROJECTION ', trim(project)

    ! Initialize reference point (0,0 indicates regular lat/lon grid)
    rlat = 0.0
    rlon = 0.0

    ! Get grid parameters from pressure level file
    call grib_get(igrib(i), 'latitudeOfFirstGridPointInDegrees', clat)
    call grib_get(igrib(i), 'longitudeOfFirstGridPointInDegrees', clon)
    call grib_get(igrib(i), 'latitudeOfLastGridPointInDegrees', clat2)
    call grib_get(igrib(i), 'longitudeOfLastGridPointInDegrees', clon2)
    call grib_get(igrib(i), 'iDirectionIncrementInDegrees', dlon)
    call grib_get(igrib(i), 'jDirectionIncrementInDegrees', dlat)
    call grib_get(igrib(i), 'numberOfPointsAlongAParallel', nxp)
    call grib_get(igrib(i), 'numberOfPointsAlongAMeridian', nyp)

    ! Get grid parameters from surface file for verification
    call grib_get(agrib(i), 'latitudeOfFirstGridPointInDegrees', aclat)
    call grib_get(agrib(i), 'longitudeOfFirstGridPointInDegrees', aclon)
    call grib_get(agrib(i), 'latitudeOfLastGridPointInDegrees', aclat2)
    call grib_get(agrib(i), 'longitudeOfLastGridPointInDegrees', aclon2)
    call grib_get(agrib(i), 'iDirectionIncrementInDegrees', adlon)
    call grib_get(agrib(i), 'jDirectionIncrementInDegrees', adlat)
    call grib_get(agrib(i), 'numberOfPointsAlongAParallel', anxp)
    call grib_get(agrib(i), 'numberOfPointsAlongAMeridian', anyp)

    ! Log grid comparison for debugging
    write(kunit,*) '---------------------------------------------------------'
    write(kunit,*) 'Verifying 2D analysis and 3D pressure level grids match:'
    write(kunit,*) 'First lat:  ', clat, aclat
    write(kunit,*) 'First lon:  ', clon, aclon
    write(kunit,*) 'Last lat:   ', clat2, aclat2
    write(kunit,*) 'Last lon:   ', clon2, aclon2
    write(kunit,*) 'Delta lat:  ', dlat, adlat
    write(kunit,*) 'Delta lon:  ', dlon, adlon
    write(kunit,*) 'NX points:  ', nxp, anxp
    write(kunit,*) 'NY points:  ', nyp, anyp
    write(kunit,*) '---------------------------------------------------------'

    ! Create ARL packing configuration file
    call MAKNDX(arlcfg_name, model, nxp, nyp, numlev, clat, clon, dlat, dlon, &
                rlat, rlon, tlat1, tlat2, numsfc, numatm, ndxlevels,          &
                sfcvar, atmvar, atmarl, sfcarl)

    deallocate(ndxlevels)

    !---------------------------------------------------------------------------
    ! SECTION 6: Initialize ARL packing and open output file
    !---------------------------------------------------------------------------
    call PAKSET(lunit, arlcfg_name, 1, nxp, nyp, nzp)
    open(lunit, file=trim(data_name), recl=(50 + nxp*nyp), access='DIRECT', &
         form='UNFORMATTED')

    ! Allocate data arrays
    call grib_get_size(igrib(i), 'values', numberOfValues)
    allocate(values(numberOfValues), stat=iret)
    allocate(cvar(numberOfValues), stat=iret)
    write(kunit,*) 'Grid size:', nxp, nyp, numberOfValues

    ! Verify array dimensions are consistent
    if (numberOfValues /= nxp * nyp) then
        write(*,*) 'ERROR: Inconsistent 1D and 2D array size!'
        write(*,*) '1D array: ', numberOfValues
        write(*,*) '2D array: ', nxp, nyp
        stop
    end if

    allocate(rvalue(nxp, nyp), stat=iret)
    allocate(tvalue(nxp, nyp), stat=iret)
    allocate(var2d(nxp, nyp), stat=iret)

    write(*,*) 'Packing routines initialized successfully'

    !---------------------------------------------------------------------------
    ! SECTION 7: Main processing loop - convert and pack data
    !---------------------------------------------------------------------------
    write(*,*) 'Processing time periods...'

    ipp = 1
    ipa = 1

    ! Loop through each time period
    do iii = 1, fff, tstep

        write(*,*) 'Time period:', iii

        !-----------------------------------------------------------------------
        ! Process 3D pressure level variables
        !-----------------------------------------------------------------------
        write(*,*) 'Processing levels file: ', lgrib_name
        write(*,*) 'Message range:', (iii-1)*num_msg/fff + 1, 'to', (iii-1)*num_msg/fff + num_msg/fff

        do i = (iii-1)*num_msg/fff + 1, (iii-1)*num_msg/fff + num_msg/fff

            ! Get validity date/time
            call grib_get(igrib(i), 'validityDate', value)
            read(value, '(2X,3I2)') iyr, imo, ida
            call grib_get(igrib(i), 'validityTime', imn)
            ihr = imn / 100
            imn = imn - ihr * 100

            ! Skip messages not in configuration
            if (msgvar(i) < 0) cycle

            ! Get variable and level indices
            kl = msglev(i)
            kv = msgvar(i)

            ! Set parameter name and conversion factor
            if (kl == 0) then
                param = sfcarl(kv)
                units = sfccnv(kv)
            else
                param = atmarl(kv)
                units = atmcnv(kv)
            end if

            call grib_get(igrib(i), 'shortName', value)
            call grib_get(igrib(i), 'level', levhgt)

            if (verbose) then
                write(kunit,*) '3D variable: ', i, ihr, imn, param, ' ', trim(value), levhgt, kl, kv
            end if

            ! Extract data values
            call grib_get(igrib(i), 'values', values)

            ! Reshape 1D array to 2D, handling latitude inversion if needed
            ! HRDPS data may be stored N to S, ARL expects S to N
            k = 0
            do j = 1, nyp
                n = j
                if (invert) n = nyp + 1 - j
                do m = 1, nxp
                    k = k + 1
                    ! Handle missing values for specific parameters
                    if (param == 'RGHS' .and. values(k) == 9999.0) values(k) = 0.01
                    if (param == 'WWND' .and. values(k) == 9999.0) values(k) = 0.0
                    rvalue(m, n) = values(k) * units
                end do
            end do

            ! Pack and write record
            call PAKREC(lunit, rvalue, cvar, nxp, nyp, (nxp*nyp), param, &
                        iyr, imo, ida, ihr, imn, 0, (kl+1), zero)

        end do  ! End 3D message loop

        !-----------------------------------------------------------------------
        ! Process 2D surface variables
        !-----------------------------------------------------------------------
        if (afile == 1) then
            write(*,*) 'Processing surface file: ', sgrib_name
            test2 = 0

            do i = 1, anum_msg
                test1 = 0

                ! Get validity date/time for this surface message
                call grib_get(agrib(i), 'validityDate', value)
                read(value, '(2X,3I2)') fiyr, fimo, fida
                call grib_get(agrib(i), 'validityTime', fimn)
                fihr = fimn / 100
                fimn = fimn - fihr * 100

                ! Check if this message matches current time period
                if (fihr /= ihr) test1 = test1 + 1
                if (fida /= ida) test1 = test1 + 1
                if (fimo /= imo) test1 = test1 + 1
                if (test1 > 0) cycle

                test2 = test2 + 1

                ! Skip messages not in configuration
                if (amsgvar(i) < 0) cycle

                ! Get variable and level indices
                kl = amsglev(i)
                kv = amsgvar(i)

                ! Set parameter name and conversion factor
                if (kl == 0) then
                    param = sfcarl(kv)
                    units = sfccnv(kv)
                else
                    param = atmarl(kv)
                    units = atmcnv(kv)
                end if

                call grib_get(agrib(i), 'shortName', value)
                call grib_get(agrib(i), 'level', levhgt)

                if (verbose) then
                    write(kunit,*) '2D variable: ', i, param, iyr, imo, ida, ihr
                end if

                ! Extract data values
                call grib_get(agrib(i), 'values', values)

                ! Reshape 1D array to 2D
                k = 0
                do j = 1, nyp
                    n = j
                    if (invert) n = nyp + 1 - j
                    do m = 1, nxp
                        k = k + 1
                        rvalue(m, n) = values(k) * units
                    end do
                end do

                ! Pack and write record
                call PAKREC(lunit, rvalue, cvar, nxp, nyp, (nxp*nyp), param, &
                            iyr, imo, ida, ihr, imn, 0, (kl+1), zero)

            end do  ! End 2D message loop
        end if

        ! Write index record to complete this time period
        call PAKNDX(lunit)
        write(*,*)  'Completed time: ', iyr, imo, ida, ihr, imn
        write(kunit,*) 'Completed time: ', iyr, imo, ida, ihr, imn

    end do  ! End time period loop

    !---------------------------------------------------------------------------
    ! SECTION 8: Cleanup and exit
    !---------------------------------------------------------------------------

    ! Release GRIB handles for pressure level file
    do i = 1, num_msg
        call grib_release(igrib(i))
    end do
    deallocate(igrib)
    deallocate(msglev)
    deallocate(msgvar)

    ! Release GRIB handles for surface analysis file
    if (afile == 1) then
        do i = 1, anum_msg
            call grib_release(agrib(i))
        end do
        deallocate(agrib)
        deallocate(amsglev)
        deallocate(amsgvar)
    end if

    ! Release GRIB handles for surface forecast file (if used)
    if (ffile == 1) then
        do i = 1, fnum_msg
            call grib_release(fgrib(i))
        end do
        deallocate(fgrib)
        deallocate(fmsglev)
        deallocate(fmsgvar)
    end if

    ! Deallocate data arrays
    deallocate(cvar)
    deallocate(values)
    deallocate(rvalue)
    deallocate(tvalue)
    deallocate(var2d)

    ! Close files
    close(kunit)
    close(lunit)

    write(*,*) 'Conversion completed successfully!'
    stop

    !---------------------------------------------------------------------------
    ! Error handler
    !---------------------------------------------------------------------------
900 continue
    call grib_get_error_string(iret, message)
    write(*,*) 'ERROR: ', message
    stop 900

END PROGRAM hrdps2arl


!===============================================================================
! SUBROUTINE: MAKNDX
!===============================================================================
!
! PURPOSE:
!   Creates the ARL packing configuration file (arldata.cfg) that defines
!   the structure of the output packed data file.
!
! DESCRIPTION:
!   This subroutine writes the HYSPLIT/ARL configuration file that specifies:
!   - Model identification
!   - Grid geometry and projection parameters
!   - Variable definitions at each level
!
! ARGUMENTS:
!   FILE_NAME  - Output configuration file name
!   MODEL      - 4-character model identifier
!   NXP, NYP   - Horizontal grid dimensions
!   NZP        - Number of vertical levels
!   CLAT, CLON - Lower-left corner coordinates
!   DLAT, DLON - Grid spacing in degrees
!   RLAT, RLON - Reference point (0,0 for regular lat/lon)
!   TLAT1, TLAT2 - Tangent latitudes (for Lambert conformal)
!   NUMSFC     - Number of surface variables
!   NUMATM     - Number of atmospheric (3D) variables
!   LEVELS     - Pressure level values
!   SFCVAR     - Surface variable found flags
!   ATMVAR     - Atmospheric variable found flags by level
!   ATMARL     - ARL names for atmospheric variables
!   SFCARL     - ARL names for surface variables
!
!===============================================================================

SUBROUTINE MAKNDX(FILE_NAME, MODEL, NXP, NYP, NZP, CLAT, CLON, DLAT, DLON,   &
                  RLAT, RLON, TLAT1, TLAT2, NUMSFC, NUMATM, LEVELS,          &
                  SFCVAR, ATMVAR, ATMARL, SFCARL)

    implicit none

    ! Arguments
    character(80), intent(in) :: file_name
    character(4),  intent(in) :: model
    integer,       intent(in) :: nxp, nyp, nzp
    real,          intent(in) :: clat, clon, dlat, dlon
    real,          intent(in) :: rlat, rlon, tlat1, tlat2
    integer,       intent(in) :: numsfc, numatm
    integer,       intent(in) :: levels(:)
    integer,       intent(in) :: sfcvar(:)
    integer,       intent(in) :: atmvar(:,:)
    character(4),  intent(in) :: atmarl(:), sfcarl(:)

    ! Local variables
    character(4)  :: VCHAR(50)     ! Variable identifiers for current level
    character(20) :: LABEL(18)     ! Configuration file labels
    integer       :: n, nl, mvar   ! Loop counters
    real          :: sig           ! Sigma/pressure level value
    real          :: GRIDS(12)     ! Grid definition array

    ! Configuration file labels
    DATA LABEL / 'Model Type:', 'Grid Numb:', 'Vert Coord:', 'Pole Lat:',   &
                 'Pole Lon:', 'Ref Lat:', 'Ref Lon:', 'Grid Size:',         &
                 'Orientation:', 'Cone Angle:', 'Sync X Pt:', 'Sync Y Pt:', &
                 'Sync Lat:', 'Sync Lon:', 'Reserved:', 'Numb X pt:',       &
                 'Numb Y pt:', 'Numb Levels:' /

    !---------------------------------------------------------------------------
    ! Set up grid definition array
    !---------------------------------------------------------------------------

    ! Sync point defines lower-left grid point
    GRIDS(8)  = 1.0
    GRIDS(9)  = 1.0

    ! Lower-left corner coordinates
    GRIDS(10) = CLAT
    GRIDS(11) = CLON

    ! Convert to 0-360 longitude convention
    if (GRIDS(11) < 0.0) GRIDS(11) = 360.0 + GRIDS(11)

    ! Configure for regular lat/lon grid (RLAT=0, RLON=0)
    if (RLAT == 0.0 .and. RLON == 0.0) then
        ! Upper-right corner (pole position for lat/lon grids)
        GRIDS(1) = GRIDS(10) + DLAT * (NYP - 1)
        GRIDS(2) = GRIDS(11) + DLON * (NXP - 1)
        GRIDS(2) = AMOD(GRIDS(2), 360.0)

        ! Grid spacing stored in reference position
        GRIDS(3) = DLAT
        GRIDS(4) = DLON

        ! No grid size/orientation for lat/lon
        GRIDS(5) = 0.0
        GRIDS(6) = 0.0
        GRIDS(7) = 0.0
    end if

    ! Reserved field
    GRIDS(12) = 0.0

    !---------------------------------------------------------------------------
    ! Write configuration file
    !---------------------------------------------------------------------------
    open(30, file=FILE_NAME)

    ! Header: model type and grid number
    write(30, '(A20,A4)') LABEL(1), MODEL
    write(30, '(A20,A4)') LABEL(2), '  99'

    ! Vertical coordinate type (2 = pressure)
    write(30, '(A20,I4)') LABEL(3), 2

    ! Grid parameters
    do n = 1, 12
        write(30, '(A20,F10.4)') LABEL(n+3), GRIDS(n)
    end do

    ! Grid dimensions
    write(30, '(A20,I4)') LABEL(16), NXP
    write(30, '(A20,I4)') LABEL(17), NYP
    write(30, '(A20,I4)') LABEL(18), NZP + 1

    !---------------------------------------------------------------------------
    ! Write level definitions
    !---------------------------------------------------------------------------
    do nl = 1, nzp + 1

        write(LABEL(1), '(A6,I4,A1)') 'Level ', nl, ':'

        if (nl == 1) then
            ! Surface level
            sig  = 0.0
            mvar = 0

            ! List surface variables that were found
            do n = 1, numsfc
                if (sfcvar(n) == 1) then
                    mvar = mvar + 1
                    VCHAR(mvar) = sfcarl(n)
                end if
            end do

        else
            ! Upper levels
            sig  = LEVELS(nl - 1)
            mvar = 0

            ! List atmospheric variables that were found at this level
            do n = 1, numatm
                if (atmvar(n, nl-1) == 1) then
                    mvar = mvar + 1
                    VCHAR(mvar) = atmarl(n)
                end if
            end do
        end if

        ! Write level line with appropriate format for sigma/pressure value
        if (sig < 1.0) then
            write(30, '(A20,F6.5,I3,99(1X,A4))') LABEL(1), sig, mvar, (VCHAR(n), n=1, mvar)
        else if (sig >= 1.0 .and. sig < 10.0) then
            write(30, '(A20,F6.4,I3,99(1X,A4))') LABEL(1), sig, mvar, (VCHAR(n), n=1, mvar)
        else if (sig >= 10.0 .and. sig < 100.0) then
            write(30, '(A20,F6.3,I3,99(1X,A4))') LABEL(1), sig, mvar, (VCHAR(n), n=1, mvar)
        else if (sig >= 100.0 .and. sig < 1000.0) then
            write(30, '(A20,F6.2,I3,99(1X,A4))') LABEL(1), sig, mvar, (VCHAR(n), n=1, mvar)
        else if (sig >= 1000.0) then
            write(30, '(A20,F6.1,I3,99(1X,A4))') LABEL(1), sig, mvar, (VCHAR(n), n=1, mvar)
        end if

    end do

    close(30)

END SUBROUTINE MAKNDX


!===============================================================================
! SUBROUTINE: MAKAPI
!===============================================================================
!
! PURPOSE:
!   Creates the default decoding configuration file (hrdps2arl.cfg) that
!   specifies which GRIB2 variables to extract and convert.
!
! DESCRIPTION:
!   This subroutine generates a namelist file containing:
!   - GRIB2 variable definitions (short name, category, parameter number)
!   - Unit conversion factors (HRDPS to ARL units)
!   - ARL variable names
!   - Pressure levels to extract
!
! VARIABLE MAPPING (HRDPS -> HYSPLIT/ARL):
!
!   3D Variables:
!     gh    -> HGTS  : Geopotential height (gpm)
!     t     -> TEMP  : Temperature (K)
!     u     -> UWND  : U-wind component (m/s)
!     v     -> VWND  : V-wind component (m/s)
!     w     -> WWND  : Omega (Pa/s -> hPa/s, factor 0.01)
!     r     -> RELH  : Relative humidity (%)
!     q     -> SPHU  : Specific humidity (kg/kg)
!
!   2D Variables:
!     prmsl -> MSLP  : Mean sea level pressure (Pa -> hPa, factor 0.01)
!     10u   -> U10M  : 10m U-wind (m/s)
!     10v   -> V10M  : 10m V-wind (m/s)
!     2t    -> T02M  : 2m temperature (K)
!     blh   -> PBLH  : Boundary layer height (m)
!     sp    -> PRSS  : Surface pressure (Pa -> hPa, factor 0.01)
!     ishf  -> SHTF  : Sensible heat flux (W/m2)
!     ssrd  -> DSWF  : Downward shortwave flux (W/m2)
!     2r    -> RH2M  : 2m relative humidity (%)
!     2sh   -> SPH2  : 2m specific humidity (kg/kg)
!     h     -> SHGT  : Surface orography (m)
!     cape  -> CAPE  : Convective available potential energy (W/m2)
!     prate -> TPP1  : Total precip (1h) (kg/(m2*s) -> m factor 3.6)
!     tcc   -> TCLD  : Total cloud cover (%)
!     lhtfl -> LTHF  : Latent heat flux (W/m2)
!
! ARGUMENTS:
!   apicfg_name - Output configuration file name
!
! REFERENCES:
!   HRDPS: https://eccc-msc.github.io/open-data/msc-data/nwp_hrdps/readme_hrdps-datamart_en/
!   HYSPLIT: https://www.ready.noaa.gov/hysplitusersguide/S141.htm
!
!===============================================================================

SUBROUTINE MAKAPI(apicfg_name)

    implicit none

    ! Arguments
    character(len=80), intent(in) :: apicfg_name

    ! Local variables for string formatting
    character(len=1) :: a, c    ! Apostrophe and comma characters
    character(len=3) :: d       ! Delimiter string ','

    ! Build delimiter strings for namelist formatting
    a = char(39)  ! Apostrophe
    c = char(44)  ! Comma
    d(1:1) = a
    d(2:2) = c
    d(3:3) = a

    !---------------------------------------------------------------------------
    ! Write configuration file
    !---------------------------------------------------------------------------
    open(30, file=trim(apicfg_name))

    write(30, '(a)') '&SETUP'

    ! 3D atmospheric variables
    write(30, '(a)') ' numatm = 7,'
    write(30, '(a)') ' atmgrb = ' // a // 'gh' // d // 't' // d // 'u' // d // &
                     'v' // d // 'w' // d // 'r' // d // 'q' // a // c
    write(30, '(a)') ' atmcat =      3 ,   0 ,    2 ,   2 ,   2 ,    1 ,  1,'
    write(30, '(a)') ' atmnum =      5 ,   0 ,    2 ,   3 ,   8 ,    1 ,   0 ,'
    write(30, '(a)') ' atmcnv =     1.0 ,  1.0 ,   1.0 ,   1.0 ,  0.01,   1.0 , 1.0 ,'
    write(30, '(a)') ' atmarl = ' // a // 'HGTS' // d // 'TEMP' // d // 'UWND' // d // &
                     'VWND' // d // 'WWND' // d // 'RELH' // d // 'SPHU' // a // c

    ! 2D surface variables
    write(30, '(a)') ' numsfc = 15,'
    write(30, '(a)') ' sfcgrb = ' // a // 'prmsl' // d // '10u' // d // '10v' // d // &
                     '2t' // d // 'blh' // d // 'sp' // d // 'ishf' // d // 'ssrd' // d // &
                     '2r' // d // '2sh' // d // 'h' // d // 'cape' // d
                     // 'prate' // d // 'tcc' // d // 'lhtfl' //a // c
    write(30, '(a)') ' sfccat =      3,   2,  2,    0,   3,    3,   0,
    4,   1,   1,  3, 7, 1, 6, 0'
    write(30, '(a)') ' sfcnum =      1,   2,  3,    0,  18,    0,  11,
    7,   1,   0,  6, 6, 7, 1, 10'
    write(30, '(a)') ' sfccnv =   0.01, 1.0, 1.0, 1.0, 1.0, 0.01, 1.0,
    1.0, 1.0, 1.0, 1.0, 1.0, 3.6, 1, 1'
    write(30, '(a)') ' sfcarl = ' // a // 'MSLP' // d // 'U10M' // d // 'V10M' // d // &
            'T02M' // d // 'PBLH' // d // 'PRSS' // d // 'SHTF' // d // 'DSWF' // d // &
            'RH2M' // d // 'SPH2' // d // 'SHGT' // d // 'CAPE' // d //
            'TPP1' // d // 'TCLD' // d // 'LTHF' // a // c

    ! Pressure levels (hPa)
    write(30, '(a)') ' numlev = 26'
    write(30, '(a)') ' plev = 1015, 1000, 985, 970, 950, 925, 900, 850, 800, &
                    750, 700, 650, 600, 550, 500, 450, &
                    400, 350, 300, 275, 250, 225, 200, 150, 100, 50 '

    write(30, '(a)') '/'
    close(30)

END SUBROUTINE MAKAPI
