# Skill: Flutter Safe Layout & Orientation handling

## Description
This skill provides guidelines and mandatory patterns to prevent `RenderFlex overflow` errors (like the "RIGHT OVERFLOWED BY 14 PIXELS" or "10 PIXELS" errors) and to handle Landscape/Portrait transitions correctly in Flutter.

## Core Rules

### 1. The "Flexible First" Rule
In any `Row`, **never** place a `Text` widget without a `Flexible` or `Expanded` wrapper if it's next to other widgets. This ensures the text shrinks gracefully on narrow screens.

```dart
// SAFE ROW PATTERN
Row(
  children: [
    Expanded(child: Text('Long content...', overflow: TextOverflow.ellipsis, maxLines: 1)),
    const SizedBox(width: 8),
    Icon(Icons.more_vert),
  ],
)
```

### 2. The "Action Width" Calculation
When using a `SizedBox` for a group of `IconButton`s or `InkWell` icons:
- Width = (Number of Icons) * (Icon Size + (Padding * 2)).
- **Always add a 5-10px buffer** to account for standard `visualDensity` or system scaling.
- *Good practice:* 2 icons (18px each) with 6px padding = 60px. Use **70px** as a safe fixed width.

### 3. Landscape Sheet Constraints
Bottom sheets (`DraggableScrollableSheet`) often get "stuck" in landscape.
- **Rule:** Use `MediaQuery.of(context).orientation` to check orientation.
- **Goal:** In landscape, set `initialChildSize` higher (e.g. 0.8) and `minChildSize` lower (e.g. 0.3) to allow full dragging.

### 4. AppBar Action Limits
Narrow phones (320dp-360dp) can only comfortably fit a title and **2, maybe 3 icons**.
- If you have 4+ icons: Move secondary actions to a `PopupMenuButton`.
- This prevents the 10-20px "Right Overflow" in the top bar.

## Verification Checklist
- [ ] Row text has `Expanded` + `Ellipsis`.
- [ ] Action area `SizedBox` width >= `(count * (size + 2*padding)) + buffer`.
- [ ] Screen turned horizontally: is the sheet pullable?
- [ ] Is `maxLines` defined for all list labels?
