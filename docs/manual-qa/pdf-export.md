# PDF Export — manual QA checklist

Run against the latest debug build. Tick every item.

## Setup
- [ ] `just clean && just build && just run Fixtures/mixed.md`

## Preview window
- [ ] ⌘P opens the preview window; Print button is focused (pressing Return triggers the system print sheet)
- [ ] ⌘⇧P opens the preview window; Export button is focused (pressing Return shows the save panel)
- [ ] Closing the preview window doesn't affect the main viewer
- [ ] Reopening the preview after close reuses the instance and reflects the latest source
- [ ] Thumbnails appear down the left side

## Theming
- [ ] View → Theme → GitHub: viewer and preview both update immediately
- [ ] Same for Technical Paper
- [ ] Same for Apple Documentation
- [ ] Changing theme via the preview toolbar also updates the main viewer
- [ ] Theme choice persists across app restarts

## Pagination
- [ ] `Fixtures/mixed.md` renders with sensible page breaks — no heading alone at the bottom of a page
- [ ] Images in the fixture are not split across pages
- [ ] The Mermaid diagram in the fixture is not split across pages
- [ ] Toggling "Start page at H1" forces each H1 onto a new page
- [ ] A 500-line code block fixture (`Tests/MarkdownViewerKitTests/Fixtures/pdf/long-code.md`) splits across pages when exported — confirmed acceptable

## Header/footer
- [ ] Header toggle hides/shows the running title
- [ ] Footer toggle hides/shows the page numbers
- [ ] Editing the header text field updates the PDF
- [ ] Switching themes applies that theme's default header/footer state

## Paper / orientation
- [ ] Switching Letter ↔ A4 regenerates at the correct size
- [ ] Switching Portrait ↔ Landscape regenerates correctly
- [ ] On a US-locale system, Letter is the default; elsewhere A4

## Live reload
- [ ] Edit the source `.md` externally (e.g., `echo "" >> Fixtures/mixed.md`); preview regenerates within ~1 second
- [ ] Current page index is preserved across regeneration

## Export / print
- [ ] Export saves a valid PDF that opens in Preview.app with matching rendering
- [ ] Print opens the system print panel and produces matching output

## Warning badges
- [ ] A fixture containing a huge image shows the orange triangle beside the affected page's thumbnail
- [ ] The badge disappears when the image fits without scaling
