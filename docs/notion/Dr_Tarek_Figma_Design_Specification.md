# Dr. Tarek Platform — Figma Design Specification
## Source: `education - os ui`

> **Purpose:** This document is an implementation reference extracted directly from the Figma file through Figma MCP.
>
> **Figma file key:** `N4XUVx81rLxVOADK5PB0Kd`
>
> **Target implementation:** Flutter / Material 3
>
> **Primary mobile canvas:** `393 × 852 px`
>
> **Important:** Values below are Figma values. Do not reinterpret them as arbitrary Flutter constants. Convert them to the project's responsive/layout system while preserving the visual result.

---

# 1. File Overview

| Property | Value |
|---|---|
| File | `education - os ui` |
| Page | `Page 1` |
| Page ID | `0:1` |
| Primary mobile frame | `393 × 852 px` |
| Primary target | Mobile / iPhone-sized UI |
| Primary implementation | Flutter |
| Design extraction | Figma MCP |

## Top-level frames / sections detected

| Node ID | Name | X | Y | W | H |
|---|---|---:|---:|---:|---:|
| `17:20` | Splash Screen-START | -885 | 23 | 393 | 852 |
| `28:11` | Splash Screen-END | -455 | 23 | 393 | 852 |
| `1:2` | User Type Selection | 66 | 31 | 393 | 852 |
| `35:18` | New Student - Welcome | 532 | 23 | 393 | 852 |
| `38:43` | New Student - name | 965 | 23 | 393 | 852 |
| `40:4` | New Student - number | 1398 | 23 | 393 | 852 |
| `41:14` | New Student - photo | 1831 | 23 | 393 | 852 |
| `44:98` | New Student - Gade | 2264 | 23 | 393 | 852 |
| `42:57` | New Student - password | 2697 | 23 | 393 | 852 |
| `44:108` | New Student - End | 3130 | 23 | 393 | 852 |
| `52:143` | current Student - sign in | 532 | 961 | 393 | 852 |
| `55:10` | Student - home | 2264 | 3960 | 393 | 852 |
| `134:697` | Student - home | 1005 | 961 | 393 | 852 |
| `168:287` | educational cinema carousel import section | -2381 | 3960 | 2122 | 1402 |
| `190:556` | avatar system import section | -259 | 3960 | 2122 | 957 |

---

# 2. Global Design Tokens Observed

## Canvas

- Standard mobile frame: **393 × 852**
- The UI is designed around a mobile viewport.
- Do not add desktop-specific UI to the mobile implementation.

## Main light background

```text
#FFFCF7
```

Observed on:
- Splash START
- Splash END
- User Type Selection
- New Student flow screens
- Current Student Sign In

## Common button blue

```text
#2563EB
```

Observed on:
- Get Started
- Next
- Finish
- Login

## Common input border

```text
#D0D0D0
```

## Common secondary input/placeholder text

```text
#9A9A9A
```

## Safe-area placeholder / top region in registration screens

```text
#D9D9D9
```

> This is a Figma visual placeholder named `Safe Area`; it should not automatically become a literal gray production status bar. Preserve the intended platform-safe-area behavior in Flutter.

## White / cream text

```text
#FFFCF7
```

## User Type Selection colors

New Student card:

```text
#FBCB3D
```

Old Student card:

```text
#E43639
```

## Carousel primary red

```text
#8C2323
```

## Carousel accent

```text
#FBBF24
```

## Avatar system light text

```text
#F5F7FC
```

## Avatar system translucent text

```text
rgba(245,247,252,0.6)
```

---

# 3. Typography

## Inter

Used throughout the registration and user-selection flows.

Observed weights:
- Regular
- Semi Bold
- Bold

Examples:

| Usage | Font | Weight | Size |
|---|---|---|---:|
| Main title `I am a` | Inter | Bold | 36 |
| Subtitle | Inter | Regular | 16 |
| Arabic user labels | Inter | Bold | 24 |
| Registration field labels | Inter | Regular | 20 |
| Registration action labels | Inter | Semi Bold | 32 |
| Welcome title | Inter | Bold | 48 |
| Welcome brand | Inter | Regular | 32 |
| Welcome subtitle | Inter | Regular | 24 |
| Login | Inter | Bold | 24 |
| Forgot password | Inter | Regular | 12 |

## Gardenia Summer

