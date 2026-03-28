---
name: frontend-polish
description: >
  Audit and polish an existing frontend repo's layout, composition, and motion
  WITHOUT changing any colors, fonts, or brand identity. Adds effects, fixes
  visual hierarchy, removes clutter, and enforces clean composition using only
  the repo's existing design tokens. Trigger on: "polish the frontend",
  "clean up the UI", "add animations", "fix the layout", "improve the hero",
  "tighten up the page", "make it feel more polished", "add motion",
  "audit the frontend", "fix visual hierarchy", or any request to improve
  an existing frontend surface without a redesign. Also trigger when the user
  says "polish", "tighten", "clean up", or "add effects" in a frontend context.
---

# Frontend Polish Skill

Polish an existing frontend codebase — improve composition, hierarchy, and motion
using ONLY the design tokens (colors, fonts, spacing) already present in the repo.

**Core rule: You are polishing, not redesigning. Change nothing about the visual identity.**

---

## Phase 1: Audit (mandatory, execute before any changes)

Scan the repo and extract the complete existing design system:

1. **Colors** — CSS variables, Tailwind config, theme files, hardcoded hex/rgb/hsl values across all stylesheets and components. Build a full palette map.
2. **Fonts** — font-family stacks, Google Font imports, @font-face rules, Tailwind font config entries.
3. **Spacing** — defined spacing tokens, recurring gap/padding/margin values.
4. **Existing patterns** — border radii, shadows, transitions, easing curves already in use.
5. **Component inventory** — card styles, button variants, section structures, nav patterns.

**Output a summary before proceeding.** List the palette, fonts, and key patterns found. Do not skip this step. Do not begin writing code until this is complete.

---

## Phase 2: Apply Polish

### Hard constraints (violating any of these is a failure)

| Never change | Rationale |
|---|---|
| Any color value, variable, or palette entry | Preserve brand identity |
| Any font-family, font import, or type stack | Preserve typographic identity |
| Logos, brand marks, wordmarks | Untouchable |
| Component prop interfaces or data flow | Preserve functionality |
| Content (unless it is placeholder/lorem ipsum) | Not your job here |

### Layout & Composition Fixes

Apply these rules to improve structure and hierarchy:

**First viewport (hero) budget** — must contain exactly:
- Brand/product name as a hero-level visual signal (not just nav text)
- One headline
- One short supporting sentence
- One CTA group
- One dominant visual (full-bleed preferred unless existing system uses another pattern)
- **Nothing else**

**Remove clutter from above-the-fold on sight:**
- Stat strips (rows of large numbers with labels)
- Pill clusters (multiple tag/badge rows)
- Icon rows (feature grids with icon + label + copy)
- Boxed promos (inset callouts with background fills)
- Schedule/agenda snippets in non-schedule contexts
- Multiple competing text blocks side-by-side in the hero
- "Everything above the fold" syndrome

**Card rules:**
- No cards in the hero. Ever.
- Cards are valid only as interactive containers (forms, selectable options, clickable grid items).
- Test: if removing border + shadow + background doesn't hurt interaction or comprehension, remove the card treatment.

**Section discipline:**
- One job per section.
- One headline + one supporting sentence per section.
- Section headlines must be specific to content below, not generic ("Why Us", "Our Features", "Learn More").

**Hero images:**
- Full-bleed / edge-to-edge by default.
- No inset heroes, side-panel heroes, rounded media cards, tiled collages, or floating image blocks (unless the existing design system explicitly uses these).
- No floating badges, labels, promo stickers, or info chips overlaid on hero media.

### Motion & Effects (ADD these — this is the primary value-add)

Add a minimum of 2–3 intentional motion moments:

1. **Page entrance** — orchestrated staggered reveal of hero elements (fade + slight translate, 0.3–0.6s, eased, 50–100ms stagger between elements). This is the single highest-impact addition.
2. **Scroll reveals** — sections fade/slide into view on scroll using Intersection Observer. Use `opacity: 0` + `translateY(20–30px)` → `opacity: 1` + `translateY(0)` with an eased transition.
3. **Interactive hover states** — purposeful hover effects on buttons, links, cards: subtle scale (1.02–1.05), opacity shifts, underline animations, shadow lifts. Only on genuinely interactive elements.

**Motion rules:**
- Use CSS transitions/animations and vanilla JS (Intersection Observer) unless the repo already includes an animation library.
- Motion creates hierarchy and presence. It does not decorate.
- One orchestrated page entrance > twenty scattered hover micro-interactions.
- Never animate purely decorative elements.
- Use the repo's existing easing curves and transition durations as a baseline. If none exist, default to `cubic-bezier(0.16, 1, 0.3, 1)` for reveals and `200ms ease` for hover states.

### Spacing & Rhythm

- Normalize inconsistent spacing using the existing scale — do not introduce new spacing values.
- Ensure sections have clear visual breathing room.
- Fix vertical rhythm inconsistencies across sections.

### Responsive Verification

- Confirm rendering at **1280px+** (desktop) and **375px** (mobile).
- Hero must function at both breakpoints without overflow, cramped text, or broken layouts.
- Navigation must be functional at mobile width.

### Micro-Details

- Smooth any janky or uneased transitions.
- Add `focus-visible` states on interactive elements if missing.
- Fix z-index stacking issues if present.
- Fix orphaned/widowed headlines at common breakpoints.

---

## Phase 3: Verify (mandatory before completion)

Run through this checklist and confirm each item:

```
[ ] AUDIT COMPLETE — palette, fonts, and patterns documented before changes began
[ ] ZERO color changes — no new colors, no modified colors, only existing palette
[ ] ZERO font changes — no new fonts, no modified font stacks
[ ] HERO BUDGET — first viewport contains only: brand + headline + sentence + CTA + visual
[ ] NO CLUTTER — no stat strips, pill clusters, icon grids, boxed promos in hero
[ ] NO HERO CARDS — cards removed from hero section
[ ] MOTION ADDED — at least 2 intentional motion moments (entrance + scroll reveals)
[ ] RESPONSIVE — renders correctly at 1280px+ and 375px
[ ] FUNCTIONALITY — all existing features, links, and interactions still work
[ ] SUMMARY — changes documented with rationale
```

---

## Output

After completing all phases, provide a concise summary:

1. **What was found** (audit results — palette size, fonts, patterns)
2. **What was changed** (list each modification with one-line rationale)
3. **What was added** (motion moments, hover states, spacing fixes)
4. **What was NOT changed** (confirm colors and fonts untouched)
