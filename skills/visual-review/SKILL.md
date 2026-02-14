---
name: visual-review
description: Take screenshots of web pages and UI using Playwright for visual review and iteration
auto_activate: false
triggers:
  - "visual review"
  - "screenshot"
  - "take a screenshot"
  - "review visually"
  - "check how it looks"
  - "review the UI"
  - "review the slides"
---

# Visual Review

## Purpose

Agents cannot see rendered web pages, presentations, or UI. This skill bridges that gap by using Playwright to capture screenshots of web pages (local files, localhost servers, or deployed URLs) so agents can visually inspect their work, identify layout issues, and iterate.

This is especially useful for:
- **Reveal.js presentations** — capture each slide individually
- **Web UIs** — verify layout, styling, and responsiveness
- **Landing pages** — check visual design matches intent
- **Email templates** — verify rendering

## Prerequisites

This skill requires **Playwright** to be available. Before first use, check and install if needed:

```bash
# Check if Playwright is available
npx playwright --version 2>/dev/null

# If not available, install it (one-time setup)
npx playwright install chromium
```

**Important:** Only the `chromium` browser is needed. Do not install all browsers — it wastes disk space and time.

If `npx playwright` fails entirely, the user may need to install it:
```bash
npm install -g playwright
npx playwright install chromium
```

## Workflow

### Phase 1: Setup

1. **Verify Playwright is available** — run `npx playwright --version`
2. **If not installed** — run `npx playwright install chromium` and inform the user
3. **Create output directory** — `mkdir -p /tmp/visual-review`
4. **Determine the target** — local file path, localhost URL, or deployed URL

### Phase 2: Capture Screenshots

#### For a single page:

```bash
npx playwright screenshot \
  --browser chromium \
  --viewport-size "1456,816" \
  --wait-for-timeout 3000 \
  "<URL_OR_FILE_PATH>" \
  /tmp/visual-review/page.png
```

**Parameters:**
- `--viewport-size "1456,816"` — 16:9 aspect ratio, good for presentations
- `--wait-for-timeout 3000` — wait 3 seconds for fonts, images, and animations to settle
- Use `file:///absolute/path/to/file.html` for local files
- Use full URLs for deployed sites

#### For Reveal.js presentations (multiple slides):

Capture each slide by appending the slide hash to the URL:

```bash
# Capture all slides (adjust count as needed)
for i in $(seq 0 15); do
  npx playwright screenshot \
    --browser chromium \
    --viewport-size "1456,816" \
    --wait-for-timeout 2000 \
    "<BASE_URL>#/$i" \
    "/tmp/visual-review/slide-$i.png"
done
```

**Tip:** To capture slides with all fragments visible, add `?fragments=true` or use JavaScript injection via a Playwright script. The simpler approach is to accept that fragment-heavy slides will appear in their initial (pre-click) state.

#### For responsive testing:

```bash
# Mobile
npx playwright screenshot --viewport-size "390,844" "<URL>" /tmp/visual-review/mobile.png

# Tablet
npx playwright screenshot --viewport-size "768,1024" "<URL>" /tmp/visual-review/tablet.png

# Desktop wide
npx playwright screenshot --viewport-size "1920,1080" "<URL>" /tmp/visual-review/desktop.png
```

### Phase 3: Show and Review Screenshots

**IMPORTANT:** The agent can see screenshots via the Read tool, but the **user cannot**. Always open screenshots for the user so they can see what you see:

```bash
# Open a specific screenshot for the user
open /tmp/visual-review/slide-2.png

# Open all screenshots at once (for batch review)
open /tmp/visual-review/slide-*.png
```

Then use the Read tool yourself to analyze each screenshot:

```
Read /tmp/visual-review/slide-0.png
Read /tmp/visual-review/slide-1.png
...
```

**Always do both:** `open` for the user + `Read` for the agent. The user and agent should be looking at the same thing and able to discuss what they see.

For each screenshot, evaluate:
- **Layout** — Is content centered/aligned as intended?
- **Typography** — Are headings, body text, and code readable?
- **Colors** — Do accent colors, backgrounds, and contrasts look right?
- **Spacing** — Is there enough whitespace? Any cramped areas?
- **Content** — Is all expected content visible? (Note: fragment content may be hidden)
- **Responsiveness** — Does it work at the target viewport size?

### Phase 4: Document Findings

Create a findings summary:

```markdown
## Visual Review — [Project Name]

### Reviewed: [date]

| Slide/Page | Status | Notes |
|-----------|--------|-------|
| slide-0   | Good   | Title centered, accent color correct |
| slide-1   | Issue  | Text overflows right edge on mobile |
| ...       | ...    | ... |

### Issues to Fix
1. [Description of issue + which slide/page]
2. [...]

### Looks Good
- [Things that are working well]
```

### Phase 5: Fix and Re-capture

After making fixes:
1. Re-capture only the affected slides/pages
2. Review the new screenshots
3. Repeat until satisfied

## Reveal.js-Specific Tips

- **Slide numbering**: Reveal.js uses `#/0` for the first slide, `#/1` for the second, etc.
- **Vertical slides**: Use `#/horizontal/vertical` format (e.g., `#/2/1`)
- **Fragments**: Content with `class="fragment"` is hidden until clicked. Screenshots show the initial state. This is expected behavior, not a bug.
- **Speaker notes**: Not visible in screenshots (they appear in a separate window with `S` key)
- **Theme loading**: Use `--wait-for-timeout 3000` to ensure CDN-loaded themes and fonts are ready

## Common Mistakes

| Mistake | Why It's Wrong | Do This Instead |
|---------|---------------|-----------------|
| Not waiting for page load | Fonts/images may not render | Use `--wait-for-timeout 3000` |
| Using `http://` for local files | File URLs need `file:///` protocol | Use `file:///absolute/path` |
| Installing all Playwright browsers | Wastes time and disk | Only install `chromium` |
| Treating fragment-hidden content as a bug | Fragments are designed to reveal on click | Note it as expected |
| Forgetting to create output directory | Screenshots fail silently | Always `mkdir -p /tmp/visual-review` first |
| Taking too many screenshots at once | Floods context window | Review in batches of 4-6 |
| Only using Read without `open` | User can't see what the agent sees | Always `open` for the user + `Read` for yourself |

## Integration Points

**Upstream:** Any skill that produces visual output (presentations, web UIs, email templates)

**Downstream:** Fixes feed back into the source files, then re-capture to verify

## Verification Checklist

- [ ] Playwright is installed and working
- [ ] Screenshots captured at correct viewport size
- [ ] All pages/slides reviewed
- [ ] Issues documented with specific descriptions
- [ ] Fixes verified with re-captured screenshots