Used for signature/brand text.

Observed:
- `Tarek el araby`
- `tarek el araby`
- Font size: **128 px**
- Splash text height: **172 px**

## Cairo

Used heavily by the imported educational carousel and avatar system.

Observed:
- Regular
- Bold
- ExtraBold

Carousel:
- Course title: Cairo Bold, 20 px
- Metadata: Cairo Regular, 11 px
- Start button: Cairo Bold, 20 px

Avatar system:
- Main title: Cairo ExtraBold, 26 px
- Group labels: Cairo Bold, 13 px
- Badge text: Cairo ExtraBold, 10.5 px

## Freestyle Script

Used for:

```text
Tarek El Araby
```

inside the main course card.

Observed size:

```text
20 px
```

---

# 4. Screen: Splash Screen-START

**Node:** `17:20`

**Frame:** `393 × 852`

## Background

```text
#FFFCF7
```

## Text

Node:

```text
26:7
```

Text:

```text
Tarek el araby
```

Position:

```text
X: 0
Y: 314
W: 393
H: 172
```

Typography:

```text
Font: Gardenia Summer Regular
Size: 128 px
Color: #000000
Alignment: Center
Opacity: 0
```

### Implementation state

The Figma START state explicitly has:

```text
opacity = 0
```

Therefore the text is invisible in the captured START state.

---

# 5. Screen: Splash Screen-END

**Node:** `28:11`

**Frame:** `393 × 852`

## Background

```text
#FFFCF7
```

## Text

Node:

```text
28:13
```

Text:

```text
Tarek el araby
```

Position:

```text
X: 0
Y: 314
W: 393
H: 172
```

Typography:

```text
Font: Gardenia Summer Regular
Size: 128 px
Color: #000000
Alignment: Center
Opacity: 100%
```

---

# 6. Screen: User Type Selection

**Node:** `1:2`

**Frame:** `393 × 852`

## Background

```text
#FFFCF7
```

## Main title

Node:

```text
3:3
```

Text:

```text
I am a
```

Position:

```text
center X ≈ 200.5
Y: 80
W: 169
H: 41
```

Typography:

```text
Inter Bold
36 px
Black
Center
```

## Subtitle

Node:

```text
5:5
```

Text:

```text
Select one that applies to you
```

Position:

```text
center X ≈ 197
Y: 129
W: 302
H: 20
```

Typography:

```text
Inter Regular
16 px
Black
Center
```

## New Student Card

Node:

```text
6:7
```

Frame:

```text
X: 24
Y: 165
W: 345
H: 260
```

Corner radius:

```text
28 px
```

Background:

```text
#FBCB3D
```

Image layer:

```text
Node: 7:25
X: 54
Y: 38
W: 321
H: 241
```

Image is cropped using an oversized source image.

## New Student label

Node:

```text
7:9
```

Text:

```text
طالب جديد
```

Position:

```text
X center: 110
Y: 205
W: 128
H: 48
```

Typography:

```text
Inter Bold
24 px
#FFFCF7
Center
```

## Old Student Card

Container:

```text
X: 24
Y: 445
W: 345
H: 260
```

Corner radius:

```text
28 px
```

Background:

```text
#E43639
```

Image:

```text
Node: 12:5
X: 43
Y: 15
W: 311
H: 260
```

## Old Student label

Node:

```text
7:23
```

Text:

```text
طالب حالي
```

Position:

```text
X center: 110
Y: 481
W: 128
H: 48
```

Typography:

```text
Inter Bold
24 px
#FFFCF7
Center
```

## Signature

Node:

```text
13:8
```

Text:

```text
tarek el araby
```

Position:

```text
center X ≈ 196.5
Y: 684
W: 252
H: 147
```

Typography:

```text
Gardenia Summer Regular
128 px
Black
Center
```

## Academic year

Node:

```text
13:9
```

Text:

```text
2026-2027
```

Position:

```text
X: 198
Y: 772
W: 100
H: 16
```

Typography:

```text
Inter Bold
10 px
Black
Center
```

## Person icon

Node:

```text
15:15
```

Size:

```text
40 × 40
```

Position:

```text
X: 177
Y: 783
```

The Figma MCP identifies this as a Material 3 Design Kit `person` component.

---

# 7. Screen: New Student - Welcome

**Node:** `35:18`

