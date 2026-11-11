mkdir -p docs src/components
printf 'export function App() { return null; }\n' > src/App.tsx
cat > docs/design.md <<'MD'
# Design: saved searches panel

## Components
- `SavedSearchList` shows the user's saved searches as cards, newest first.
- `SavedSearchCard` shows the search name, the filters as chips, and a "Run" button.
- Clicking "Run" re-runs the search.

## Visual design
Cards use the existing card style: title in bold, chips in a single row, the "Run" button right-aligned.
MD
git add -A && git commit -qm "design"
