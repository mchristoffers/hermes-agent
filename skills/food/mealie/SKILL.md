---
name: mealie
description: "Manage recipes, meal plans, and shopping lists in the self-hosted Mealie instance via its REST API. Import recipes from a URL, a photo/screenshot, handwritten cards, or pasted text."
version: 1.1.0
author: moritz
license: MIT
platforms: [linux, macos, windows]
prerequisites:
  env_vars: [MEALIE_API_TOKEN]
metadata:
  hermes:
    tags: [Mealie, Recipes, Cooking, MealPlan, ShoppingList, Food, API]
    homepage: https://mealie.mchristoffers.dev
---

# Mealie

Talk to the self-hosted **Mealie** recipe manager (running on Coolify at
`https://mealie.mchristoffers.dev`) over its REST API. Use this for anything about
recipes, meal planning, shopping lists, and the food/category/tag organizers.

## Setup

Already wired in `~/.hermes/.env`:

```
MEALIE_BASE_URL=https://mealie.mchristoffers.dev
MEALIE_API_TOKEN=<long-lived token for the "hermes-agent" integration>
```

The token is a 5-year long-lived API token belonging to the admin user (Moritz). It
authenticates as a normal Bearer token. To mint a replacement, log into Mealie →
profile → **API Tokens**, or POST `/api/users/api-tokens` with a session token.

## Auth pattern

Every request sends the token as a Bearer header. Define a helper once per session:

```bash
B="$MEALIE_BASE_URL"
H=(-H "Authorization: Bearer $MEALIE_API_TOKEN" -H "Content-Type: application/json")

# sanity check — who am I?
curl -s "$B/api/users/self" "${H[@]}" | jq '{username, email, admin}'
```

Always pass `-s` to curl (clean output) and pipe reads through `jq`.

## When to Use

- "Add this recipe" / "import this recipe from <URL>"
- "Save this" with a **photo, screenshot, or handwritten card** of a recipe
- "Add this" with recipe text **pasted into chat** (or a transcribed voice note)
- "What should I cook?" / "find a recipe with chicken"
- "Put X on the meal plan for Friday" / "what's planned for today?"
- "Add milk and eggs to the shopping list"
- Browsing, tagging, or organizing the recipe collection

## Recipes

### Search / list
```bash
# free-text search, newest first, 1 page of 20
curl -s "$B/api/recipes?search=banana&page=1&perPage=20&orderBy=created_at&orderDirection=desc" "${H[@]}" \
  | jq '.items[] | {name, slug}'

# filter by category / tag slug
curl -s "$B/api/recipes?categories=dinner&tags=quick&perPage=50" "${H[@]}" | jq '.items[].name'
```
The list response is paginated: `{page, per_page, total, total_pages, items: [...]}`.

### Read one (full detail)
Recipes are addressed by **slug**, not numeric id.
```bash
curl -s "$B/api/recipes/banana-bread" "${H[@]}" \
  | jq '{name, recipeIngredient, recipeInstructions, recipeYield, totalTime}'
```

