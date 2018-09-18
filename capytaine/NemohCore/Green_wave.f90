MODULE GREEN_WAVE

  USE CONSTANTS
  USE INITIALIZE_GREEN_WAVE
  USE GREEN_RANKINE, ONLY: COMPUTE_ASYMPTOTIC_RANKINE_SOURCE

  IMPLICIT NONE

  ! Dependancies between the functions of this module:
  ! (from top to bottom: "is called by")
  !
  !            LAGRANGE_POLYNOMIAL_INTERPOLATION
  !                          |
  !              COMPUTE_INTEGRAL_WRT_THETA       (COMPUTE_ASYMPTOTIC_RANKINE_SOURCE)
  !                        /   \                    /
  ! WAVE_PART_INFINITE_DEPTH   WAVE_PART_FINITE_DEPTH
  !                        \   /
  !              BUILD_MATRICES_WAVE_SOURCE
  !                          |
  !                    (python code)

CONTAINS

  ! =====================================================================

  SUBROUTINE LAGRANGE_POLYNOMIAL_INTERPOLATION &
    (AKR, AKZ,                                 &
     XR, XZ, APD,                              &
     PD1X, PD2X, PD1Z, PD2Z)
   ! Helper function used in the following subroutine to interpolate between the tabulated integrals.

    ! Inputs
    REAL(KIND=PRE),                        INTENT(IN) :: AKR, AKZ
    REAL(KIND=PRE), DIMENSION(3),          INTENT(IN) :: XR
    REAL(KIND=PRE), DIMENSION(3),          INTENT(IN) :: XZ
    REAL(KIND=PRE), DIMENSION(3, 3, 2, 2), INTENT(IN) :: APD

    ! Output
    REAL(KIND=PRE), INTENT(OUT) :: PD1X, PD2X, PD1Z, PD2Z

    ! Local variable
    REAL(KIND=PRE), DIMENSION(3) :: XL, ZL

    XL(1) = PL2(XR(2), XR(3), XR(1), AKR)
    XL(2) = PL2(XR(3), XR(1), XR(2), AKR)
    XL(3) = PL2(XR(1), XR(2), XR(3), AKR)
    ZL(1) = PL2(XZ(2), XZ(3), XZ(1), AKZ)
    ZL(2) = PL2(XZ(3), XZ(1), XZ(2), AKZ)
    ZL(3) = PL2(XZ(1), XZ(2), XZ(3), AKZ)

    PD1Z = DOT_PRODUCT(XL, MATMUL(APD(:, :, 1, 2), ZL))
    PD2Z = DOT_PRODUCT(XL, MATMUL(APD(:, :, 2, 2), ZL))
    PD1X = DOT_PRODUCT(XL, MATMUL(APD(:, :, 1, 1), ZL))
    PD2X = DOT_PRODUCT(XL, MATMUL(APD(:, :, 2, 1), ZL))

  CONTAINS

    REAL(KIND=PRE) FUNCTION PL2(U1, U2, U3, XU)
      REAL(KIND=PRE) :: U1, U2, U3, XU
      PL2 = ((XU-U1)*(XU-U2))/((U3-U1)*(U3-U2))
      RETURN
    END FUNCTION

  END SUBROUTINE LAGRANGE_POLYNOMIAL_INTERPOLATION

  ! =====================================================================

  SUBROUTINE COMPUTE_INTEGRAL_WRT_THETA &
      (XI, XJ, depth, wavenumber,       &
      XR, XZ, APD,                      &
      FS, VS)
    ! Compute the integral with respect to theta and its derivative.
    ! This integral is also called S^2 in Eq. (9) of [Babarit and Delhommeau, 2015]

    ! Inputs
    REAL(KIND=PRE), DIMENSION(3),             INTENT(IN) :: XI, XJ
    REAL(KIND=PRE),                           INTENT(IN) :: depth, wavenumber

    ! Tabulated data
    REAL(KIND=PRE), DIMENSION(328),           INTENT(IN) :: XR
    REAL(KIND=PRE), DIMENSION(46),            INTENT(IN) :: XZ
    REAL(KIND=PRE), DIMENSION(328, 46, 2, 2), INTENT(IN) :: APD

    ! Outputs
    COMPLEX(KIND=PRE),                        INTENT(OUT) :: FS
    COMPLEX(KIND=PRE), DIMENSION(3),          INTENT(OUT) :: VS

    ! Local variables
    INTEGER        :: KI, KJ
    REAL(KIND=PRE) :: RRR, AKR, ZZZ, AKZ, DD, PSURR
    REAL(KIND=PRE) :: SIK, CSK, SQ, EPZ
    REAL(KIND=PRE) :: PD1X, PD2X, PD1Z, PD2Z

    RRR = NORM2(XI(1:2) - XJ(1:2))
    AKR = wavenumber*RRR

    ZZZ = XI(3) + XJ(3)
    AKZ = wavenumber*ZZZ

    DD  = SQRT(RRR**2 + ZZZ**2)

    IF ((DD > 1e-5) .AND. (wavenumber > 0)) THEN
      PSURR = PI/(wavenumber*DD)**3
    ELSE
      PSURR = 0.0
    ENDIF

    !================================================
    ! Evaluate PDnX and PDnZ depending on AKZ and AKR
    !================================================

    IF ((MINVAL(XZ) < AKZ) .AND. (AKZ < MAXVAL(XZ))) THEN

      IF ((MINVAL(XR) <= AKR) .AND. (AKR < MAXVAL(XR))) THEN

        IF (AKR < 1) THEN
          KI = INT(5*(LOG10(AKR+1e-20)+6)+1)
        ELSE
          KI = INT(3*AKR+28)
        ENDIF
        KI = MAX(MIN(KI, 327), 2)

        IF (AKZ < -1e-2) THEN
          KJ = INT(8*(LOG10(-AKZ)+4.5))
        ELSE
          KJ = INT(5*(LOG10(-AKZ)+6))
        ENDIF
        KJ = MAX(MIN(KJ, 45), 2)

        CALL LAGRANGE_POLYNOMIAL_INTERPOLATION   &
                (AKR, AKZ,                       &
                XR(KI-1:KI+1), XZ(KJ-1:KJ+1),    &
                APD(KI-1:KI+1, KJ-1:KJ+1, :, :), &
                PD1X, PD2X, PD1Z, PD2Z)

      ELSE  ! MAXVAL(XR) < AKR

        EPZ  = EXP(AKZ)
        SQ   = SQRT(2*PI/AKR)
        CSK  = COS(AKR-PI/4)
        SIK  = SIN(AKR-PI/4)

        PD1Z = PSURR*AKZ - PI*EPZ*SQ*SIK
        PD2Z =                EPZ*SQ*CSK

        IF (RRR > REAL(1e-5, KIND=PRE)) THEN
          PD1X = PI*EPZ*SQ*(CSK - 0.5*SIK/AKR) - PSURR*AKR
          PD2X =    EPZ*SQ*(SIK + 0.5*CSK/AKR)
        END IF

      ENDIF

      !====================================
      ! Deduce FS ans VS from PDnX and PDnZ
      !====================================

      FS    = -CMPLX(PD1Z, PD2Z, KIND=PRE)
      IF (depth == 0.0) THEN
        VS(3) = -CMPLX(PD1Z-PSURR*AKZ, PD2Z, KIND=PRE)
      ELSE
        VS(3) = -CMPLX(PD1Z, PD2Z, KIND=PRE)
      END IF

      IF (RRR > 1e-5) THEN
        IF (depth == 0.0) THEN
          VS(1) = (XI(1) - XJ(1))/RRR * CMPLX(PD1X+PSURR*AKR, PD2X, KIND=PRE)
          VS(2) = (XI(2) - XJ(2))/RRR * CMPLX(PD1X+PSURR*AKR, PD2X, KIND=PRE)
        ELSE
          VS(1) = (XI(1) - XJ(1))/RRR * CMPLX(PD1X, PD2X, KIND=PRE)
          VS(2) = (XI(2) - XJ(2))/RRR * CMPLX(PD1X, PD2X, KIND=PRE)
        END IF
      ELSE
        VS(1:2) = CMPLX(0.0, 0.0, KIND=PRE)
      END IF

    ELSE ! AKZ < MINVAL(XZ)
      FS      = CMPLX(-PSURR*AKZ, 0.0, KIND=PRE)
      VS(1:3) = CMPLX(0.0, 0.0, KIND=PRE)
    ENDIF

    RETURN
  END SUBROUTINE COMPUTE_INTEGRAL_WRT_THETA

  ! =========================

  SUBROUTINE WAVE_PART_INFINITE_DEPTH &
      (wavenumber, X0I, X0J,          &
      XR, XZ, APD,                    &
      SP, VSP)
    ! Compute the frequency-dependent part of the Green function in the infinite depth case.
    ! This is basically just the integral computed by the subroutine above.

    ! Inputs
    REAL(KIND=PRE),                           INTENT(IN)  :: wavenumber
    REAL(KIND=PRE), DIMENSION(3),             INTENT(IN)  :: X0I   ! Coordinates of the source point
    REAL(KIND=PRE), DIMENSION(3),             INTENT(IN)  :: X0J   ! Coordinates of the center of the integration panel

    ! Tabulated data
    REAL(KIND=PRE), DIMENSION(328),           INTENT(IN) :: XR
    REAL(KIND=PRE), DIMENSION(46),            INTENT(IN) :: XZ
    REAL(KIND=PRE), DIMENSION(328, 46, 2, 2), INTENT(IN) :: APD

    ! Outputs
    COMPLEX(KIND=PRE),               INTENT(OUT) :: SP  ! Integral of the Green function over the panel.
    COMPLEX(KIND=PRE), DIMENSION(3), INTENT(OUT) :: VSP ! Gradient of the integral of the Green function with respect to X0I.

    ! Local variables
    REAL(KIND=PRE)               :: ADPI, ADPI2, AKDPI, AKDPI2
    REAL(KIND=PRE), DIMENSION(3) :: XI

    XI(:) = X0I(:)
    CALL COMPUTE_INTEGRAL_WRT_THETA(XI, X0J, INFINITE_DEPTH, wavenumber, XR, XZ, APD, SP, VSP(:))

    ADPI2  = wavenumber/(2*PI**2)
    ADPI   = wavenumber/(2*PI)
    AKDPI2 = wavenumber**2/(2*PI**2)
    AKDPI  = wavenumber**2/(2*PI)

    SP  = CMPLX(REAL(SP)*ADPI2,   AIMAG(SP)*ADPI,   KIND=PRE)
    VSP = CMPLX(REAL(VSP)*AKDPI2, AIMAG(VSP)*AKDPI, KIND=PRE)

    RETURN
  END SUBROUTINE WAVE_PART_INFINITE_DEPTH

  ! ======================

  SUBROUTINE WAVE_PART_FINITE_DEPTH &
      (wavenumber, X0I, X0J, depth, &
      XR, XZ, APD,                  &
      NEXP, REF_AMBDA, REF_AR,      &
      SP, VSP_SYM, VSP_ANTISYM)
    ! Compute the frequency-dependent part of the Green function in the finite depth case.

    ! Inputs
    REAL(KIND=PRE),                           INTENT(IN) :: wavenumber, depth
    REAL(KIND=PRE), DIMENSION(3),             INTENT(IN) :: X0I  ! Coordinates of the source point
    REAL(KIND=PRE), DIMENSION(3),             INTENT(IN) :: X0J  ! Coordinates of the center of the integration panel

    REAL(KIND=PRE), DIMENSION(328),           INTENT(IN) :: XR
    REAL(KIND=PRE), DIMENSION(46),            INTENT(IN) :: XZ
    REAL(KIND=PRE), DIMENSION(328, 46, 2, 2), INTENT(IN) :: APD

    INTEGER,                                  INTENT(IN) :: NEXP
    REAL(KIND=PRE), DIMENSION(NEXP),          INTENT(IN) :: REF_AMBDA, REF_AR

    ! Outputs
    COMPLEX(KIND=PRE),               INTENT(OUT) :: SP  ! Integral of the Green function over the panel.
    COMPLEX(KIND=PRE), DIMENSION(3), INTENT(OUT) :: VSP_SYM, VSP_ANTISYM ! Gradient of the integral of the Green function with respect to X0I.

    ! Local variables
    INTEGER                              :: KE
    REAL(KIND=PRE)                       :: AMH, AKH, A, COF1, COF2, COF3, COF4
    REAL(KIND=PRE)                       :: AQT, RRR
    REAL(KIND=PRE),    DIMENSION(3)      :: XI, XJ
    REAL(KIND=PRE),    DIMENSION(4)      :: FTS, PSR
    REAL(KIND=PRE),    DIMENSION(3, 4)   :: VTS
    REAL(KIND=PRE),    DIMENSION(NEXP+1) :: AMBDA, AR
    COMPLEX(KIND=PRE), DIMENSION(4)      :: FS
    COMPLEX(KIND=PRE), DIMENSION(3, 4)   :: VS

    !========================================
    ! Part 1: Solve 4 infinite depth problems
    !========================================

    XI(:) = X0I(:)
    XJ(:) = X0J(:)

    ! Distance in xOy plane
    RRR = NORM2(XI(1:2) - XJ(1:2))

    ! 1.a First infinite depth problem
    CALL COMPUTE_INTEGRAL_WRT_THETA(XI(:), XJ(:), depth, wavenumber, XR, XZ, APD, FS(1), VS(:, 1))

    PSR(1) = PI/(wavenumber*SQRT(RRR**2+(XI(3)+XJ(3))**2))

    ! 1.b Shift and reflect XI and compute another value of the Green function
    XI(3) = -X0I(3) - 2*depth
    XJ(3) =  X0J(3)
    CALL COMPUTE_INTEGRAL_WRT_THETA(XI(:), XJ(:), depth, wavenumber, XR, XZ, APD, FS(2), VS(:, 2))
    VS(3, 2) = -VS(3, 2) ! Reflection of the output vector

    PSR(2) = PI/(wavenumber*SQRT(RRR**2+(XI(3)+XJ(3))**2))

    ! 1.c Shift and reflect XJ and compute another value of the Green function
    XI(3) =  X0I(3)
    XJ(3) = -X0J(3) - 2*depth
    CALL COMPUTE_INTEGRAL_WRT_THETA(XI(:), XJ(:), depth, wavenumber, XR, XZ, APD, FS(3), VS(:, 3))

    PSR(3) = PI/(wavenumber*SQRT(RRR**2+(XI(3)+XJ(3))**2))

    ! 1.d Shift and reflect both XI and XJ and compute another value of the Green function
    XI(3) = -X0I(3) - 2*depth
    XJ(3) = -X0J(3) - 2*depth
    CALL COMPUTE_INTEGRAL_WRT_THETA(XI(:), XJ(:), depth, wavenumber, XR, XZ, APD, FS(4), VS(:, 4))
    VS(3, 4) = -VS(3, 4) ! Reflection of the output vector

    PSR(4) = PI/(wavenumber*SQRT(RRR**2+(XI(3)+XJ(3))**2))

    ! Add up the results of the four problems
    SP               = -SUM(FS(1:4)) - SUM(PSR(1:4))
    VSP_SYM(1:3)     = -VS(1:3, 1) - VS(1:3, 4)
    VSP_ANTISYM(1:3) = -VS(1:3, 2) - VS(1:3, 3)

    ! Multiply by some coefficients
    AMH  = wavenumber*depth
    AKH  = AMH*TANH(AMH)
    A    = (AMH+AKH)**2/(depth*(AMH**2-AKH**2+AKH))
    COF1 = -A/(8*PI**2)
    COF2 = -A/(8*PI)
    COF3 = wavenumber*COF1
    COF4 = wavenumber*COF2

    SP          = CMPLX(REAL(SP)*COF1,          AIMAG(SP)*COF2, KIND=PRE)
    VSP_ANTISYM = CMPLX(REAL(VSP_ANTISYM)*COF3, AIMAG(VSP_ANTISYM)*COF4, KIND=PRE)
    VSP_SYM     = CMPLX(REAL(VSP_SYM)*COF3,     AIMAG(VSP_SYM)*COF4, KIND=PRE)

    !=====================================================
    ! Part 2: Integrate (NEXP+1)×4 terms of the form 1/MM'
    !=====================================================

    AMBDA(1:NEXP) = REF_AMBDA(1:NEXP)
    AMBDA(NEXP+1) = 0

    AR(1:NEXP) = REF_AR(1:NEXP)
    AR(NEXP+1) = 2

    DO KE = 1, NEXP+1
      XI(:) = X0I(:)

      ! 2.a Shift observation point and compute integral
      XI(3) =  X0I(3) + depth*AMBDA(KE) - 2*depth
      CALL COMPUTE_ASYMPTOTIC_RANKINE_SOURCE(XI(:), X0J(:), ONE, FTS(1), VTS(:, 1))

      ! 2.b Shift and reflect observation point and compute integral
      XI(3) = -X0I(3) - depth*AMBDA(KE)
      CALL COMPUTE_ASYMPTOTIC_RANKINE_SOURCE(XI(:), X0J(:), ONE, FTS(2), VTS(:, 2))
      VTS(3, 2) = -VTS(3, 2) ! Reflection of the output vector

      ! 2.c Shift and reflect observation point and compute integral
      XI(3) = -X0I(3) + depth*AMBDA(KE) - 4*depth
      CALL COMPUTE_ASYMPTOTIC_RANKINE_SOURCE(XI(:), X0J(:), ONE, FTS(3), VTS(:, 3))
      VTS(3, 3) = -VTS(3, 3) ! Reflection of the output vector

      ! 2.d Shift observation point and compute integral
      XI(3) =  X0I(3) - depth*AMBDA(KE) + 2*depth
      CALL COMPUTE_ASYMPTOTIC_RANKINE_SOURCE(XI(:), X0J(:), ONE, FTS(4), VTS(:, 4))

      AQT = -AR(KE)/(8*PI)

      ! Add all the contributions
      SP               = SP               + AQT*SUM(FTS(1:4))
      VSP_ANTISYM(1:3) = VSP_ANTISYM(1:3) + AQT*(VTS(1:3, 1) + VTS(1:3, 4))
      VSP_SYM(1:3)     = VSP_SYM(1:3)     + AQT*(VTS(1:3, 2) + VTS(1:3, 3))

    END DO

    RETURN
  END SUBROUTINE

  ! =====================================================================

  SUBROUTINE BUILD_MATRICES_WAVE_SOURCE  &
      (nb_faces_1, centers_1, normals_1, &
      nb_faces_2,                        &
      centers_2, areas_2,                &
      wavenumber, depth,                 &
      XR, XZ, APD,                       &
      NEXP, AMBDA, AR,                   &
      same_body,                         &
      S, V)

    ! Mesh data
    INTEGER,                                  INTENT(IN) :: nb_faces_1, nb_faces_2
    REAL(KIND=PRE), DIMENSION(nb_faces_1, 3), INTENT(IN) :: normals_1, centers_1
    REAL(KIND=PRE), DIMENSION(nb_faces_2, 3), INTENT(IN) :: centers_2
    REAL(KIND=PRE), DIMENSION(nb_faces_2),    INTENT(IN) :: areas_2

    REAL(KIND=PRE),                           INTENT(IN) :: wavenumber, depth

    ! Tabulated integrals
    REAL(KIND=PRE), DIMENSION(328),           INTENT(IN) :: XR
    REAL(KIND=PRE), DIMENSION(46),            INTENT(IN) :: XZ
    REAL(KIND=PRE), DIMENSION(328, 46, 2, 2), INTENT(IN) :: APD

    ! Prony decomposition for finite depth
    INTEGER,                                  INTENT(IN) :: NEXP
    REAL(KIND=PRE), DIMENSION(NEXP),          INTENT(IN) :: AMBDA, AR

    ! Trick to save some time
    LOGICAL,                                  INTENT(IN) :: same_body

    ! Output
    COMPLEX(KIND=PRE), DIMENSION(nb_faces_1, nb_faces_2), INTENT(OUT) :: S
    COMPLEX(KIND=PRE), DIMENSION(nb_faces_1, nb_faces_2), INTENT(OUT) :: V

    ! Local variables
    INTEGER                         :: I, J
    COMPLEX(KIND=PRE)               :: SP2
    COMPLEX(KIND=PRE), DIMENSION(3) :: VSP2_SYM, VSP2_ANTISYM

    IF (SAME_BODY) THEN
      ! If we are computing the influence of some cells upon themselves, the resulting matrices have some symmetries.
      ! This is due to the symmetry of the Green function, and the way the integral on the face is approximated.
      ! (More precisely, the Green function is symmetric and its derivative is the sum of a symmetric part and an anti-symmetric
      ! part.)

      DO I = 1, nb_faces_1
        !$OMP PARALLEL DO PRIVATE(J, SP2, VSP2_SYM, VSP2_ANTISYM)
        DO J = I, nb_faces_2

          IF (depth == INFINITE_DEPTH) THEN
            CALL WAVE_PART_INFINITE_DEPTH &
              (wavenumber,                &
              centers_1(I, :),            &
              centers_2(J, :),            &
              XR, XZ, APD,                &
              SP2, VSP2_SYM               &
              )
            VSP2_ANTISYM(:) = ZERO
          ELSE
            CALL WAVE_PART_FINITE_DEPTH   &
              (wavenumber,                &
              centers_1(I, :),            &
              centers_2(J, :),            &
              depth,                      &
              XR, XZ, APD,                &
              NEXP, AMBDA, AR,            &
              SP2, VSP2_SYM, VSP2_ANTISYM &
              )
          END IF

          S(I, J) = SP2*areas_2(J)
          V(I, J) = DOT_PRODUCT(normals_1(I, :),         &
                                VSP2_SYM + VSP2_ANTISYM) &
                                *areas_2(J)

          IF (.NOT. I==J) THEN
            VSP2_SYM(1:2) = -VSP2_SYM(1:2)
            S(J, I) = SP2*areas_2(I)
            V(J, I) = DOT_PRODUCT(normals_1(J, :),         &
                                  VSP2_SYM - VSP2_ANTISYM) &
                                  *areas_2(I)
          END IF

        END DO
        !$OMP END PARALLEL DO
      END DO

    ELSE
      ! General case: if we are computing the influence of a some cells on other cells, we have to compute all the coefficients.

      DO I = 1, nb_faces_1
        !$OMP PARALLEL DO PRIVATE(J, SP2, VSP2_SYM, VSP2_ANTISYM)
        DO J = 1, nb_faces_2

          IF (depth == INFINITE_DEPTH) THEN
            CALL WAVE_PART_INFINITE_DEPTH &
              (wavenumber,                &
              centers_1(I, :),            &
              centers_2(J, :),            &
              XR, XZ, APD,                &
              SP2, VSP2_SYM               &
              )
            VSP2_ANTISYM(:) = ZERO 
          ELSE
            CALL WAVE_PART_FINITE_DEPTH   &
              (wavenumber,                &
              centers_1(I, :),            &
              centers_2(J, :),            &
              depth,                      &
              XR, XZ, APD,                &
              NEXP, AMBDA, AR,            &
              SP2, VSP2_SYM, VSP2_ANTISYM &
              )
          END IF

          S(I, J) = SP2*areas_2(J)                                ! Green function
          V(I, J) = DOT_PRODUCT(normals_1(I, :),         &
                                VSP2_SYM + VSP2_ANTISYM) &
                                *areas_2(J) ! Gradient of the Green function

        END DO
        !$OMP END PARALLEL DO
      END DO
   END IF

  END SUBROUTINE

  ! =====================================================================

END MODULE GREEN_WAVE