**Frame:** `393 × 852`

## Background

```text
#FFFCF7
```

## Top safe-area layer

Node:

```text
38:57
```

```text
X: -1
Y: 0
W: 393
H: 59
Color: #D9D9D9
```

## Hero image

Node:

```text
38:59
```

```text
X ≈ 12.32
Y: 60
W: 369.634
H: 405
```

The source image is cropped/overscaled.

## Welcome title

Node:

```text
35:38
```

Text:

```text
welcome to our society with
```

```text
Y: 467
W: 374
H: 134
```

Typography:

```text
Inter Bold
48 px
Black
Center
```

## Brand

Node:

```text
35:39
```

Text:

```text
TAREK EL ARABY
```

```text
Y: 619
W: 393
H: 57
```

Typography:

```text
Inter Regular
32 px
Black
Center
```

## Subtitle

Node:

```text
35:40
```

Text:

```text
Go pro to unlock our features
```

```text
Y: 668
W: 393
H: 61
```

Typography:

```text
Inter Regular
24 px
Black
Center
```

## Get Started button

Container:

```text
X: 23
Y: 713
W: 347
H: 69
Radius: 12
Color: #2563EB
```

Label:

```text
Get started
```

Typography:

```text
Inter Bold
24 px
#FFFCF7
Center
```

---

# 8. Screen: New Student - name

**Node:** `38:43`

**Frame:** `393 × 852`

## Hero image

```text
X: 6
Y: 60
W: 381
H: 502
```

## Input

Outer field:

```text
X: 23
Y: 608
W: 347
H: 69
Radius: 12
Border: #D0D0D0
Fill: transparent
```

Floating label backing:

```text
X: 46
Y: 590
W: 122
H: 33
Background: #FFFCF7
```

Label:

```text
Full Name
```

```text
X center: 106
Y: 596
Font: Inter Regular
Size: 20
Color: #9A9A9A
```

Placeholder:

```text
Enter your full name
```

```text
Y: 633
W: 319
H: 29
Font: Inter Regular
20
Color: #9A9A9A
Center
```

## Next button

```text
X: 23
Y: 713
W: 347
H: 69
Radius: 12
Color: #2563EB
```

Label:

```text
Next
```

```text
Font: Inter Semi Bold
32 px
White
```

---

# 9. Screen: New Student - number

**Node:** `40:4`

**Frame:** `393 × 852`

## Hero image

```text
X: -2.5
Y: 60
W: 400
H: 515
```

## Phone input

```text
X: 23
Y: 608
W: 347
H: 69
Radius: 12
Border: #D0D0D0
```

Floating label backing:

```text
X: 34
Y: 590
W: 145
H: 33
Background: #FFFCF7
```

Label:

```text
phone number
```

Typography:

```text
Inter Regular
20 px
#9A9A9A
```

Placeholder:

```text
Enter your phone number
```

Typography:

```text
Inter Regular
20 px
#9A9A9A
Center
```

## Next

```text
X: 23
Y: 713
W: 347
H: 69
Radius: 12
Color: #2563EB
```

Label:

```text
Next
```

Typography:

```text
Inter Semi Bold
32 px
White
```

---

# 10. Screen: New Student - photo

**Node:** `41:14`

**Frame:** `393 × 852`

## Hero image

```text
X: -2.5
Y: 60
W: 410
H: 461
```

## Photo selection circle

Node:

```text
41:24
```

```text
X: 117
Y: 529
W: 159
H: 159
```

## Photo/add icon

Node:

```text
42:56
```

```text
X: 181
Y: 593
W: 32
H: 32
```

## Next

```text
X: 23
Y: 713
W: 347
H: 69
Radius: 12
Color: #2563EB
```

Label:

```text
Next
```

```text
Inter Semi Bold
32 px
White
```

---

# 11. Screen: New Student - Gade

**Node:** `44:98`

> Note: Figma layer name is `Gade` in the source file.

**Frame:** `393 × 852`

## Hero image

```text
X: -2.5
Y: 60
W: 410
H: 426
```

## Selection panel

```text
X: 23
Y: 486
W: 347
H: 202
Radius: 12
Border: #D0D0D0
```

## Grade options

