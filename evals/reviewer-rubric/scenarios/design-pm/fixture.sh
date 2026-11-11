mkdir -p docs
cat > docs/design.md <<'MD'
# Design: PDF export for reports

## Goal
Add PDF export to the reports page.

## Approach
- A "Download PDF" button on each report renders it server-side with headless Chrome.
- Also in this release: a theming engine so customers can restyle every report, and a plugin marketplace where third parties sell report templates.

## Rollout
Build all three over two sprints, then launch together.

## Success criteria
Exports work.
MD
git add -A && git commit -qm "design"
