import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/asset_paths.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/glass_back_button.dart';
import '../../../../core/widgets/primary_button.dart';
import '../providers/registration_form_provider.dart';
import 'new_student_number_screen.dart';

// User-facing strings are plain literals, matching the already-built
// sibling screens (User Type Selection, Welcome), which do not use a
// localization layer yet. Do NOT introduce intl/AppLocalizations in this
// screen alone — that would diverge from its siblings.
// OPEN ITEM (03 UI & UX, Section 4, item 10): all supplied Figma frames are
// English LTR while FINAL_DECISIONS requires Arabic RTL support. Whether
// the shipped app is Arabic RTL or bilingual is unresolved and affects
// every screen; the forced-LTR Directionality below mirrors the siblings
// until the Teacher decides.

// ---------------------------------------------------------------------------
// Design constants for the "New Student - name" step (Figma node 38:43).
// Raw design-pixel values from Figma dev mode, consumed exclusively via
// context.rs() / context.rsV() — identical to Figma at the 393x852
// reference, proportionally preserved elsewhere. Pattern mirrors
// NewStudentWelcomeScreen (node 35:18): Scaffold + SafeArea +
// SingleChildScrollView + ConstrainedBox(minHeight: viewportHeight) +
// SizedBox(393x852) + Stack of exact Positioned coordinates.
// ---------------------------------------------------------------------------
abstract final class _NameDesign {
  // Canvas
  static const canvasWidth = 393.0;
  static const canvasHeight = 852.0;

  // Illustration panel: 369x344 at (12, 50), corner radius 35.
  static const illustrationX = 12.0;
  static const illustrationY = 50.0;
  static const illustrationWidth = 369.0;
  static const illustrationHeight = 344.0;
  static const illustrationRadius = 35.0;

  // Floating back button: 44x44 at (24, 64) over the illustration.
  static const backButtonX = 24.0;
  static const backButtonY = 64.0;
  static const backButtonSize = 44.0;

  // Headline frame: 393 wide at y426 ("What's your name?").
  static const titleY = 426.0;

  // Input field outer box: 369 wide at (12, 608), ~69px tall.
  static const fieldX = 12.0;
  static const fieldY = 608.0;
  static const fieldWidth = 369.0;

  // Primary CTA: 345 wide at (24, 754), Style = Solid.
  static const buttonX = 24.0;
  static const buttonY = 754.0;
  static const buttonWidth = 345.0;
}

/// Screen 3.3 — New Student Full Name (Registration step 2).
///
/// Collects `users.full_name` (04 Features, Registration step 2; 05
/// Database `users.full_name`).
///
/// Geometry reference (Figma raw export, 393x852 canvas, node 38:43):
/// illustration 369x344 @ (12, 50) radius 35, title 393 wide @ y426,
/// field 369x69 @ (12, 608), button 345 @ (24, 754),
/// back button 44 @ (24, 64) as an overlay on the illustration.
///
/// The simulated OS status bar in the Figma export ("9:41" / battery,
/// 0-50 canvas chrome) is NOT reproduced — the OS draws the real status
/// bar and [SafeArea] already insets for it.
///
/// On "Next": the `Form` validates, `fullName` is written into the shared
/// [registrationFormProvider] draft, then the flow pushes
/// [NewStudentNumberScreen] (Registration step 3). No Cloud Function is
/// called here: per 04 Features, the account is created only after the
/// Password step.
class NewStudentNameScreen extends ConsumerStatefulWidget {
  /// Value already collected earlier in the flow (forward/back navigation).
  /// The field is seeded from it once and never overwritten with an empty
  /// string on rebuild; when null, the shared registration draft is used.
  final String? initialFullName;

  const NewStudentNameScreen({super.key, this.initialFullName});

  static const Color backgroundColor = Color(0xFFFFFCF7);

  @override
  ConsumerState<NewStudentNameScreen> createState() =>
      _NewStudentNameScreenState();
}

