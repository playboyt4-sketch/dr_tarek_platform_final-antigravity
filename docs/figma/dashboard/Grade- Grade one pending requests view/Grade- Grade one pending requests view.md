# Technical Specification: Student Request Review & Approval Dashboard

**Target Platform:** Tarek el araby Platform — Dashboard  
**Screen Name:** Grade- Grade one pending requests view  
**Canvas / Viewport Size:** 1280 × 800 px  
**Design Environment:** Figma Web / Desktop  

---

## 1. Design Tokens & Styles
* **Brand Primary (Amber / Orange):** `#F59E0B`
* **Surface / Cards Background:** `#FFFFFF`
* **Canvas Background:** `#F5F5F5`
* **Text Primary (Headings / Titles):** `#1F2937`
* **Text Secondary (Meta / Subtitles):** `#6B7280`
* **Toggle Active State (ON):** `#10B981`
* **Toggle Inactive State (OFF):** `#D1D5DB`
* **Border Radii:**
  * Capsules & Pills: `9999px` (All buttons, student card, status pills)
  * Overlays: `20px`

---

## 2. Layout & Component Hierarchy (1280 × 800)

### A. Header & Top Navigation
1. **Menu Hamburger Icon (`the menu ICON`):** `80 × 80 px` at `X: 80, Y: 24`
2. **Platform Title (`Tarek el araby Platform`):** `540 × 80 px` at `X: 370, Y: 24`
3. **Grade Navigation (`Grades nav icons`):** `660 × 40 px` at `X: 310, Y: 132`, Auto Layout Gap `4px`.
   * Active: `Grade One` (Solid Amber `#F59E0B`). Inactive: `Grade Two`, `Grade Three`, `Grade Four`.
4. **Sub-Navigation Tabs (`nav tool bar`):** `336 × 40 px` at `X: 472, Y: 190`.
   * Active: `Students` (Underlined). Inactive: `Subjects`.

---

### B. Student Information Card (`pending requests`)
* **Container:** `540 × 132 px` at `X: 370, Y: 240` | Shape: Pill (`Corner radius: 9999px`) | Stroke: `#F59E0B`.
* **Avatar (`avatar`):** `100 × 100 px` at `X: 16, Y: 16`.
* **Student Name (`name`):** `392 × 60 px` at `X: 132, Y: 20` ("Ahmed Gamal mousa", Bold).
* **Metadata (`student information`):** Auto Layout Horizontal, `384 Hug × 24 Hug px` at `X: 132, Y: 80`, Gap `8px`.
  * Phone: `01101011588` • Grade: `Grade One` • Date: `15/9/2026` • Device: `Iphone 17 pro`.

---

### C. Review Stepper Action Bar (`Center student bar`)
* **Container:** `1120 Hug × 60 Hug px` at `X: 80, Y: 392` | Auto Layout Gap `40px`.
* **Center Flow (`Center Student Nav`):** Shows 4 buttons (`250 × 60 px` each):
  1. `Student Type`
  2. `Student Subjects`
  3. `Student Plan`
  4. `Other Subjects`
* **Public Flow (`publicStudent Nav`):** Shows only 2 buttons (`250 × 60 px` each):
  1. `Student Type`
  2. `Student Subjects`
  *(Note: `Student Plan` and `Other Subjects` are completely removed from view).*

---

### D. Bottom Decision Bar (`Frame 92`)
* **Container:** Centered horizontally at bottom (`X: ~460, Y: 710`), Auto Layout Gap `24px`.
* **Buttons:**
  1. **Approve Button (`Approve`):** Solid Amber Fill `#F59E0B`, White text, Pill radius `9999px`.
  2. **Reject Button (`Reject`):** Outlined Pill (`Corner radius: 9999px`), Stroke `#F59E0B`.

---

## 3. Overlays Specifications

### 1. `Student Type` Overlay
* **Dimensions:** `380 × 220 px`, Spacing `24px`, `Clip content: true`.
* **Selector (`160 × 32 px`):** `Center` vs `Public`.
* **States & Transition:** `Swap overlay` with `Smart animate` (`150ms`).
* **Confirm Button:** `Save` (`160 × 32 px`) triggers `Close overlay`.

### 2. `Student Plan` Overlay (Center Only)
* **Dimensions:** `328 × 220 px`, Spacing `24px`, `Clip content: true`.
* **Selector (`plans`):** `280 × 40 px` at `X: 24, Y: 92`, Gap `4px` (`FREE` | `PRO` | `MAX`).
* **States & Transition:** Bidirectional `Swap overlay` with `Smart animate` (`150ms`).
* **Confirm Button:** `Save` (`160 × 32 px`) triggers `Close overlay`.

### 3. `Grade One Subjects` Overlay
* **Dimensions:** `380 × 416 px`, Spacing `16px`, `Clip content: true`.
* **Rows:** 6 Accounting subjects with Toggle Switches (Default: ON / Green `#10B981`).
* **Confirm Button:** `Save` (`160 × 32 px`) triggers `Close overlay`.

### 4. `Other Subjects` Overlay (Center Only)
* **Dimensions:** Width `380px`, Max Height `480px` with internal **Vertical Scrolling**.
* **Content:** Subjects from previous 4 academic grades with individual toggle switches.
* **Confirm Button:** Fixed `Save` button at bottom triggers `Close overlay`.

---

## 4. Business Logic & State Machine