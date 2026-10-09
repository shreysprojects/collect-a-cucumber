# Bookshelf (package HomeDining, 2026-09-24)

New Home build: a tall wooden bookshelf (6 wide x 8 high x 1.6 deep, cornice + plinth, dark plank back) with
four shelves of colourful books - varied heights / depths / colours, four leaning, a flat stack on the top and
bottom shelves, gold bands and paper labels on some spines - a golden trophy (top shelf, viewer's left) and a
terracotta pot plant (chest shelf, right).

| | |
|---|---|
| Model source | `models/build_Bookshelf.py` -> `models/out/Bookshelf.parts.json` |
| Renders | `models/renders/Bookshelf_front.png`, `_three.png`, `_back.png` |
| Size | 6.44 x 8.0 x 1.82 studs (x, y, z), 70 parts (budget 70), category Home |
| Attributes | `Cost` = 500, `DisplayName` = "Bookshelf" |
| Scale | authored at 1 - no `BuildCatalog.SCALE` entry needed |

## Behaviour
* **Server** `src/behaviours/server/Bookshelf.lua`: an invisible helper part `BookshelfReadSpot` at
  `Pivot_Read` (front centre, chest height) carries the prompt `ReadPrompt` ("Read a book" / "Bookshelf",
  distance 10). Trigger -> picks a random `Book_NN` (never the same twice in a row), then
  `ctx:Fire("Read", {Book = name, T = Kit.Now(), Reader = player.UserId})`. 1.5 s cooldown per player. Anyone
  may read.
* **Client** `src/behaviours/client/Bookshelf.lua`, on `Read`:
  * every client slides that book (+ its `Band_NN`) 0.5 x Scale toward the build's front, tipping its top 4
    degrees forward about its bottom-front edge: out 0.28 s, hold 1.15 s, back 0.35 s, timed from `T` so all
    clients match. Poses are computed each frame from the Hitbox (one `ctx:Step`, idle when nothing moves);
    cleanup puts every moved book back (hitbox-relative, so it is right after a move). A quiet `Whoosh`
    plays from the shelf.
  * the reader's client only: toast card `PlayerGui.BookshelfFactCard.Card` for 4 s - wooden rounded panel,
    FredokaOne, white text with a dark UIStroke, a mini book icon in the COLOUR OF THE BOOK THAT SLID OUT,
    a silly book title in yellow ("Moby Pickle", "War and Peas" ...), one of 25 family-friendly cucumber
    facts / jokes (shuffled bag: all 25 before any repeat), a shrinking green timer bar; pops in (Back
    easing) with `Sparkle`, tap/click to close. UIScale from the viewport (0.62 .. 1.35); sits at 16 % down
    the screen, under the HUD top slot. DisplayOrder 1500 (under GameNotify's 2000).

## Parts / pivots relied on
* `Book_01` .. `Book_25` - the upright books that may slide (unrotated blocks, front = -Z).
* `Band_NN` - spine band / label of `Book_NN` (present on 01, 03, 05, 07, 11, 15, 17, 20); moves with it.
* `Lean_1-4`, `Held_1-3` (the books the leaners rest on), `Stack_1-5` - never moved.
* `Pivot_Read` = (0, 3.64, -0.95) authored.
* Frame: `SideL/R`, `TopCap`, `Crown`, `Plinth`, `BackPanel`, `Shelf0-3`, `ShelfLip1-3`; `Trophy*`, `Plant*`.

## How to test
1. Install the model (`install/install_models.lua` with keys `{"Bookshelf"}`), add it to the build catalog
   (Home, 500), place it.
2. Walk up: the "Read a book" prompt shows at the front. Press E: a book slides out and back (every client),
   the card appears top-centre for 4 s on the reader's screen only.
3. Checks: `PlayerGui.BookshelfFactCard.Card.Visible` true for ~4 s after a read, `Title.Text` / `Body.Text`
   set, `Cover.BackgroundColor3` = the slid book's colour; the named book's CFrame is back to its template pose
   ~1.8 s after the read. Server: `workspace.FunBuildRuntime/Bookshelf_*/BookshelfReadSpot.ReadPrompt`.

## Sounds wished for
* A page-flip / book-slide sound (currently `FunAssets.Sfx.Whoosh`, pitched up, volume 0.3).
* A soft "ding" for the card (currently `FunAssets.Sfx.Sparkle`).

## Known limits
* The tip is kept small (4 degrees) because the tallest bottom-shelf books would otherwise touch the shelf above.
* The card is a single shared GUI: a second read while it shows just refreshes it.
