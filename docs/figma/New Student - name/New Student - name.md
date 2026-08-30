### 📱 Screen 05: Student Name Entry (`New Student - name`) — APPROVED

#### 1. Frame & Canvas:
* **Dimensions:** `393px` (Width) × `852px` (Height).
* **Background Canvas:** `AppColors.white` (`#FFFFFF`).

#### 2. Header Section & Floating Controls:
* **Header Artwork (`New Student - name photo`):**
  * Dimensions: Width `369px` × Height `344px` (Top-center aligned at `X: 12`, `Y: 50`).
  * Corner Radius: `35px` on all 4 corners.
* **Floating Glass Back Button (`❖ button/back`):**
  * Dimensions: `44 × 44 px` circle (`radius/full`).
  * Position: `X: 24`, `Y: 64` (Top-left floating over illustration).
  * Material: Liquid Glass (`Fill: White 25%`, `Stroke: White 35%`, `Blur: 20px`).
  * Icon: White Chevron Left (`<`, `20px`).
  * Action: `OnTap` -> `Navigator.pop(context)` (`Push Right →`, `300ms`, `EaseOut`).

#### 3. Title & Input Form:
* **Question Title (`What's your name?`):**
  * Position: `Y: 426`, Height `67px`, Width `393px`.
  * TextStyle: `AppTypography.titleLarge` (`28px`, `Regular`, LineHeight `36px`).
  * Color: `AppColors.darkText` (`#111827`).
  * Alignment: Center (`TextAlign.center`).
* **Input Field (`full name`):**
  * Position: `Y: 590`, Height `87px`.
  * Label: `"Full Name"` (`body/regular` 14px, `#6B7280`).
  * Input Container: Width `345px`, Height `56px`, Corner Radius `16px` (`radius/md`), Outline `1px` `#E5E7EB`.
  * Hint / Placeholder: `"Enter your full name"` (`body/regular` 14px, `#9CA3AF`).

#### 4. Primary CTA Button (`Next`):
* **Component:** `❖ button/primary` (Variant: `Style = Solid`).
* **Label:** `"Next"` (`title/medium` 20px, White `#FFFFFF`).
* **Dimensions:** Width `345px` × Height `56px` (`radius/full` 9999px).
* **Position:** `X: 24`, `Y: 754` (Bottom centered with 24px margins).
* **Interaction:** `OnTap` -> Validates input text -> Navigates to `NewStudentNumberScreen` (`Push Left ←`, `300ms`, `EaseOut`).