| Option | X | Y | Font |
|---|---:|---:|---|
| Grade one | 78 | 505 | Inter Regular 24 |
| Grade two | 78 | 550 | Inter Regular 24 |
| Grade three | 78 | 595 | Inter Regular 24 |
| Grade four | 78 | 640 | Inter Regular 24 |

Text color:

```text
#1E1E1E
```

## Radio controls

Outer circle:

```text
20 × 20
X: 33
```

Y positions:

```text
509
555
601
647
```

Selected inner circle:

```text
12 × 12
X: 37
Y: 513
```

## Next

```text
X: 23
Y: 713
W: 347
H: 69
Radius: 12
Color: #2563EB
```

---

# 12. Screen: New Student - password

**Node:** `42:57`

**Frame:** `393 × 852`

## Hero image

```text
X: -2.5
Y: 56
W: 410
H: 438
```

## Password input 1

```text
X: 23
Y: 500
W: 347
H: 69
Radius: 12
Border: #D0D0D0
```

Label/placeholder:

```text
Enter password
```

```text
Y: 520
Font: Inter Regular
20 px
#9A9A9A
```

Eye control:

```text
24 × 24
X: 321
Y: 520
```

## Password input 2

```text
X: 23
Y: 602
W: 347
H: 69
Radius: 12
Border: #D0D0D0
```

Text:

```text
Re-Enter password
```

```text
Y: 626
Font: Inter Regular
20 px
#9A9A9A
```

Eye-off control:

```text
24 × 24
X: 321
Y: 625
```

## Finish

```text
X: 23
Y: 713
W: 347
H: 69
Radius: 12
Color: #2563EB
```

Label:

```text
Finish
```

```text
Inter Semi Bold
32 px
White
```

---

# 13. Screen: New Student - End

**Node:** `44:108`

**Frame:** `393 × 852`

## Safe Area

```text
X: 0
Y: 0
W: 393
H: 59
```

## Hero image

```text
X: -8
Y: 59
W: 410
H: 589
```

No additional visible controls were exposed in the metadata for this frame.

---

# 14. Screen: Current Student - Sign In

**Node:** `52:143`

**Frame:** `393 × 852`

## Hero image

```text
X: -2.5
Y: 60
W: 420
H: 416
```

## Phone input

```text
X: 23
Y: 486
W: 347
H: 69
Radius: 12
Border: #D0D0D0
```

Label:

```text
phone number
```

```text
X ≈ 102
Y: 507
W: 157
H: 29
Inter Regular
20 px
#9A9A9A
```

Smartphone icon:

```text
20 × 20
X: 42
Y: 510
```

## Password input

```text
X: 23
Y: 569
W: 347
H: 69
Radius: 12
Border: #D0D0D0
```

Label:

```text
Password
```

```text
X ≈ 102
Y: 589
W: 157
H: 29
Inter Regular
20 px
#9A9A9A
```

Lock icon:

```text
20 × 20
X: 42
Y: 589
```

Eye controls:

```text
24 × 24
X: 324
Y: 589
```

## Forgot password

Text:

```text
Forget password?
```

Position:

```text
X ≈ 206
Y: 655
W: 186
H: 31
```

Typography:

```text
Inter Regular
12 px
Black
Center
```

## Login

Button:

```text
X: 23
Y: 713
W: 347
H: 69
Radius: 12
Color: #2563EB
```

Label:

```text
Login
```

Typography:

```text
Inter Bold
24 px
#FFFCF7
Center
```

---

# 15. Component: 3D Coverflow Carousel

**Node:** `191:745`

**Frame:** `460 × 547`

## Main carousel container

```text
W: 460
H: 547
Padding left: 460
Padding top: 20
Padding bottom: 40
```

## Cards viewport

Node:

```text
191:746
```

```text
W: 380
H: 487
```

## Main card — Slide 1 / 4

Node:

```text
191:771
```

```text
X: -418
Y: 0
W: 300
H: 440
```

Card:

```text
Background: #8C2323
Radius: 24
```

Shadow:

```text
0 20px 40px rgba(0,0,0,0.6)
0 0 0 2px rgba(255,255,255,0.2)
```

Poster:

```text
W: 300
H: 320
```

Poster overflow:

```text
Top corners: 20
```

Poster image inset:

```text
X: -6.5
Y: -8
W: 313
H: 336
```

## Main card information section

```text
W: 300
H: 172.5
```

Gradient:

```text
Top: transparent #8C2323
Bottom: #8C2323
```