### Import from any source
A recipe can come in from a web link, a photo, a screenshot, a handwritten card, or
plain pasted text. See **[Importing recipes from any source](#importing-recipes-from-any-source)**
below — that's the main entry point for "add this recipe".

### Create manually
Two-step: create a stub to get a slug, then PUT the full body.
```bash
# 1. create stub -> returns slug string
SLUG=$(curl -s -X POST "$B/api/recipes" "${H[@]}" -d '{"name": "Weeknight Dal"}' | tr -d '"')

# 2. fetch, edit, and PUT the whole object back (PUT is the reliable update path)
curl -s "$B/api/recipes/$SLUG" "${H[@]}" > /tmp/r.json
# ...edit /tmp/r.json (set recipeIngredient, recipeInstructions, recipeYield, etc.)...
curl -s -X PUT "$B/api/recipes/$SLUG" "${H[@]}" -d @/tmp/r.json | jq '.slug'
```

Ingredient and instruction shapes:
```json
"recipeIngredient":   [{"note": "2 ripe bananas"}, {"note": "200g flour"}],
"recipeInstructions": [{"text": "Mash the bananas."}, {"text": "Mix and bake 50 min."}]
```

> **Update gotcha:** `PATCH /api/recipes/{slug}` *applies* partial changes but can
> return HTTP 500 on response serialization. Prefer **PUT** with the full object for
> updates; if you do use PATCH, re-GET to confirm rather than trusting the status code.

### Delete
```bash
curl -s -X DELETE "$B/api/recipes/$SLUG" "${H[@]}"
```

## Importing recipes from any source

When someone says "add this recipe" / "save this" / "import this", the source can be
anything. **You (the bot) are the universal importer** — you read links, images, and
text natively, so extract the recipe and push it to Mealie. Pick the path by what you
were given.

> Don't use Mealie's *built-in* AI import (`POST /api/recipes/create/image`) — it's
> intentionally left disabled on this instance (`aiEnabled: false`). You're the
> extractor: read the source yourself and write it through the normal API (Path C).

### Path A — a web URL (let Mealie scrape it)
```bash
curl -s -X POST "$B/api/recipes/create/url" "${H[@]}" \
  -d '{"url": "https://example.com/some-recipe", "includeTags": true}'
# -> returns the new recipe's slug as a bare JSON string

# many at once
curl -s -X POST "$B/api/recipes/create/url/bulk" "${H[@]}" \
  -d '{"imports": [{"url": "https://a.com/r1"}, {"url": "https://b.com/r2"}]}'
```
Server-side scrape, best for sites with proper recipe markup. Some sites block the
scraper (returns an HTTPException with no recipe) — fall back to Path B or C.

### Path B — you already have the page HTML / JSON-LD
When the scraper is blocked but you can fetch the page yourself, or you have a
schema.org Recipe JSON-LD blob, hand the raw markup to Mealie's parser:
```bash
HTML=$(curl -sL "https://example.com/some-recipe")          # or any saved page source
jq -n --arg d "$HTML" '{data: $d, includeTags: true}' \
  | curl -s -X POST "$B/api/recipes/create/html-or-json" "${H[@]}" -d @-
# -> slug. Needs schema.org Recipe markup (or JSON-LD) present in the HTML.
```

### Path C — a photo, screenshot, handwritten card, or pasted text (you extract)
This is the catch-all and works for **everything**: a snapshot of a cookbook page, an
Instagram/TikTok screenshot, a WhatsApp photo of grandma's index card, a transcribed
voice note, or freeform text someone pasted into chat.

1. **Read the source and extract** into this shape (drop fields you can't determine):
   ```json
   {
     "name": "Banana Bread",
     "recipeYield": "1 loaf",
     "totalTime": "1 hour",
     "recipeIngredient":   [{"note": "3 ripe bananas, mashed"}, {"note": "2 cups flour"}],
     "recipeInstructions": [{"text": "Heat oven to 175°C."}, {"text": "Mix and bake 50 min."}],
     "recipeCategory": [],
     "tags": []
   }
   ```
   Keep each ingredient as one freeform `note` string — don't try to split quantity/unit
   by hand (Path below does it better). Preserve the original language.

2. **Create the stub, then PUT the extracted body.** Fetch the stub first so you keep
   the required fields, merge yours in, and PUT the whole object back (verified 200):
   ```bash
   SLUG=$(curl -s -X POST "$B/api/recipes" "${H[@]}" -d '{"name": "Banana Bread"}' | tr -d '"')
   curl -s "$B/api/recipes/$SLUG" "${H[@]}" > /tmp/r.json
   jq '. + {
         recipeYield: "1 loaf", totalTime: "1 hour",
         recipeInstructions: [{text: "Heat oven to 175°C."}, {text: "Mix and bake 50 min."}],
         recipeIngredient:   [{note: "3 ripe bananas, mashed"}, {note: "2 cups all-purpose flour"}]
       }' /tmp/r.json > /tmp/full.json
   curl -s -X PUT "$B/api/recipes/$SLUG" "${H[@]}" -d @/tmp/full.json | jq '.slug'
   ```
   **Keep ingredients as freeform `note` strings — this is the reliable path.** Don't
   hand-build structured `{quantity, unit, food}` objects on the PUT: `unit`/`food` must
   reference rows that already exist, and bogus/empty refs make the PUT 500. Freeform
   notes display fine and stay searchable.

3. **(Optional) Preview structured ingredients** — Mealie's NLP parser splits a line
   into quantity + unit + food (handy if you want to confirm amounts or build a shopping
   list). This is read-only; it does **not** modify the recipe:
   ```bash
   curl -s -X POST "$B/api/parser/ingredients" "${H[@]}" \
     -d '{"parser": "nlp", "ingredients": ["2 cups all-purpose flour", "3 ripe bananas, mashed"]}' \
     | jq '.[].ingredient | {quantity, unit: .unit.name, food: .food.name, note}'
   # -> {quantity: 2, unit: "cup", food: "all-purpose flour"} ...
   ```
   To make those *stick* as structured fields you'd first create the foods/units
   (`POST /api/foods`, `POST /api/units`) and reference their IDs — usually not worth it.
   Easier: save freeform notes now, and use the **"Parse"** button in Mealie's recipe
   editor to structure them later in the UI.

### Picking a path
| You have… | Use |
|---|---|
| A recipe website link | Path A (`create/url`) |
| A link Path A choked on, or saved page source | Path B (`create/html-or-json`) |
| A photo / screenshot / handwritten card | Path C (you read the image → manual create) |
| Pasted recipe text, a voice note, a DM | Path C |
| 20 links to bulk-add | Path A `create/url/bulk` |

### Source link & importing ratings (avg + count)
When importing from a recipe portal (Chefkoch, etc.), also carry over the **original
link** and the **rating** so the collection stays traceable.

- **Original link → `orgURL`.** Path A (`create/url`) sets `orgURL` automatically to
  the source URL — nothing to do. For Path B/C, set it yourself in the PUT body:
  `jq '. + {orgURL: "https://…"}'`.

- **Star average → per-user rating endpoint, NOT the recipe PUT.** Mealie stores the
  rating per user, so `"rating"` in a recipe `PUT` is silently ignored (re-GET shows
  `null`). Set it through the user endpoint instead:
  ```bash
  ME=$(curl -s "$B/api/users/self" "${H[@]}" | jq -r .id)
  curl -s -X POST "$B/api/users/$ME/ratings/$SLUG" "${H[@]}" -d '{"rating": 4.7}'
  # re-GET the recipe -> .rating is now 4.7 (float accepted; UI rounds the stars)
  ```

- **Rating *count* has no native field → store as a note + in `extras`.** A note shows
  on the recipe page; `extras` is machine-readable for later filtering/sorting. Merge
  both into the recipe PUT body (keep any existing notes):
  ```bash
  curl -s "$B/api/recipes/$SLUG" "${H[@]}" \
    | jq --arg avg "4,7" --arg cnt "980" '. + {
        notes: ((.notes // []) | map(select(.title != "Chefkoch-Bewertung"))
                 + [{title: "Chefkoch-Bewertung", text: ($avg + " ★ von 5 (" + $cnt + " Bewertungen)")}]),
        extras: ((.extras // {}) + {chefkoch_rating: "4.7", chefkoch_rating_count: $cnt})
      }' > /tmp/r.json
  curl -s -X PUT "$B/api/recipes/$SLUG" "${H[@]}" -d @/tmp/r.json | jq '.slug'
  ```

> **"Most popular" on Chefkoch** = sort by *number of ratings*, not the 5-star average
> (the rating sort `…/rs/s0o3/…` surfaces 5★ recipes with only a handful of votes). Use
> the default relevance search `…/rs/s0/<query>/Rezepte.html` and pick the result with
> the highest *Bewertungen* count. Strip the tracking `#…` fragment off the recipe URL
> before importing.

## Meal Plans

Household-scoped. Entry types: `breakfast`, `lunch`, `dinner`, `side`.
```bash
# what's planned today
curl -s "$B/api/households/mealplans/today" "${H[@]}" | jq '.[].recipe.name'

# range
curl -s "$B/api/households/mealplans?start_date=2026-06-12&end_date=2026-06-19" "${H[@]}" \
  | jq '.items[] | {date, entryType, recipe: .recipe.name}'

# add a recipe to a day (recipeId is the recipe's UUID `id`, from GET /api/recipes/{slug})
curl -s -X POST "$B/api/households/mealplans" "${H[@]}" \
  -d '{"date": "2026-06-13", "entryType": "dinner", "recipeId": "<recipe-uuid>"}'

# add a free-text entry instead of a recipe
curl -s -X POST "$B/api/households/mealplans" "${H[@]}" \
  -d '{"date": "2026-06-14", "entryType": "lunch", "title": "Leftovers", "text": "fridge cleanout"}'

# random plan from rules
curl -s -X POST "$B/api/households/mealplans/random" "${H[@]}" -d '{"date": "2026-06-15", "entryType": "dinner"}'
```

## Shopping Lists

```bash
# lists
curl -s "$B/api/households/shopping/lists" "${H[@]}" | jq '.items[] | {id, name}'

# items on a list
LIST=<list-id>
curl -s "$B/api/households/shopping/items?queryFilter=shoppingListId%3D$LIST" "${H[@]}" \
  | jq '.items[] | {id, note, checked, quantity}'

# add an item
curl -s -X POST "$B/api/households/shopping/items" "${H[@]}" \
  -d "{\"shoppingListId\": \"$LIST\", \"note\": \"Milk\", \"quantity\": 1}"

# add several at once
curl -s -X POST "$B/api/households/shopping/items/create-bulk" "${H[@]}" \
  -d "{\"items\": [{\"shoppingListId\":\"$LIST\",\"note\":\"Eggs\"},{\"shoppingListId\":\"$LIST\",\"note\":\"Bread\"}]}"

# check off an item
curl -s -X PUT "$B/api/households/shopping/items/<item-id>" "${H[@]}" -d '{"checked": true}'

# push every ingredient of a recipe onto a list
curl -s -X POST "$B/api/households/shopping/lists/$LIST/recipe/<recipe-uuid>" "${H[@]}"
```

## Organizers (categories, tags, tools, foods, units)

```bash
curl -s "$B/api/organizers/categories" "${H[@]}" | jq '.items[] | {name, slug}'
curl -s "$B/api/organizers/tags"       "${H[@]}" | jq '.items[] | {name, slug}'
curl -s "$B/api/organizers/tools"      "${H[@]}" | jq '.items[].name'
curl -s "$B/api/foods?perPage=100"     "${H[@]}" | jq '.items[].name'
curl -s "$B/api/units?perPage=100"     "${H[@]}" | jq '.items[].name'

# create a category / tag
curl -s -X POST "$B/api/organizers/categories" "${H[@]}" -d '{"name": "Weeknight"}'
```
Assign categories/tags to a recipe by including them in the recipe PUT body:
`"recipeCategory": [{"id": "...", "name": "...", "slug": "..."}]`, `"tags": [...]`.

## Notes

- **Recipes use slugs; meal-plan/shopping references use the recipe's UUID `id`.** Get
  both from `GET /api/recipes/{slug}` (`.slug` and `.id`).
- List endpoints share the same query params: `page`, `perPage`, `orderBy`,
  `orderDirection`, plus resource filters (`search`, `categories`, `tags`, `foods`).
- Meal plans and shopping lists live under `/api/households/...`; group-wide organizers
  under `/api/organizers/...` and `/api/foods`, `/api/units`.
- The token is admin-scoped — it can read and write everything in Moritz's group.
- Full live API reference: `https://mealie.mchristoffers.dev/openapi.json` (or `/docs`).
- Deployment details (Coolify service UUID, redeploy, DNS) live in the mealie repo at
  `git/mchristoffers/mealie/deploy/README.md`.
