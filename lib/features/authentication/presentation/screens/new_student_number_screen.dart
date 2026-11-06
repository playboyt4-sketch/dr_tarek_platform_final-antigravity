import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/asset_paths.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/validators/egyptian_phone.dart';
import '../../../../core/widgets/glass_back_button.dart';
import '../../../../core/widgets/primary_button.dart';
import '../providers/registration_form_provider.dart';
import 'new_student_photo_screen.dart';

// User-facing strings are plain literals, matching the already-built
// sibling screens (User Type Selection, Welcome, Name), which do not use a
// localization layer yet. Do NOT introduce intl/AppLocalizations in this
// screen alone — that would diverge from its siblings.
// OPEN ITEM (03 UI & UX, Section 4, item 10): all supplied Figma frames are
// English LTR while FINAL_DECISIONS requires Arabic RTL support. Whether
// the shipped app is Arabic RTL or bilingual is unresolved and affects
// every screen; the forced-LTR Directionality below mirrors the siblings
// until the Teacher decides.

// ---------------------------------------------------------------------------
// Design constants for the "New Student - number" step (Figma node
// "New Student - number").
// Raw design-pixel values from Figma dev mode, consumed exclusively via
// context.rs() / context.rsV() — identical to Figma at the 393x852
// reference, proportionally preserved elsewhere. Pattern mirrors
// NewStudentWelcomeScreen and NewStudentNameScreen: Scaffold + SafeArea +
// SingleChildScrollView + ConstrainedBox(minHeight: viewportHeight) +
// SizedBox(393x852) + Stack of exact Positioned coordinates.
// ---------------------------------------------------------------------------
abstract final class _NumberDesign {
  // Canvas
  static const canvasWidth = 393.0;
  static const canvasHeight = 852.0;

  // Illustration panel: 369x355 at (12, 50), corner radius 35.
  static const illustrationX = 12.0;
  static const illustrationY = 50.0;
  static const illustrationWidth = 369.0;
  static const illustrationHeight = 355.0;
  static const illustrationRadius = 35.0;

  // Floating back button: 44x44 at (24, 64) over the illustration.
  static const backButtonX = 24.0;
  static const backButtonY = 64.0;
  static const backButtonSize = 44.0;

  // Headline frame: 393 wide at y437 ("Your phone number?").
  static const titleY = 437.0;

  // Phone field outer box: 345 wide at (24, 608), ~69px tall.
  static const fieldX = 24.0;
  static const fieldY = 608.0;
  static const fieldWidth = 345.0;

  // Primary CTA: 345 wide at (24, 754), Style = Solid.
  static const buttonX = 24.0;
  static const buttonY = 754.0;
  static const buttonWidth = 345.0;
}

/// Screen — New Student Phone Number (Registration step 3).
///
/// Collects `users.phone_number` (04 Features, Registration Main Flow
/// step 3; 05 Database `users.phone_number`, unique). Layout: illustration
/// panel → headline "Your phone number?" → single phone field → primary
/// "Next" button (03 UI & UX, Section 3.4; Figma `New Student - number`).
///
/// Geometry reference (Figma raw export, 393x852 canvas,
/// node "New Student - number"): illustration 369x355 @ (12, 50)
/// radius 35, title 393 wide @ y437, phone field 345 @ (24, 608),
/// button 345 @ (24, 754), back button 44 @ (24, 64) as a SIBLING
/// Positioned on the page Stack (offset 12,14 from the illustration),
/// NOT nested inside the art box — same as the Welcome screen.
///
/// The simulated OS status bar in the Figma export ("9:41" / battery,
/// 0-50 canvas chrome) is NOT reproduced — the OS draws the real status
/// bar and [SafeArea] already insets for it. The label is a native
/// floating label straddling the top border (caption/small, mediumGray)
/// — Flutter's [OutlineInputBorder] draws the notch automatically, so no
/// manual background-patch hack is used.
///
/// On "Next": the `Form` validates the Egyptian format client-side, the
/// value is written into the shared [registrationFormProvider] draft, then
/// the flow pushes [NewStudentPhotoScreen] (Registration step 4). No Cloud
/// Function is called here: per 04 Features, the account is created only
/// after the Password step.
class NewStudentNumberScreen extends ConsumerStatefulWidget {
  /// Values already collected earlier in the flow (forward/back
  /// navigation). The field is seeded from [initialPhoneNumber] once (falling
  /// back to the shared registration draft) and never overwritten with an
  /// empty string on rebuild; [initialFullName] is carried forward so going
  /// back never loses the Full Name step value.
  final String? initialFullName;
  final String? initialPhoneNumber;