### Course name

```text
مالية متقدمة
```

```text
Y: 16
Font: Cairo Bold
20 px
White
Center
```

### Doctor name

```text
Tarek El Araby
```

```text
Y: 48
Font: Freestyle Script Regular
20 px
rgba(255,255,255,0.8)
Center
```

### Course statistics

Container:

```text
X: 16
Y: 80
W: 268
H: 33
Radius: 12
Background: rgba(0,0,0,0.2)
Backdrop blur: 2 px
Padding: 8
```

Stats:

```text
1 فاينال
2 مراجعة
12 شرح
```

Metadata:

```text
Cairo Regular
11 px
rgba(255,255,255,0.7)
```

Icons:

```text
Font Awesome 5 Free Solid
11 px
#FBBF24
```

### Start button

```text
X: 16
Y: 124.5
W: 268
H: 32
Radius: 12
Background: white
```

Label:

```text
start
```

```text
Cairo Bold
20 px
#8C2323
```

## Side card — Slide 2 / 4

Node:

```text
191:759
```

```text
X: -616.71
Y: 24.4
W: 230.87
H: 397.64
```

Poster:

```text
W: 230.87
H: 289.19
```

Info:

```text
W: 230.87
H: 155.89
```

Course:

```text
استراتيجيات التسويق
```

Typography:

```text
Cairo Bold
20 px
White
```

Metadata:

```text
8 محاضرات
Cairo Regular
11 px
rgba(255,255,255,0.7)
```

Card background:

```text
#8C2323
```

Radius:

```text
24
```

Shadow:

```text
0 15px 35px rgba(0,0,0,0.4)
```

## Side card — Slide 4 / 4

Node:

```text
191:747
```

```text
X: -153.8
Y: 37.48
W: 230.87
H: 374.95
```

Poster:

```text
230.87 × 272.69
```

Info:

```text
230.87 × 147.04
```

Course:

```text
إدارة المشاريع
```

Metadata:

```text
14 ساعة
```

Typography:

```text
Cairo Bold / Regular
20 / 11 px
```

## Pagination

Node:

```text
191:792
```

```text
W: 460
H: 24
```

Dots:

```text
8 × 8
Radius: 4
Gap: 8
```

Active dot:

```text
20 × 8
Radius: 6
Background: white
```

Inactive dots:

```text
8 × 8
Background: rgba(255,255,255,0.4)
```

Positions:

```text
Slide 4: X 156
Slide 3: X 172
Slide 2: X 188
Slide 1: X 204, width 20
```

---

# 16. Avatar System

**Section:** `190:556`

**Design showcase frame:** `190:146`

## Showcase

```text
Width: 1200
Height: 601
```

Title:

```text
Avatar System — Dr. Tarek Platform
```

Typography:

```text
Cairo ExtraBold
26 px
#F5F7FC
Center
```

## Group labels

```text
Placeholder
Photo
```

Typography:

```text
Cairo Bold
13 px
rgba(245,247,252,0.6)
Letter spacing: 0.5
Uppercase
```

## Avatar card

Each role card:

```text
W: 183.33 px
H: 170 px
Radius: 18 px
Border: 1 px rgba(255,255,255,0.16)
Backdrop blur: 9 px
```

Card background gradient:

```text
rgba(255,255,255,0.10) → rgba(255,255,255,0.03) → rgba(255,255,255,0.01)
```

## Avatar

```text
56 × 56
Radius: 28
```

Base avatar shadow:

```text
0 10px 20px -10px rgba(0,0,0,0.5)
```

Inner highlight:

```text
inset 0 1px 0 rgba(255,255,255,0.4)
```

Avatar glass layer:

```text
Backdrop blur: 5 px
Gradient:
rgba(255,255,255,0.28)
→ rgba(255,255,255,0.04)
```

## Badge

Badge position:

```text
Top: -9 px
```

Shape:

```text
Radius: 999
Backdrop blur: 3 px
Border: 1 px rgba(255,255,255,0.4)
Padding horizontal: 13 px
Padding vertical: 4 px
```

Badge typography:

```text
Cairo ExtraBold
10.5 px
Letter spacing: 0.3
White
```

Badge shadow:

```text
0 8px 16px -6px rgba(0,0,0,0.55)
```

---

# 17. Avatar Roles / Plans

