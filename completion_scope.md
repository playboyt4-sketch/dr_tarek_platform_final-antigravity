# Completion Scope

## Source of truth

Implementation follows `docs/notion/00_MASTER_ARCHITECTURE.md`, approved `04_FEATURES.md`, `05_DATABASE.md`, and `FINAL_DECISIONS.md`. Presentation-final work for features other than Authentication is blocked because `03_UI_UX.md` is still Draft and the real Figma screens are not supplied.

## Current gaps identified

1. The Flutter custom-token data source expects `customToken`, while `verifyPhonePassword` returns `token`.
2. Flutter registration is declared in the domain contract but `AuthRepositoryImpl.register` throws `UnimplementedError`.
3. No registration callable exists in `functions/src/index.ts`; the onboarding screens are static and their actions are empty.
4. `app_router.dart` is empty; `AuthGate` sends authenticated users to a placeholder rather than a feature dashboard.
5. Device binding client code exists and can be invoked after custom-token sign-in, but the login screen does not invoke it.
6. Approval and plan activation logic already exists in `onStudentApproved`; registration should create a `new_student` with pending approval and leave `student_type` for the approval/admin workflow.

## First implementation slice

Complete the functional Feature 01 foundation: registration callable with scrypt password hashing consistent with existing login verification, client registration data source/repository/use case/provider, onboarding navigation/state, token response compatibility, and post-login device validation. Do not invent final Dashboard visuals or other feature UI while their Figma specifications remain blocked.
