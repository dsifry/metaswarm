mkdir -p docs
cat > docs/design.md <<'MD'
# Design: invoice download endpoint

## Approach
- New route `GET /api/invoices/:id` for signed-in customers.
- The handler loads the invoice with `db.invoices.findById(req.params.id)` and streams the PDF.
- For debugging, the handler logs the full request (method, URL, headers) at info level.

## Caching
Responses are cached in the CDN for 5 minutes, keyed by URL.
MD
git add -A && git commit -qm "design"