## 1 — Teacher (Platform Owner)

Official role name:

```text
Teacher (Platform Owner)
```

Badge:

```text
DR
```

Avatar ring:

```text
#FFC96B
Solid
Shadow: rgba(255,158,44,0.55)
```

Badge gradient:

```text
rgba(255,201,107,0.94)
→ rgba(255,158,44,0.94)
```

## 2 — Admin

Badge:

```text
ADMIN
```

Avatar ring:

```text
#C084FC
Dashed
Shadow: rgba(139,92,246,0.55)
```

Badge gradient:

```text
rgba(192,132,252,0.94)
→ rgba(139,92,246,0.94)
```

## 3 — External Student

Plan:

```text
FREE
```

Avatar ring:

```text
rgba(255,255,255,0.45)
Dashed
```

Badge gradient:

```text
rgba(111,195,255,0.94)
→ rgba(61,143,224,0.94)
```

## 4 — Internal Student — FREE

Plan:

```text
FREE
```

Avatar ring:

```text
#5CF2D6
Dashed
Shadow: rgba(31,203,168,0.5)
```

Badge uses the blue FREE gradient.

## 5 — Internal Student — PRO

Plan:

```text
PRO
```

Avatar ring:

```text
#5CF2D6
Dashed
Shadow: rgba(31,203,168,0.5)
```

Badge gradient:

```text
rgba(92,242,214,0.94)
→ rgba(31,203,168,0.94)
```

## 6 — Internal Student — MAX

Plan:

```text
MAX
```

Avatar ring:

```text
#5CF2D6
Dashed
Shadow: rgba(31,203,168,0.5)
```

Badge gradient:

```text
rgba(255,143,203,0.94)
→ rgba(194,24,91,0.94)
```

---

# 18. Avatar Variants

The Figma file exposes the following profile/button variants:

```text
FREE_EXTERNAL
FREE_INTERNAL
PRO
MAX
ADMIN
```

The Teacher/Platform Owner variant uses:

```text
DR
```

The Figma component structure also exposes:

```text
Badge=FREE_EXTERNAL
Badge=FREE_INTERNAL
Badge=PRO
Badge=MAX
Badge=ADMIN
Teachr (platform owner)
```

> The official platform terminology is `Teacher (Platform Owner)`.

---

# 19. Student Home — Primary Extracted Version

**Node:** `55:10`

**Frame:** `393 × 852`

## Background

The screen uses a red radial gradient.

Observed gradient stops:

```text
rgba(255,179,168,1)
rgba(255,151,138,1)
rgba(255,122,107,1)
rgba(245,95,80,1)
rgba(234,67,53,1)
rgba(178,45,38,1)
rgba(122,23,23,1)
```

## Greeting

```text
Hi, tarek
```

Position:

```text
Y: 187
W: 133
H: 23
```

Typography:

```text
Inter Semi Bold
16 px
#FFFCF7
Center
```

## Poster

Node:

```text
70:12
```

```text
W: 150
H: 183.333
Y: 238.333
```

Radius:

```text
23.333
```

## Decorative background elements

Detected four overlapping image/shape layers:

| Node | X | Y | W | H |
|---|---:|---:|---:|---:|
| `97:18` | -49 | 169.286 | 250 | 321.429 |
| `97:16` | -24.199 | 161.25 | 270 | 337.5 |
| `97:15` | 191.801 | 169.766 | 250 | 321.429 |
| `97:17` | 138.801 | 161.25 | 270 | 337.5 |

## Signature

```text
Tarek El Araby
```

```text
Y: 721
W: 393
H: 172
Font: Inter Regular
20 px
#FFFCF7
Center
```

---

# 20. Imported Educational Cinema Section

**Section:** `168:287`

Overall:

```text
2122 × 1402
```

Main design frame:

```text
1920 × 1200
```

Mobile device mockup:

```text
380 × 780
```

Carousel:

```text
460 × 547
```

This section contains the same `3D Coverflow Carousel` specifications documented above.

---

# 21. Assets Detected

The Figma MCP returned temporary remote assets for the following design elements:

## Registration / onboarding

- New Student welcome hero
- Full-name screen hero
- Phone-number screen hero
- Photo screen hero
- Grade screen hero
- Password screen hero
- Current student sign-in hero
- New Student End hero
- User Type Selection — New Student image
- User Type Selection — Old Student image
- Photo selection ellipse
- Photo/add icon
- Grade radio controls