class _NewStudentNameScreenState extends ConsumerState<NewStudentNameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seed once: explicit constructor value wins, otherwise resume whatever
    // the draft already holds (e.g. user went back from the Number step).
    // Controller text is local UI state; business state lives in the draft.
    if (!_seeded) {
      _seeded = true;
      final seed =
          widget.initialFullName ?? ref.read(registrationFormProvider).fullName;
      if (seed.isNotEmpty) {
        _nameController.text = seed;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 03 UI & UX, Section 3.3: non-empty required. Exact error copy is TBD
  /// by the Teacher/copy owner — "Full name is required." is the minimal
  /// placeholder, not invented marketing copy.
  String? _validateFullName(String? value) {
    if ((value ?? '').trim().isEmpty) {
      return 'Full name is required.';
    }
    // OPEN ITEM (03 UI & UX, Section 3.3): no max length is specified in
    // the approved docs. 100 chars is a sane input cap, NOT an approved
    // business rule — flag for Teacher confirmation before treating it as
    // one. Enforced both by the validator (message path, testable) and by
    // `maxLength` (hard cap on the field itself).
    if (value!.trim().length > 100) {
      return 'Full name must be at most 100 characters.';
    }
    return null;
  }

  void _onNextPressed() {
    if (!_formKey.currentState!.validate()) return;
    final fullName = _nameController.text.trim();
    ref.read(registrationFormProvider.notifier).setFullName(fullName);
    // Submission happens only after the Password step (04 Features,
    // Registration step 7) — deliberately no backend call here, so this
    // screen never touches Firestore/Auth (Master Architecture, Section 5).
    if (!mounted) return;
    Navigator.of(context).push(
      // Figma interaction: push-left, 300ms, EaseOut — the platform
      // MaterialPageRoute transition (matches the sibling steps).
      MaterialPageRoute(
        builder: (_) => NewStudentNumberScreen(initialFullName: fullName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Same viewport math as the Welcome screen: the fixed 393x852 Stack
    // lives INSIDE the SafeArea, so Figma's y-coords (measured from the
    // canvas top, status-bar chrome included) land correctly without any
    // manual top/bottom padding to tune.
    final viewportHeight = MediaQuery.of(context).size.height -
        MediaQuery.of(context).padding.vertical;

    return Scaffold(
      backgroundColor: NewStudentNameScreen.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: viewportHeight),
            child: Directionality(
              // Force LTR — English-only screen (see file-level OPEN ITEM).
              textDirection: TextDirection.ltr,
              child: SizedBox(
                width: context.rs(_NameDesign.canvasWidth),
                height: context.rsV(_NameDesign.canvasHeight),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // --- 1. Illustration panel (Figma 12,50 369x344 r35).
                    // BoxFit.cover crops cleanly to the box — never
                    // BoxFit.fill, which stretches the art.
                    Positioned(
                      left: context.rs(_NameDesign.illustrationX),
                      top: context.rsV(_NameDesign.illustrationY),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          context.rs(_NameDesign.illustrationRadius),
                        ),
                        child: SizedBox(
                          key: const Key('nameIllustrationStack'),
                          width: context.rs(_NameDesign.illustrationWidth),
                          height:
                              context.rsV(_NameDesign.illustrationHeight),
                          child: Image.asset(
                            AssetImages.newStudentNamePhoto,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              color: AppColors.itemSurface,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.image_not_supported_outlined,
                                size: 64,
                                color: AppColors.mediumGray,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // --- Back button (Figma 24,64 44x44, asset button/back).
                    Positioned(
                      left: context.rs(_NameDesign.backButtonX),
                      top: context.rsV(_NameDesign.backButtonY),
                      child: SizedBox(
                        width: context.rs(_NameDesign.backButtonSize),
                        height: context.rs(_NameDesign.backButtonSize),
                        child: const _NameBackButton(),
                      ),
                    ),

                    // --- 2. Headline (Figma y426, 393 wide, centered).
                    Positioned(
                      top: context.rsV(_NameDesign.titleY),
                      left: 0,
                      right: 0,
                      child: Text(
                        "What's your name?",
                        key: const Key('nameTitle'),
                        textAlign: TextAlign.center,
                        style: AppTypography.titleLarge(
                          context,
                          color: AppColors.darkText,
                        ),
                      ),
                    ),

                    // --- 3. Full Name field (Figma 12,608 w369, ~69px box).
                    // FONT: Figma exports Inter 20px for BOTH the
                    // 'Full Name' label and the 'Enter your full name'
                    // hint — reproduced here as the shared
                    // AppTypography.bodyRegular size for both, in
                    // Figma's #9A9A9A gray, LEFT-aligned
                    // (floatingLabelAlignment.start + textAlign.start).
                    Positioned(
                      left: context.rs(_NameDesign.fieldX),
                      top: context.rsV(_NameDesign.fieldY),
                      child: SizedBox(
                        width: context.rs(_NameDesign.fieldWidth),
                        child: Form(
                          key: _formKey,
                          child: TextFormField(
                            key: const Key('nameField'),
                            controller: _nameController,
                            keyboardType: TextInputType.name,
                            textInputAction: TextInputAction.next,
                            textAlign: TextAlign.start,
                            autofillHints: const [AutofillHints.name],
                            maxLength: 100,
                            buildCounter: (
                              context, {
                              required int currentLength,
                              required bool isFocused,
                              required int? maxLength,
                            }) =>
                                const SizedBox.shrink(),
                            onFieldSubmitted: (_) => _onNextPressed(),
                            style: AppTypography.bodyRegular(
                              context,
                              color: AppColors.darkText,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Full Name',
                              hintText: 'Enter your full name',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                              floatingLabelAlignment:
                                  FloatingLabelAlignment.start,
                              labelStyle: AppTypography.bodyRegular(
                                context,
                                color: const Color(0xFF9A9A9A),
                              ),
                              floatingLabelStyle: AppTypography.bodyRegular(
                                context,
                                color: const Color(0xFF9A9A9A),
                              ),
                              hintStyle: AppTypography.bodyRegular(
                                context,
                                color: const Color(0xFF9A9A9A),
                              ),
                              // FIXED ~69px field height (intentional):
                              // vertical padding resolves the box to
                              // Figma's bordered-container height.
                              // Kept FIXED (not height-scaled) because a
                              // single-line input is fixed UI chrome.
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 23,
                              ),
                              // RADIUS CONFLICT (Teacher decision needed):
                              // design_system.md ("حقول الإدخال" =
                              // radiusMedium/md) requires 16px — used
                              // here via AppShapes.radiusMd. The raw
                              // Figma export for THIS screen showed 12px.
                              // 16px chosen per the design-system
                              // input-field rule; confirm which source
                              // wins.
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppShapes.radiusMd,
                                ),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE5E7EB),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppShapes.radiusMd,
                                ),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE5E7EB),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppShapes.radiusMd,
                                ),
                                borderSide: const BorderSide(
                                  color: AppColors.buttonSolid,
                                  width: 1.5,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppShapes.radiusMd,
                                ),
                                borderSide: const BorderSide(
                                  color: AppColors.error,
                                ),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppShapes.radiusMd,
                                ),
                                borderSide: const BorderSide(
                                  color: AppColors.error,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            validator: _validateFullName,
                          ),
                        ),
                      ),
                    ),

                    // --- 4. Primary CTA (Figma 24,754 w345, Style = Solid).
                    Positioned(
                      left: context.rs(_NameDesign.buttonX),
                      top: context.rsV(_NameDesign.buttonY),
                      child: SizedBox(
                        width: context.rs(_NameDesign.buttonWidth),
                        child: PrimaryButton(
                          label: 'Next',
                          variant: ButtonVariant.solid,
                          onPressed: _onNextPressed,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin adapter so the overlay back button can be `const` inside the
/// illustration `Stack` while keeping the pop behavior identical.
class _NameBackButton extends StatelessWidget {
  const _NameBackButton();

  @override
  Widget build(BuildContext context) {
    return GlassBackButton(
      onTap: () => Navigator.of(context).maybePop(),
    );
  }
}