  const NewStudentNumberScreen({
    super.key,
    this.initialFullName,
    this.initialPhoneNumber,
  });

  static const Color backgroundColor = Color(0xFFFFFCF7);

  @override
  ConsumerState<NewStudentNumberScreen> createState() =>
      _NewStudentNumberScreenState();
}

class _NewStudentNumberScreenState
    extends ConsumerState<NewStudentNumberScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seed once: explicit constructor value wins, otherwise resume whatever
    // the draft already holds (e.g. user went back from the Photo step).
    // Controller text is local UI state; business state lives in the draft.
    if (!_seeded) {
      _seeded = true;
      final seed =
          widget.initialPhoneNumber ??
          ref.read(registrationFormProvider).phoneNumber;
      if (seed.isNotEmpty) {
        _phoneController.text = seed;
      }
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  /// 08 Development Standards, Section 2.1 + 04 Features preconditions:
  /// Egyptian mobile format — starts with 010/011/012/015, 11 digits total,
  /// no country code in V1 (shared [egyptianPhoneRegExp] convention; `+20…`
  /// forms are rejected). Exact error copy is TBD by the Teacher/copy
  /// owner — the messages below are minimal placeholders, not invented
  /// marketing copy.
  String? _validatePhoneNumber(String? value) {
    final phone = normalizeEgyptianPhone(value ?? '');
    if (phone.isEmpty) {
      return 'Phone number is required.';
    }
    if (!isValidEgyptianPhone(phone)) {
      return 'Enter a valid Egyptian mobile number (e.g. 01001234567).';
    }
    return null;
  }

  void _onNextPressed() {
    if (!_formKey.currentState!.validate()) return;
    final phone = normalizeEgyptianPhone(_phoneController.text);
    ref.read(registrationFormProvider.notifier).setPhoneNumber(phone);
    // OPEN ITEM (04 Features Preconditions: "the phone number is not
    // already registered"): server-side uniqueness is enforced at FINAL
    // submission (`registerNewStudent` → `FailureCode.phoneAlreadyExists`).
    // No phone-uniqueness repository/use case exists in the codebase yet,
    // so no availability check is performed here — deliberately no
    // Firestore/Auth access from this widget (Master Architecture,
    // Section 5; 07 Flutter Architecture: Presentation never touches
    // Firebase). A per-step availability check can be wired here once the
    // Teacher approves the use case.
    if (!mounted) return;
    final draft = ref.read(registrationFormProvider);
    final fullName = widget.initialFullName ?? draft.fullName;
    Navigator.of(context).push(
      // Figma interaction: push-left, 300ms, EaseOut — the platform
      // MaterialPageRoute transition (matches the sibling steps).
      MaterialPageRoute(
        builder: (_) => NewStudentPhotoScreen(
          initialFullName: fullName.isEmpty ? null : fullName,
          initialPhoneNumber: phone,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Same viewport math as the Welcome/Name screens: the fixed 393x852
    // Stack lives INSIDE the SafeArea, so Figma's y-coords (measured from
    // the canvas top, status-bar chrome included) land correctly without
    // any manual top/bottom padding to tune.
    final viewportHeight = MediaQuery.of(context).size.height -
        MediaQuery.of(context).padding.vertical;

    final semantic = AppSemanticColors.of(context);

    return Scaffold(
      backgroundColor: semantic.canvasWarm,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: viewportHeight),
            child: Directionality(
              // Force LTR — English-only screen (see file-level OPEN ITEM).
              textDirection: TextDirection.ltr,
              child: SizedBox(
                width: context.rs(_NumberDesign.canvasWidth),
                height: context.rsV(_NumberDesign.canvasHeight),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // --- 1. Illustration panel (Figma 12,50 369x355 r35).
                    // BoxFit.cover crops cleanly to the box — never
                    // BoxFit.fill, which stretches the art.
                    Positioned(
                      left: context.rs(_NumberDesign.illustrationX),
                      top: context.rsV(_NumberDesign.illustrationY),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          context.rs(_NumberDesign.illustrationRadius),
                        ),
                        child: SizedBox(
                          key: const Key('numberIllustrationStack'),
                          width: context.rs(_NumberDesign.illustrationWidth),
                          height: context.rsV(
                            _NumberDesign.illustrationHeight,
                          ),
                          child: Image.asset(
                            AssetImages.newStudentNumberPhoto,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (
                                  context,
                                  error,
                                  stackTrace,
                                ) => Container(
                                  color: semantic.surface,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.image_not_supported_outlined,
                                    size: 64,
                                    color: semantic.textSecondary,
                                  ),
                                ),
                          ),
                        ),
                      ),
                    ),

                    // --- Back button (Figma 24,64 44x44, sibling overlay).
                    // SIBLING Positioned on the page Stack (offset 12,14
                    // from the illustration) — same as the Welcome screen,
                    // NOT nested inside the art box.
                    Positioned(
                      left: context.rs(_NumberDesign.backButtonX),
                      top: context.rsV(_NumberDesign.backButtonY),
                      child: SizedBox(
                        width: context.rs(_NumberDesign.backButtonSize),
                        height: context.rs(_NumberDesign.backButtonSize),
                        child: const _NumberBackButton(),
                      ),
                    ),

                    // --- 2. Headline (Figma y437, 393 wide, centered).
                    Positioned(
                      top: context.rsV(_NumberDesign.titleY),
                      left: 0,
                      right: 0,
                      child: Text(
                        'Your phone number?',
                        key: const Key('numberTitle'),
                        textAlign: TextAlign.center,
                        style: AppTypography.titleLarge(
                          context,
                          color: semantic.textPrimary,
                        ),
                      ),
                    ),

                    // --- 3. Phone number field (Figma 24,608 w345, ~69px).
                    // FONT CONFLICT (Teacher decision needed): 11 Assets
                    // Section 4.1/5.2 uses `Cairo` in its examples while
                    // design_system.md mandates `Google Sans Flex`
                    // (Regular + Thin only). This screen uses the
                    // project-wired [AppTypography] (Google Sans Flex),
                    // consistent with the sibling auth screens — no raw
                    // "Inter"/"SF Pro" from the Figma export is used.
                    //
                    // MASK NOTE (03 UI & UX, Section 3.4 open
                    // recommendation `01xxxxxxxxx`): the `01…` shape is
                    // enforced structurally via the input formatters
                    // below (digits-only + 11-char cap) and surfaced in
                    // the validator's example; `hintText` stays exactly
                    // per the Figma frame ("Enter your phone number").
                    // Validation states: Default (enabledBorder) →
                    // Focused (focusedBorder) → Error (errorBorder via
                    // the `Form` validator) → Filled (dark input text
                    // style). The "already registered" error is a
                    // server-side response surfaced at final
                    // submission, never faked client-side (see
                    // [_onNextPressed] OPEN ITEM).
                    Positioned(
                      left: context.rs(_NumberDesign.fieldX),
                      top: context.rsV(_NumberDesign.fieldY),
                      child: SizedBox(
                        width: context.rs(_NumberDesign.fieldWidth),
                        child: Form(
                          key: _formKey,
                          child: TextFormField(
                            key: const Key('numberField'),
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            textAlign: TextAlign.start,
                            autofillHints: const [
                              AutofillHints.telephoneNumber,
                            ],
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(11),
                            ],
                            onFieldSubmitted: (_) => _onNextPressed(),
                            style: AppTypography.bodyRegular(
                              context,
                              color: semantic.textPrimary,
                            ),
                            decoration: InputDecoration(
                              // Native floating label straddling the
                              // top border with an automatic notch
                              // (Figma's background-patch technique,
                              // reproduced by Flutter's
                              // OutlineInputBorder — no manual patch
                              // here). Left-aligned per the Figma
                              // reference screenshots (both texts sit
                              // flush-left with a small inset).
                              labelText: 'phone number',
                              hintText: 'Enter your phone number',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                              floatingLabelAlignment:
                                  FloatingLabelAlignment.start,
                              // Label is genuinely captionSmall (smaller
                              // than the bodyRegular hint); both share
                              // Figma's #9A9A9A gray. NOTE: #9A9A9A
                              // differs slightly from the #9CA3AF
                              // previously used for the hint alone.
                              labelStyle: AppTypography.captionSmall(
                                context,
                                color: semantic.inputHint,
                              ),
                              floatingLabelStyle: AppTypography.captionSmall(
                                context,
                                color: semantic.inputHint,
                              ),
                              hintStyle: AppTypography.bodyRegular(
                                context,
                                color: semantic.inputHint,
                              ),
                              // FIXED 69px field height (intentional):
                              // vertical 22.5 resolves the box to exactly
                              // 69px (Figma's bordered-container height),
                              // measured via tester.getSize — do not
                              // "tidy" back to 18 without re-measuring.
                              // Kept FIXED (not height-scaled) because a
                              // single-line input is fixed UI chrome per
                              // touch-target conventions; only the
                              // whitespace gaps above scale.
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 22.5,
                              ),
                              // RADIUS CONFLICT (Teacher decision needed):
                              // design_system.md ("حقول الإدخال" =
                              // radiusMedium/md) requires 16px — used
                              // here via AppShapes.radiusMd. The raw
                              // Figma export for THIS screen showed 12px,
                              // and 11 Assets Section 5.4 maps
                              // `radiusMedium` -> 12 / `radiusLarge` -> 16
                              // (the codebase keeps both: legacy
                              // `radiusMedium` = 12, `radiusMd` = 16).
                              // 16px chosen per the design-system
                              // input-field rule; confirm which source
                              // wins.
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppShapes.radiusMd,
                                ),
                                borderSide: BorderSide(
                                  color: semantic.inputBorderSubtle,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppShapes.radiusMd,
                                ),
                                borderSide: BorderSide(
                                  color: semantic.inputBorderSubtle,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppShapes.radiusMd,
                                ),
                                borderSide: BorderSide(
                                  color: semantic.inputBorderFocused,
                                  width: 1.5,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppShapes.radiusMd,
                                ),
                                borderSide: BorderSide(
                                  color: semantic.error,
                                ),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppShapes.radiusMd,
                                ),
                                borderSide: BorderSide(
                                  color: semantic.error,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            validator: _validatePhoneNumber,
                          ),
                        ),
                      ),
                    ),

                    // --- 4. Primary CTA (Figma 24,754 w345, Style = Solid).
                    Positioned(
                      left: context.rs(_NumberDesign.buttonX),
                      top: context.rsV(_NumberDesign.buttonY),
                      child: SizedBox(
                        width: context.rs(_NumberDesign.buttonWidth),
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
/// page `Stack` while keeping the pop behavior identical.
class _NumberBackButton extends StatelessWidget {
  const _NumberBackButton();

  @override
  Widget build(BuildContext context) {
    return GlassBackButton(
      onTap: () => Navigator.of(context).pop(),
    );
  }
}