## Student Home

- Student avatar image
- Four decorative poster/background layers
- Poster 1

## Carousel

- Main course poster
- Secondary course poster 1
- Secondary course poster 2

## Avatar system

Multiple SVG assets for:
- placeholder avatar
- role avatars
- photo avatars
- badge/ring graphics
- masked avatar artwork

> Figma MCP asset URLs are temporary and should not be treated as permanent project asset URLs. Production assets must be copied into the project's approved asset pipeline.

---

# 22. Flutter Implementation Mapping

The Figma design is a mobile UI and should map to Flutter approximately as follows:

| Figma concept | Flutter implementation |
|---|---|
| Frame | `Scaffold` / screen root |
| Absolute positioning | `Stack` only where design requires exact layered composition |
| Text | `Text` / project typography component |
| Rounded rectangle | `Container` / `DecoratedBox` |
| Image crop | `Image` + `BoxFit.cover` / `ClipRRect` |
| Rounded card | `ClipRRect` + decoration |
| Gradient | `LinearGradient` / `RadialGradient` |
| Glass effect | `BackdropFilter` + translucent decoration |
| Badge | Reusable avatar badge component |
| Avatar | Reusable avatar component |
| Pagination dots | Reusable carousel pagination component |
| Input | Project input component following Figma geometry |
| Button | Project button component following Figma geometry |
| Safe area | Flutter `SafeArea`, not a hard-coded gray rectangle in production |

---

# 23. Non-Negotiable Visual Constants

The following values repeatedly occur and should become project-level design constants/tokens where appropriate:

```text
Mobile width: 393
Mobile height: 852

Primary light background: #FFFCF7
Primary action blue: #2563EB
Input border: #D0D0D0
Placeholder gray: #9A9A9A
Safe-area source placeholder: #D9D9D9

Primary card yellow: #FBCB3D
Primary card red: #E43639

Carousel red: #8C2323
Carousel gold: #FBBF24

Standard registration button:
347 × 69
Radius: 12

Standard registration horizontal margin:
23 px

Registration hero start:
Y ≈ 60

Standard avatar:
56 × 56
Radius: 28

Avatar badge:
Radius: 999
Top overlap: -9
Horizontal padding: 13
Vertical padding: 4
```

---

# 24. Important Implementation Rules

1. **Figma is the visual source of truth.**
2. Preserve the `393 × 852` mobile design.
3. Do not replace exact Figma geometry with arbitrary Material 3 defaults.
4. Do not introduce Tailwind or web-only CSS into Flutter.
5. Convert the design into Flutter widgets while preserving the measured geometry.
6. Use reusable components for:
   - buttons
   - inputs
   - avatar
   - badges
   - carousel cards
   - pagination
7. Keep business logic outside presentation widgets.
8. Keep Firebase/Firestore access outside widgets.
9. Use the project's Clean Architecture and Feature-First structure.
10. Use Riverpod for dependency injection/state management according to project architecture.
11. Use the official role name:
    `Teacher (Platform Owner)`
12. The Teacher/Platform Owner plan badge is:
    `DR`.

---

# 25. Verification Status

## Fully extracted with design context in this document

- Splash Screen-START
- Splash Screen-END
- User Type Selection
- New Student - Welcome
- New Student - name
- New Student - number
- New Student - photo
- New Student - Gade
- New Student - password
- Current Student - sign in
- Student Home — primary extracted version
- 3D Coverflow Carousel
- Avatar System

## Metadata-only / partially extracted

- New Student - End
- Alternate `Student - home` node `134:697`

## Source-file sections

- Educational cinema carousel import section
- Avatar system import section

> The Figma MCP Starter plan reached its tool-call limit while attempting an additional extraction of node `134:697`. Therefore this document does **not** invent missing styling values for that node. Its frame dimensions and location are recorded in the file inventory above.

---

# 26. Source Integrity

This document intentionally distinguishes:

- **Measured Figma values** — dimensions, positions, colors, typography, shadows, radii and node IDs returned by Figma MCP.
- **Implementation mapping** — Flutter interpretation of those values.
- **Missing information** — explicitly marked rather than guessed.

No unobserved Figma specification should be treated as final UI behavior.

